# Passo 8: series de NDVI, EVI e NDMI a partir das bandas, e BFAST Lite e votacao para o
# EVI e o NDMI, com os mesmos parametros e pixels do NDVI
# Rodar dentro desta pasta: Rscript 8_indices.R
# Saidas: dados/indices.csv, resultados/indices/<EVI|NDMI>/{quebras_pixel,eventos_buffer}.csv

suppressMessages(library(bfast))
source("parametros.R")
source("funcoes.R")

bandas <- read.csv("dados/bandas_gee.csv")
pixels <- read.csv("dados/pixels.csv")

# duas imagens no mesmo dia: fica a de aquisicao mais cedo
bandas <- bandas[order(bandas$longitude, bandas$latitude, bandas$datetime, bandas$img_id), ]
bandas <- bandas[!duplicated(paste(bandas$longitude, bandas$latitude, bandas$date)), ]

series <- merge(pixels[, c("pixel", "longitude", "latitude")], bandas, by = c("longitude", "latitude"))

# reflectancia de 0 a 1
azul <- series$B2 / 10000
vermelho <- series$B4 / 10000
nir <- series$B8 / 10000
swir <- series$B11 / 10000

series$NDVI <- (nir - vermelho) / (nir + vermelho)
series$EVI <- 2.5 * (nir - vermelho) / (nir + 6 * vermelho - 7.5 * azul + 1)
series$NDMI <- (nir - swir) / (nir + swir)

series <- series[order(series$pixel, series$date), c("pixel", "date", "NDVI", "EVI", "NDMI")]
write.csv(series, "dados/indices.csv", row.names = FALSE)
series$date <- as.Date(series$date)

for (indice in c("EVI", "NDMI")) {
  pasta <- file.path("resultados/indices", indice)
  dir.create(pasta, recursive = TRUE, showWarnings = FALSE)

  quebras <- roda_lite(series, pixels, coluna = indice)
  write.csv(quebras, file.path(pasta, "quebras_pixel.csv"), row.names = FALSE)

  eventos <- agrupa_eventos(quebras, pixels)
  write.csv(eventos, file.path(pasta, "eventos_buffer.csv"), row.names = FALSE)

  cat(indice, "| pixels com quebra:", length(unique(quebras$pixel)), "| grupos:", nrow(eventos),
      "| aceitos:", sum(eventos$aceito), "\n")
}
