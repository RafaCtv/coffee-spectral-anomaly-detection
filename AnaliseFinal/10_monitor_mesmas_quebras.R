# Passo 10: BFAST Monitor de NDVI, EVI e NDMI nas quebras aceitas do NDVI, com os mesmos
# periodos estaveis, para comparar a deteccao e as datas dos alarmes de cada indice
# Rodar dentro desta pasta, depois do passo 8: Rscript 10_monitor_mesmas_quebras.R
# Saida: resultados/indices/monitor_mesmas_quebras.csv

suppressMessages(library(bfast))
source("parametros.R")
source("funcoes.R")

indices <- c("NDVI", "EVI", "NDMI")

series <- read.csv("dados/indices.csv")
series$date <- as.Date(series$date)
pixels <- read.csv("dados/pixels.csv")

eventos <- read.csv("resultados/eventos_buffer.csv")
eventos <- eventos[eventos$aceito, ]
for (coluna in c("data", "primeira", "ultima")) eventos[[coluna]] <- as.Date(eventos[[coluna]])

saida <- NULL
alarmes <- NULL
detectados <- NULL
for (indice in indices) {
  r <- roda_monitor(series, pixels, eventos, par_monitor, coluna = indice)
  if (is.null(saida)) saida <- r$eventos[, c("buffer", "evento", "direcao", "quebra", "pixels")]

  # alarme mediano dos pixels que alarmaram na janela
  na_janela <- r$pixels[r$pixels$situacao == "na_janela", ]
  mediana <- sapply(seq_len(nrow(saida)), function(k) {
    x <- na_janela[na_janela$buffer == saida$buffer[k] & na_janela$evento == saida$evento[k], ]
    if (nrow(x) > 0) as.numeric(median(as.Date(x$alarme))) else NA
  })
  alarmes <- cbind(alarmes, mediana)
  detectados <- cbind(detectados, r$eventos$detectado)

  saida[[paste0("detectado_", indice)]] <- r$eventos$detectado
  saida[[paste0("pixels_na_janela_", indice)]] <- r$eventos$pixels_na_janela
  saida[[paste0("atraso_mediano_", indice)]] <- r$eventos$atraso_mediano_dias
  saida[[paste0("alarme_mediano_", indice)]] <- as.Date(mediana, origin = "1970-01-01")
}

# dias entre o primeiro e o ultimo alarme mediano, so entre os indices que detectaram a quebra
saida$diferenca_alarmes_dias <- sapply(seq_len(nrow(saida)), function(k) {
  v <- alarmes[k, detectados[k, ]]
  if (length(v) >= 2) diff(range(v)) else NA
})
write.csv(saida, "resultados/indices/monitor_mesmas_quebras.csv", row.names = FALSE)

print(saida[, c("buffer", "evento", paste0("detectado_", indices), "diferenca_alarmes_dias")], row.names = FALSE)
