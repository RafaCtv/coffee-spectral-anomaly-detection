# Execucao do BFAST Monitor fora da maquina de estados, para inspecao.
#
#   Rscript R/inspeciona_serie.R [centroide|pixel] [replay|operacao]
#
# centroide  serie do pixel mais proximo do centroide da area; imprime o
#            resultado e compara a serie do CSV com a que o bfastts entrega
# pixel      uma execucao independente por pixel; agrega as quebras por mes e
#            projeta no espaco, como na analise por-pixel do artigo

source("R/config.R")
source("R/funcoes.R")

args <- commandArgs(trailingOnly = TRUE)
GRAN <- if (length(args) >= 1) args[1] else "centroide"
MODO <- if (length(args) >= 2) args[2] else "replay"
stopifnot(GRAN %in% c("centroide", "pixel"))

cfg <- le_config()
m   <- cfg_modo(cfg, MODO)
FORMULA <- as.formula(paste("response ~", cfg$bfast_formula))
ORDEM   <- as.integer(cfg$bfast_order)
NIVEL   <- cfg_num(cfg, "bfast_level")

serie <- le_serie("dados/serie_ndvi.csv", politica = cfg$agregacao_dia)
serie$pixel <- id_pixel(serie$longitude, serie$latitude)
dir.create("figuras", showWarnings = FALSE)

cat("\nparametros: response ~", cfg$bfast_formula, "| order", ORDEM,
    "| level", NIVEL, "| history all\n")
cat("monitoramento a partir de", format(m$monitor_inicio), "\n")

# ---------------------------------------------------------------- centroide
if (GRAN == "centroide") {

  clon <- mean(range(serie$longitude)); clat <- mean(range(serie$latitude))
  alvo <- serie[which.min((serie$longitude - clon)^2 +
                          (serie$latitude  - clat)^2), ]
  s <- serie[serie$pixel == alvo$pixel, c("date", "NDVI")]
  s <- s[order(s$date), ]

  cat(sprintf("\n--- pixel-centroide (%.5f, %.5f) ---\n",
              alvo$longitude, alvo$latitude))
  cat("observacoes:", nrow(s), "| periodo:",
      format(min(s$date)), "a", format(max(s$date)), "\n")
  g <- as.numeric(diff(s$date))
  cat("intervalo entre datas (dias): min", min(g), "| mediana", median(g),
      "| max", max(g), "\n")

  nts <- monta_ts(s$date, s$NDVI)
  t <- as.numeric(time(nts)); ano <- floor(t)
  grade <- as.Date(paste0(ano, "-01-01")) + round((t - ano) * 365)
  v <- as.numeric(nts); ok <- !is.na(v)
  depois <- data.frame(date = grade[ok], NDVI = v[ok])

  cat(sprintf("apos bfastts: %d pontos | %d posicoes no ts (%.1f%% com dado)\n",
              nrow(depois), length(v), 100 * mean(ok)))
  if (nrow(s) != nrow(depois))
    cat("  ATENCAO:", nrow(s) - nrow(depois), "observacoes colapsadas pelo bfastts\n")

  bm <- bfastmonitor(nts, start = data_para_decimal(m$monitor_inicio),
                     formula = FORMULA, order = ORDEM,
                     history = "all", level = NIVEL)
  r2 <- tryCatch(summary(bm$model)$r.squared, error = function(e) NA_real_)

  cat("\nhistorico:", format(decimal_para_data(bm$history[1])), "a",
      format(decimal_para_data(bm$history[2])), "| R2", round(r2, 4), "\n")
  if (is.na(bm$breakpoint)) {
    cat("nenhuma quebra detectada\n")
  } else {
    q <- decimal_para_data(bm$breakpoint)
    cat("quebra:", format(q, "%d/%m/%Y"), "| magnitude", round(bm$magnitude, 5), "\n")
    if (!is.na(m$evento_ref))
      cat("defasagem em relacao a", format(m$evento_ref), ":",
          as.numeric(q - m$evento_ref), "dias\n")
  }

  png("figuras/inspecao_centroide.png", width = 1400, height = 1500, res = 120)
  par(mfrow = c(5, 1), mar = c(4, 4.5, 2.5, 1))

  plot(s$date, s$NDVI, type = "p", pch = 19, cex = 0.5, col = "grey30",
       xlab = "", ylab = "NDVI", ylim = c(0, 1),
       main = sprintf("Antes: serie do CSV, %d observacoes", nrow(s)))

  plot(depois$date, depois$NDVI, type = "o", pch = 19, cex = 0.5, col = "steelblue",
       xlab = "", ylab = "NDVI", ylim = c(0, 1),
       main = sprintf("Depois: serie usada pelo bfastmonitor (%d pontos)", nrow(depois)))
  for (i in which(g > 20)) rect(s$date[i], 0, s$date[i + 1], 1,
                                col = "#ff000012", border = NA)
  abline(v = m$monitor_inicio, col = "red", lty = 2)
  legend("bottomleft", c("lacuna > 20 dias", "inicio do monitoramento"),
         fill = c("#ff000030", NA), border = NA, lty = c(NA, 2),
         col = c(NA, "red"), bty = "n", cex = 0.9)

  # type="p": com a grade quase toda em NA, a linha nao aparece.
  plot(nts, type = "p", pch = 20, cex = 0.4, ylab = "NDVI", xlab = "", ylim = c(0, 1),
       main = sprintf("Vetor ts de frequencia 365: %d posicoes, %.1f%% com dado",
                      length(v), 100 * mean(ok)))

  anos <- sort(unique(as.integer(format(s$date, "%Y"))))
  plot(NA, xlim = c(1, 366), ylim = c(0.5, length(anos) + 0.5),
       xlab = "dia do ano", ylab = "", yaxt = "n",
       main = "Dia do ano de cada observacao")
  axis(2, at = seq_along(anos), labels = anos, las = 1)
  abline(v = seq(0, 360, 30), col = "grey90")
  for (i in seq_along(anos)) {
    d <- s$date[format(s$date, "%Y") == anos[i]]
    points(as.integer(format(d, "%j")), rep(i, length(d)),
           pch = 124, cex = 0.8, col = "darkgreen")
  }

  plot(bm, main = "Saida do bfastmonitor")
  dev.off()
  cat("\nfigura: figuras/inspecao_centroide.png\n")
}

# -------------------------------------------------------------------- pixel
if (GRAN == "pixel") {

  grupos <- split(serie[, c("longitude", "latitude", "date", "NDVI")], serie$pixel)
  cat("\npixels:", length(grupos), "\n")

  inicio <- data_para_decimal(m$monitor_inicio)
  perdidas <- 0L

  roda <- function(sub) {
    sub <- sub[order(sub$date), ]
    if (nrow(sub) < cfg_num(cfg, "min_obs_historico")) return(NULL)
    nts <- tryCatch(monta_ts(sub$date, sub$NDVI), error = function(e) NULL)
    if (is.null(nts)) return(NULL)
    perdidas <<- perdidas + (nrow(sub) - sum(!is.na(as.numeric(nts))))
    out <- tryCatch(bfastmonitor(nts, start = inicio, formula = FORMULA,
                                 order = ORDEM, history = "all", level = NIVEL),
                    error = function(e) NULL, warning = function(w) NULL)
    if (is.null(out)) return(NULL)
    data.frame(longitude = sub$longitude[1], latitude = sub$latitude[1],
               breakpoint = out$breakpoint, magnitude = out$magnitude,
               n_obs = nrow(sub))
  }

  t0 <- Sys.time()
  res <- do.call(rbind, lapply(grupos, roda))
  cat("tempo:", round(difftime(Sys.time(), t0, units = "mins"), 1), "min\n")

  cat("observacoes colapsadas pelo bfastts (soma dos pixels):", perdidas, "\n")
  res$data_quebra <- decimal_para_data(res$breakpoint)
  com <- res[!is.na(res$breakpoint), ]
  cat(sprintf("pixels avaliados: %d | com quebra: %d (%.1f%%)\n",
              nrow(res), nrow(com), 100 * nrow(com) / nrow(res)))

  write.csv(res, "figuras/quebras_por_pixel.csv", row.names = FALSE)

  if (nrow(com) > 0) {
    com$anomes <- format(com$data_quebra, "%Y-%m")
    resumo <- aggregate(magnitude ~ anomes, data = com,
                        FUN = function(x) c(n = length(x), media = mean(x)))
    resumo <- data.frame(anomes = resumo$anomes,
                         n = resumo$magnitude[, "n"],
                         magnitude_media = round(resumo$magnitude[, "media"], 4))
    cat("\nquebras por mes (negativo = queda de NDVI):\n")
    print(head(resumo[order(-resumo$n), ], 15), row.names = FALSE)

    if (!is.na(m$evento_ref)) {
      dif <- as.numeric(com$data_quebra - m$evento_ref)
      cat(sprintf("\ndefasagem em relacao a %s: mediana %.0f dias | media %.0f dias\n",
                  format(m$evento_ref), median(dif), mean(dif)))
      cat(sprintf("pixels com quebra ate 120 dias apos o evento: %d (%.1f%%)\n",
                  sum(dif >= 0 & dif <= 120),
                  100 * mean(dif >= 0 & dif <= 120)))
    }

    png("figuras/pixel_periodo.png", width = 1600, height = 1000, res = 150)
    par(mar = c(6, 4.5, 3, 1))
    barplot(table(com$anomes), las = 2, cex.names = 0.6,
            ylab = "N de pixels", main = "Distribuicao temporal das quebras")
    dev.off()

    png("figuras/pixel_mapa.png", width = 1300, height = 1200, res = 150)
    lim <- as.Date(c("2021-01-01","2021-04-01","2021-07-01","2021-10-01",
                     "2022-01-01","2022-07-01","2023-01-01","2027-01-01"))
    rot <- c("01-03/2021","04-06/2021","07-09/2021","10-12/2021",
             "01-06/2022","07-12/2022","2023+")
    pal <- colorRampPalette(c("yellow","orange","red","darkred"))(length(rot))
    cl  <- cut(com$data_quebra, breaks = lim, labels = rot, right = FALSE)
    plot(com$longitude, com$latitude, col = pal[as.integer(cl)],
         pch = 15, cex = 0.4, asp = 1, xlab = "Longitude", ylab = "Latitude",
         main = "Quebras por pixel (cor = periodo)")
    legend("topright", legend = rot, fill = pal, title = "Periodo",
           bty = "n", cex = 0.7)
    dev.off()

    cat("\nfiguras: figuras/pixel_periodo.png, figuras/pixel_mapa.png\n")
    cat("tabela: figuras/quebras_por_pixel.csv\n")
  }
}
