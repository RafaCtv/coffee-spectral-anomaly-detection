# Figuras de saida a partir de estado/alertas.csv.
# Uso: Rscript R/figuras.R

source("R/config.R")
source("R/funcoes.R")

cfg <- le_config()
dir.create("figuras", showWarnings = FALSE, recursive = TRUE)

if (!file.exists("estado/alertas.csv")) {
  stop("nenhum alerta ainda. Rode antes: Rscript R/monitora.R")
}

a <- read.csv("estado/alertas.csv", stringsAsFactors = FALSE)
a$data_quebra   <- as.Date(a$data_quebra)
a$data_deteccao <- as.Date(a$data_deteccao)
cat("alertas:", nrow(a), "\n")

# Distribuicao espacial
faixas <- pretty(range(a$data_quebra), n = 6)
rotulos <- paste(format(head(faixas, -1), "%m/%y"),
                 format(tail(faixas, -1), "%m/%y"), sep = "-")
paleta <- colorRampPalette(c("yellow", "orange", "red", "darkred"))(length(rotulos))
classe <- cut(a$data_quebra, breaks = faixas, labels = rotulos, right = FALSE)

png("figuras/mapa_alertas.png", width = 1400, height = 1200, res = 200)
plot(a$longitude, a$latitude, col = paleta[as.integer(classe)],
     pch = 15, cex = 0.6, asp = 1,
     xlab = "Longitude", ylab = "Latitude",
     main = "Alertas por pixel (cor = periodo da quebra)")
legend("topright", legend = rotulos, fill = paleta,
       title = "Periodo", bty = "n", cex = 0.7)
dev.off()

# Distribuicao temporal
png("figuras/periodo_alertas.png", width = 1400, height = 1000, res = 200)
barplot(table(format(a$data_quebra, "%Y-%m")), las = 2, cex.names = 0.6,
        xlab = "", ylab = "N de pixels",
        main = "Distribuicao temporal dos alertas")
dev.off()

# Saida do bfastmonitor no pixel de maior queda
if (file.exists("dados/serie_ndvi.csv")) {
  serie <- le_serie("dados/serie_ndvi.csv", verbose = FALSE, politica = cfg$agregacao_dia)
  alvo  <- a[which.min(a$magnitude), ]
  obs   <- serie[serie$longitude == alvo$longitude &
                 serie$latitude  == alvo$latitude, ]

  if (nrow(obs) > 0) {
    m <- cfg_modo(cfg)
    nts <- monta_ts(obs$date, obs$NDVI)
    bm <- tryCatch(
      bfastmonitor(nts, start = data_para_decimal(m$monitor_inicio),
                   formula = as.formula(paste("response ~", cfg$bfast_formula)),
                   order = as.integer(cfg$bfast_order), history = "all"),
      error = function(e) NULL)

    if (!is.null(bm)) {
      # res menor que as outras: a legenda do plot.bfastmonitor tem 6 entradas e
      # invade a area de dados quando a fonte fica grande.
      png("figuras/monitor_pixel.png", width = 1500, height = 850, res = 130)
      par(mar = c(4, 4.5, 3, 1))
      plot(bm, ylab = "NDVI", xlab = "tempo (anos)",
           main = sprintf("Pixel %.5f, %.5f  |  magnitude %+.3f",
                          alvo$longitude, alvo$latitude, alvo$magnitude))
      dev.off()
      cat("figuras/monitor_pixel.png\n")
    } else {
      cat("monitor_pixel.png nao gerado: monitor_inicio (",
          format(m$monitor_inicio), ") fora do periodo da serie (",
          format(min(obs$date)), " a ", format(max(obs$date)), ")\n", sep = "")
    }
  }
}

cat("figuras/mapa_alertas.png\nfiguras/periodo_alertas.png\n")
