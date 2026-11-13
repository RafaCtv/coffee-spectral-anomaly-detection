# Passo 2: um NDVI por pixel e dia, e a area amostral e o talhao de cada pixel
# Rodar dentro desta pasta: Rscript 2_organiza_pixels.R
# Saidas: dados/ndvi.csv, dados/pixels.csv

arq_buffers <- "../area/buffers_amostrais.geojson"
arq_talhoes <- "../area/fazenda_car.geojson"

ndvi <- read.csv("dados/ndvi_gee.csv")

# duas imagens no mesmo dia: fica a de aquisicao mais cedo
ndvi <- ndvi[order(ndvi$longitude, ndvi$latitude, ndvi$datetime, ndvi$img_id), ]
ndvi <- ndvi[!duplicated(paste(ndvi$longitude, ndvi$latitude, ndvi$date)), c("longitude", "latitude", "date", "NDVI")]

# contorno de cada poligono do geojson (lon, lat)
le_poligonos <- function(arquivo) {
  lapply(jsonlite::fromJSON(arquivo, simplifyVector = FALSE)$features, function(f) {
    g <- f$geometry
    contorno <- if (g$type == "MultiPolygon") g$coordinates[[1]][[1]] else g$coordinates[[1]]
    matrix(unlist(contorno), ncol = 2, byrow = TRUE)
  })
}

# ponto dentro do poligono (regra do raio)
ponto_dentro <- function(x, y, pol) {
  n <- nrow(pol)
  dentro <- FALSE
  for (i in 1:n) {
    j <- if (i == 1) n else i - 1
    if ((pol[i, 2] > y) != (pol[j, 2] > y) &&
        x < (pol[j, 1] - pol[i, 1]) * (y - pol[i, 2]) / (pol[j, 2] - pol[i, 2]) + pol[i, 1]) dentro <- !dentro
  }
  dentro
}

buffers <- le_poligonos(arq_buffers)
id_buffer <- sapply(jsonlite::fromJSON(arq_buffers, simplifyVector = FALSE)$features,
                    function(f) f$properties$id)
talhoes <- le_poligonos(arq_talhoes)   # talhao 1 a 6, na ordem do arquivo

pixels <- unique(ndvi[, c("longitude", "latitude")])
pixels <- pixels[order(pixels$longitude, pixels$latitude), ]
pixels$buffer <- NA
pixels$talhao <- NA
for (i in 1:nrow(pixels)) {
  for (k in seq_along(buffers)) {
    if (ponto_dentro(pixels$longitude[i], pixels$latitude[i], buffers[[k]])) { pixels$buffer[i] <- id_buffer[k]; break }
  }
  for (k in seq_along(talhoes)) {
    if (ponto_dentro(pixels$longitude[i], pixels$latitude[i], talhoes[[k]])) { pixels$talhao[i] <- k; break }
  }
}

# o GEE inclui pixels que so tocam o circulo: vao para a area com o centro mais perto
for (i in which(is.na(pixels$buffer))) {
  d <- sapply(buffers, function(b) sum((colMeans(b) - c(pixels$longitude[i], pixels$latitude[i]))^2))
  pixels$buffer[i] <- id_buffer[which.min(d)]
}

# nome do pixel: exemplo b03_p07 = setimo pixel da area 3
pixels$pixel <- NA
for (b in unique(pixels$buffer)) {
  linhas <- which(pixels$buffer == b)
  pixels$pixel[linhas] <- sprintf("b%02d_p%02d", b, seq_along(linhas))
}

ndvi <- merge(pixels, ndvi, by = c("longitude", "latitude"))
ndvi <- ndvi[order(ndvi$pixel, ndvi$date), c("pixel", "date", "NDVI")]
pixels <- pixels[order(pixels$buffer, pixels$pixel), c("pixel", "buffer", "talhao", "longitude", "latitude")]
write.csv(ndvi, "dados/ndvi.csv", row.names = FALSE)
write.csv(pixels, "dados/pixels.csv", row.names = FALSE)

cat("pixels:", nrow(pixels), "| pixel-dias:", nrow(ndvi), "\n")
