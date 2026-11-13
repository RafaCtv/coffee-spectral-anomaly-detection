# Passo 4: BFAST Monitor nas quebras aceitas pelo Lite, com todo o periodo estavel como
# historico (history = "all") e o monitoramento comecando pouco antes da quebra
# Rodar dentro desta pasta: Rscript 4_bfast_monitor.R
# Saidas: resultados/monitor_pixels.csv, resultados/monitor_eventos.csv,
#         figuras/por_pixel/bfastMonitor/buffer_XX/evento_AAAA-MM-DD/<pixel>.png

suppressMessages(library(bfast))
source("parametros.R")
source("funcoes.R")

ndvi <- read.csv("dados/ndvi.csv")
ndvi$date <- as.Date(ndvi$date)
pixels <- read.csv("dados/pixels.csv")

eventos <- read.csv("resultados/eventos_buffer.csv")
eventos <- eventos[eventos$aceito, ]
for (coluna in c("data", "primeira", "ultima")) eventos[[coluna]] <- as.Date(eventos[[coluna]])

r <- roda_monitor(ndvi, pixels, eventos, par_monitor, pasta_graficos = "figuras/por_pixel/bfastMonitor")
write.csv(r$pixels, "resultados/monitor_pixels.csv", row.names = FALSE)
write.csv(r$eventos, "resultados/monitor_eventos.csv", row.names = FALSE)

cat("quebras testadas:", nrow(r$eventos), "| detectadas:", sum(r$eventos$detectado), "\n")
print(table(r$pixels$situacao))
