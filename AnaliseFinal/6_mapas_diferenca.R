# Passo 6: mapa da diferenca de NDVI (depois - antes) de cada quebra aceita nos seis
# talhoes e diferenca media dentro da area amostral e no restante dos talhoes.
# Negativo (vermelho) = NDVI caiu, positivo (azul) = subiu, escala fixa de -0,5 a +0,5
# Rodar dentro desta pasta: Rscript 6_mapas_diferenca.R
# Entradas: dados/ndvi_quebras.csv (passo 5), resultados/eventos_buffer.csv, ../area/*.geojson
# Saidas:   figuras/mapas_diferenca/buffer_XX_quebra_AAAA-MM-DD.png, resultados/diferenca_quebras.csv

ndvi    <- read.csv("dados/ndvi_quebras.csv")
eventos <- read.csv("resultados/eventos_buffer.csv")
eventos <- eventos[eventos$aceito, ]
pasta <- "figuras/mapas_diferenca"; dir.create(pasta, recursive = TRUE, showWarnings = FALSE)


# coordenadas UTM 23S (WGS84), para cada pixel virar um quadrado de 10 m no mapa
utm23s <- function(lon, lat) {
  a <- 6378137; f <- 1 / 298.257223563; e2 <- f * (2 - f); ep2 <- e2 / (1 - e2); k0 <- 0.9996
  phi <- lat * pi / 180
  A <- cos(phi) * (lon + 45) * pi / 180            # meridiano central da zona 23: -45
  N <- a / sqrt(1 - e2 * sin(phi)^2)
  T <- tan(phi)^2
  C <- ep2 * cos(phi)^2
  M <- a * ((1 - e2 / 4 - 3 * e2^2 / 64 - 5 * e2^3 / 256) * phi -
            (3 * e2 / 8 + 3 * e2^2 / 32 + 45 * e2^3 / 1024) * sin(2 * phi) +
            (15 * e2^2 / 256 + 45 * e2^3 / 1024) * sin(4 * phi) -
            (35 * e2^3 / 3072) * sin(6 * phi))
  x <- 500000 + k0 * N * (A + (1 - T + C) * A^3 / 6 + (5 - 18 * T + T^2 + 72 * C - 58 * ep2) * A^5 / 120)
  y <- 10000000 + k0 * (M + N * tan(phi) * (A^2 / 2 + (5 - T + 9 * C + 4 * C^2) * A^4 / 24 +
                                            (61 - 58 * T + T^2 + 600 * C - 330 * ep2) * A^6 / 720))
  list(x = x, y = y)
}

p <- utm23s(ndvi$longitude, ndvi$latitude)
ndvi$x <- p$x
ndvi$y <- p$y

le_poligonos <- function(arquivo) {
  lapply(jsonlite::fromJSON(arquivo, simplifyVector = FALSE)$features, function(f) {
    g <- f$geometry
    contorno <- if (g$type == "MultiPolygon") g$coordinates[[1]][[1]] else g$coordinates[[1]]
    m <- matrix(unlist(contorno), ncol = 2, byrow = TRUE)
    q <- utm23s(m[, 1], m[, 2])
    cbind(q$x, q$y)
  })
}
talhoes <- le_poligonos("../area/fazenda_car.geojson")
buffers <- le_poligonos("../area/buffers_amostrais.geojson")
id_buffer <- sapply(jsonlite::fromJSON("../area/buffers_amostrais.geojson", simplifyVector = FALSE)$features,
                    function(f) f$properties$id)

# ponto dentro do poligono (regra do raio)
ponto_dentro <- function(x, y, pol) {
  n <- nrow(pol)
  dentro <- FALSE
  for (k in 1:n) {
    kk <- if (k == 1) n else k - 1
    if ((pol[k, 2] > y) != (pol[kk, 2] > y) &&
        x < (pol[kk, 1] - pol[k, 1]) * (y - pol[k, 2]) / (pol[kk, 2] - pol[k, 2]) + pol[k, 1]) dentro <- !dentro
  }
  dentro
}


# vermelho (caiu) - cinza (sem mudanca) - azul (subiu)
cores_dif <- colorRampPalette(c("#8f1f1e", "#e34948", "#f4b9b8", "#f0efec", "#b7d3f6", "#3987e5", "#104281"))(100)


resumo <- data.frame()

for (i in 1:nrow(eventos)) {
  b  <- eventos$buffer[i]
  ev <- eventos$data[i]
  a <- ndvi[ndvi$buffer == b & ndvi$evento == ev & ndvi$momento == "antes", ]
  d <- ndvi[ndvi$buffer == b & ndvi$evento == ev & ndvi$momento == "depois", ]
  if (nrow(a) == 0 || nrow(d) == 0) next   # sem imagem limpa na janela de 90 dias
  m <- merge(a[, c("longitude", "latitude", "x", "y", "NDVI")], d[, c("longitude", "latitude", "NDVI")],
             by = c("longitude", "latitude"), suffixes = c("_antes", "_depois"))
  m$dif <- m$NDVI_depois - m$NDVI_antes

  pol <- buffers[[which(id_buffer == b)]]
  no_buffer <- sapply(1:nrow(m), function(j) ponto_dentro(m$x[j], m$y[j], pol))
  resumo <- rbind(resumo, data.frame(
    buffer = b, evento = ev, magnitude_bfast = eventos$magnitude_mediana[i],
    data_antes = a$date[1], data_depois = d$date[1],
    dif_media_buffer = round(mean(m$dif[no_buffer], na.rm = TRUE), 3),
    dif_media_talhoes = round(mean(m$dif[!no_buffer], na.rm = TRUE), 3)))

  # cor de cada pixel na escala fixa de -0,5 a +0,5; sem dado (nuvem) em cinza
  k <- round((pmin(pmax(m$dif, -0.5), 0.5) + 0.5) * 99) + 1
  cor_pixel <- cores_dif[k]
  cor_pixel[is.na(m$dif)] <- "#d6d6d3"

  png(file.path(pasta, sprintf("buffer_%02d_quebra_%s.png", b, ev)),
      width = 3.4, height = 2.75, units = "in", res = 300, pointsize = 8)
  layout(matrix(1:2, ncol = 1), heights = c(5, 1))

  # mapa: pixels, talhoes, areas amostrais (a da quebra em preto) e escala de 200 m
  par(mar = c(0.2, 0.2, 0.2, 0.2))
  plot.new()
  plot.window(xlim = range(m$x) + c(-10, 10), ylim = range(m$y) + c(-30, 10), asp = 1)
  rect(m$x - 5, m$y - 5, m$x + 5, m$y + 5, col = cor_pixel, border = NA)
  for (t in talhoes) polygon(t, border = "#8a8a86", lwd = 0.6)
  for (j in seq_along(buffers)) {
    destaque <- id_buffer[j] == b
    polygon(buffers[[j]], border = if (destaque) "#000000" else "#6b6b67", lwd = if (destaque) 1.8 else 0.5)
  }
  x0 <- min(m$x); y0 <- min(m$y) - 20
  segments(x0, y0, x0 + 200, y0, lwd = 2)
  text(x0 + 100, y0 + 30, "200 m", cex = 0.8)

  # barra de cor
  par(mar = c(2.4, 3, 0.2, 3))
  plot.new()
  plot.window(xlim = c(-0.5, 0.5), ylim = c(0, 1))
  rect(seq(-0.5, 0.49, 0.01), 0, seq(-0.49, 0.5, 0.01), 1, col = cores_dif, border = NA)
  axis(1, at = seq(-0.5, 0.5, 0.25), labels = format(seq(-0.5, 0.5, 0.25), decimal.mark = ","),
       cex.axis = 0.85, tcl = -0.25, mgp = c(1.5, 0.3, 0))
  mtext("Diferença de NDVI (depois − antes)", side = 1, line = 1.4, cex = 0.7)
  dev.off()
}

write.csv(resumo, "resultados/diferenca_quebras.csv", row.names = FALSE)
