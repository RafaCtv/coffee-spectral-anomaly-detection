# ============================================================
# BFASTMonitor em TODOS os pixels do talhão (sem agregação)
# Dados: Sentinel-2 SR/L2A. Histórico 2019-2021; monitoramento 2021+ (geada jul/2021).
# Objetivo: ver em quais períodos há mais detecção de quebra.
# CSV por pixel: colunas "longitude", "latitude", "date", "datetime", "NDVI"
# ============================================================

# Series temporais:
arquivo <- "D:/Unifei/TFG/NovaTentativa/serie_NDVI_sem_mascara.csv"
#arquivo <- "D:/Unifei/TFG/NovaTentativa/serie_NDVI_com_mascara.csv"


df <- read.csv(arquivo, stringsAsFactors = FALSE)
df$date <- as.Date(df$date)

# 

# Identificador de cada pixel
df$pixel <- paste(df$longitude, df$latitude, sep = "_")
cat("Número de pixels:", length(unique(df$pixel)), "\n")

# Função que roda o BFASTMonitor na série de um pixel
roda_bfast <- function(sub) {
  sub <- sub[order(sub$date), ]
  sub <- sub[!is.na(sub$NDVI), ]
  if (nrow(sub) < 10) return(NULL)
  nts <- bfastts(sub$NDVI, sub$date, type = "irregular")
  out <- tryCatch(
    bfastmonitor(nts, 
                 start = c(2021, 1),
                 formula = response ~ harmon, 
                 order = 1, 
                 history = "all"),
    error = function(e) NULL
  )
  if (is.null(out)) return(NULL)
  data.frame(longitude = sub$longitude[1], latitude = sub$latitude[1],
             breakpoint = out$breakpoint, magnitude = out$magnitude)
}

# Particiona por pixel UMA vez e roda em cada grupo
grupos <- split(df, df$pixel)
resultados <- do.call(rbind, lapply(grupos, roda_bfast))

# --- Alternativa PARALELA (Windows) ainda não testei essa, mais rápida em milhões de linhas ---
# library(parallel)
# cl <- makeCluster(detectCores() - 1)
# clusterEvalQ(cl, library(bfast))
# resultados <- do.call(rbind, parLapply(cl, grupos, roda_bfast))
# stopCluster(cl)

# Converte o ano decimal (ex. 2021.329) para data de calendário (dia/mês/ano).
# Vetorizada e segura contra NA (pixels sem quebra ficam NA).
decimal_para_data <- function(x) {
  out <- as.Date(rep(NA, length(x)))
  ok  <- !is.na(x)
  ano <- floor(x[ok])
  ini <- as.Date(paste0(ano, "-01-01"))
  fim <- as.Date(paste0(ano + 1, "-01-01"))
  out[ok] <- ini + (x[ok] - ano) * as.numeric(fim - ini)
  out
}
resultados$data_quebra <- decimal_para_data(resultados$breakpoint)

write.csv(resultados, "bfast_resultados_porpixel.csv", row.names = FALSE)

com_quebra <- resultados[!is.na(resultados$breakpoint), ]
cat("Pixels com quebra:", nrow(com_quebra), "de", nrow(resultados), "\n")

# Datas exatas (dia/mês/ano) das primeiras quebras detectadas
cat("\nExemplos de datas de quebra (dia/mês/ano):\n")
print(head(format(com_quebra$data_quebra, "%d/%m/%Y"), 15))

# ============================================================
# Em quais PERÍODOS há mais quebras
# ============================================================

# Converte a data decimal da quebra para ano-mês
ano  <- floor(com_quebra$breakpoint)
mes  <- floor((com_quebra$breakpoint - ano) * 12) + 1
anomes <- sprintf("%d-%02d", ano, mes)

# Resumo por mês: nº de quebras + magnitude média (sinal = direção da mudança)
com_quebra$anomes <- anomes
resumo <- aggregate(magnitude ~ anomes, data = com_quebra,
                    FUN = function(m) c(n = length(m), media = mean(m)))
resumo <- data.frame(anomes = resumo$anomes,
                     n = resumo$magnitude[, "n"],
                     magnitude_media = round(resumo$magnitude[, "media"], 4))
resumo <- resumo[order(-resumo$n), ]
cat("\nQuebras por mês (nº e magnitude média; negativo = queda de NDVI):\n")
print(head(resumo, 15), row.names = FALSE)

# Histograma temporal das quebras
hist(com_quebra$breakpoint, breaks = 40,
     xlab = "Data da quebra (ano decimal)", ylab = "Nº de pixels",
     main = "Períodos com mais detecção de quebra")

# Mapa espacial das quebras: cor = FAIXA de período (mesmo gradiente de antes)
limites <- as.Date(c("2021-01-01", "2021-04-01", "2021-07-01", "2021-10-01",
                     "2022-01-01", "2022-07-01", "2023-01-01"))
rotulos <- c("01-03/2021", "04-06/2021", "07-09/2021",
             "10-12/2021", "01-06/2022", "07-12/2022")
paleta  <- colorRampPalette(c("yellow", "orange", "red", "darkred"))(length(rotulos))
classe  <- cut(com_quebra$data_quebra, breaks = limites,
               labels = rotulos, right = FALSE)

plot(com_quebra$longitude, com_quebra$latitude,
     col = paleta[as.integer(classe)], pch = 15, cex = 0.6, asp = 1,
     xlab = "Longitude", ylab = "Latitude",
     main = "Quebras por pixel (cor = período da quebra)")
legend("topright", legend = rotulos, fill = paleta,
       title = "Período da quebra", bty = "n", cex = 0.8)
