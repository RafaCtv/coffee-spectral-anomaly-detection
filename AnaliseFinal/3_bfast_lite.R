# Passo 3: BFAST Lite na serie completa de cada pixel, votacao por area amostral
# e fase do ciclo e direcao de cada quebra. Os grupos aceitos delimitam os periodos estaveis
# Rodar dentro desta pasta: Rscript 3_bfast_lite.R
# Saidas: resultados/quebras_pixel.csv, resultados/eventos_buffer.csv,
#         figuras/por_pixel/bfastLite/buffer_XX/<pixel>.png

suppressMessages(library(bfast))
source("parametros.R")
source("funcoes.R")

ndvi <- read.csv("dados/ndvi.csv")
pixels <- read.csv("dados/pixels.csv")
dir.create("resultados", showWarnings = FALSE)

quebras <- roda_lite(ndvi, pixels, pasta_graficos = "figuras/por_pixel/bfastLite")
write.csv(quebras, "resultados/quebras_pixel.csv", row.names = FALSE)

eventos <- agrupa_eventos(quebras, pixels)
write.csv(eventos, "resultados/eventos_buffer.csv", row.names = FALSE)

cat("pixels com quebra:", length(unique(quebras$pixel)), "| grupos:", nrow(eventos),
    "| aceitos:", sum(eventos$aceito), "\n")
