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

  # write.csv grava 15 digitos significativos, entao a coordenada do alertas.csv
  # difere da serie na ultima casa (~1e-14) e o == nao casa. Buscar a mais proxima.
  i   <- which.min((serie$longitude - alvo$longitude)^2 +
                   (serie$latitude  - alvo$latitude)^2)
  obs <- serie[serie$longitude == serie$longitude[i] &
               serie$latitude  == serie$latitude[i], ]

  if (nrow(obs) == 0)
    cat("monitor_pixel.png nao gerado: pixel do alerta ausente na serie\n")

  if (nrow(obs) > 0) {
    m <- cfg_modo(cfg)
    nts <- monta_ts(obs$date, obs$NDVI)

    # Entrada do bfastmonitor: a serie agregada e o vetor que o bfastts devolve.
    v  <- as.numeric(nts)
    ok <- !is.na(v)

    png("figuras/serie_bfastts.png", width = 1400, height = 800, res = 120)
    par(mfrow = c(2, 1), mar = c(4, 4.5, 3.5, 1))

    plot(obs$date, obs$NDVI, type = "p", pch = 19, cex = 0.5, col = "grey30",
         xlab = "", ylab = "NDVI", ylim = c(0, 1), main = "")
    title(main = sprintf("Antes do bfastts: serie apos agregacao pixel-dia (%d observacoes)", nrow(obs)),
          line = 1.9, cex.main = 1.0)
    mtext(sprintf("pixel %.5f, %.5f  |  %s a %s",
                  obs$longitude[1], obs$latitude[1],
                  format(min(obs$date), "%d/%m/%Y"),
                  format(max(obs$date), "%d/%m/%Y")),
          side = 3, line = 0.4, cex = 0.7)

    # type="p": com a grade quase toda em NA nao ha pontos consecutivos, e a
    # linha padrao do plot.ts sairia em branco.
    plot(nts, type = "p", pch = 20, cex = 0.45, col = "grey30",
         xlab = "", ylab = "NDVI", ylim = c(0, 1), main = "")
    title(main = sprintf("Depois do bfastts: serie usada pelo bfastmonitor (%d pontos)",
                         sum(ok)), line = 1.9, cex.main = 1.0)
    mtext(sprintf("frequencia 365: %d posicoes, %.1f%% com dado, sem interpolacao",
                  length(v), 100 * mean(ok)),
          side = 3, line = 0.4, cex = 0.7)
    dev.off()
    par(mfrow = c(1, 1))
    cat("figuras/serie_bfastts.png\n")

    bm <- tryCatch(
      bfastmonitor(nts, start = data_para_decimal(m$monitor_inicio),
                   formula = as.formula(paste("response ~", cfg$bfast_formula)),
                   order = as.integer(cfg$bfast_order),
                   history = cfg_historico(cfg)),
      error = function(e) NULL)

    if (!is.null(bm)) {
      # Resolucao menor que as outras: a legenda do plot.bfastmonitor tem 6
      # entradas e invade a area de dados em fonte maior.
      png("figuras/monitor_pixel.png", width = 1500, height = 850, res = 130)
      par(mar = c(4, 4.5, 3, 1))
      # Coordenada do alerta; quebra e magnitude sao desta execucao e prevalecem
      # se o config mudou desde a gravacao do alerta.
      plot(bm, ylab = "NDVI", xlab = "tempo (anos)",
           main = sprintf("Pixel %.5f, %.5f  |  historico %s  |  %s  |  magnitude %+.3f",
                          alvo$longitude, alvo$latitude, cfg_historico(cfg),
                          if (is.na(bm$breakpoint)) "sem quebra"
                          else format(decimal_para_data(bm$breakpoint), "%d/%m/%Y"),
                          bm$magnitude))
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
