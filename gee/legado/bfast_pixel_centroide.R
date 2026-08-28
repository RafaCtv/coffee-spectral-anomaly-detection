# ============================================================
# BFASTMonitor sobre a série de UM pixel (centroide do maior talhão)
# CSV: serie_NDVI_pixel_centroide.csv  -> colunas "date", "datetime", "NDVI"
# Já é 1 valor por data: sem agregação espacial.
# ============================================================

#arquivo <- "D:/Unifei/TFG/NovaTentativa/centroidPixel/serie_NDVI_pixel_centroide_comMascara_nuvem.csv"
arquivo <- "D:/Unifei/TFG/NovaTentativa/centroidPixel/serie_NDVI_pixel_centroide_semMascara_nuvem.csv"

df <- read.csv(arquivo, stringsAsFactors = FALSE)
df$date <- as.Date(df$date)
df <- df[order(df$date), ]

# Deduplicação leve (sobreposição de órbita pode repetir a mesma aquisição)
antes <- nrow(df)
df <- df[!duplicated(df[, c("datetime", "NDVI")]), ]
cat("Linhas removidas (duplicatas):", antes - nrow(df),
    "| restantes:", nrow(df), "\n")

# Monta a série temporal regular que o bfast entende (lacunas viram NA)
nts <- bfastts(df$NDVI, df$date, type = "irregular")

# BFASTMonitor: histórico = 2019-2021 (estável, pré-geada de MG, dados S2 SR/L2A);
# monitoramento a partir de 2021 -> detecta a PRIMEIRA quebra (geada jul/2021).
bm <- bfastmonitor(nts,
                   start   = c(2021, 1),
                   formula = response ~ harmon,
                   order   = 1,
                   history = "all")  # alternativa: history = "ROC"

# Converte o ano decimal (ex. 2021.329) para data de calendário (dia/mês/ano)
decimal_para_data <- function(x) {
  if (is.na(x)) return(as.Date(NA))
  ano <- floor(x)
  ini <- as.Date(paste0(ano, "-01-01"))
  fim <- as.Date(paste0(ano + 1, "-01-01"))
  as.Date(ini + (x - ano) * as.numeric(fim - ini))
}

# Resultados
print(bm)
if (is.na(bm$breakpoint)) {
  cat("Nenhuma quebra detectada no período de monitoramento.\n")
} else {
  data_quebra <- decimal_para_data(bm$breakpoint)
  cat("Data da quebra (ano decimal):", bm$breakpoint, "\n")
  cat("Data da quebra (calendário):", format(data_quebra, "%d/%m/%Y"), "\n")
  cat("Magnitude da quebra:", bm$magnitude, "\n")
}

# Gráfico: histórico, modelo ajustado, período monitorado e a quebra
plot(bm)
