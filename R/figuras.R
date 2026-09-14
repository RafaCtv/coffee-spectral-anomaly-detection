# Rscript R/figuras.R (depois do R/analise.R)

source("R/config.R")
source("R/funcoes.R")

dir_res <- dir_saida("resultados")
dir_fig <- dir_saida("figuras")
dir.create(dir_fig, showWarnings = FALSE, recursive = TRUE)
mascaras <- c("com_mascara", "sem_mascara")

quebras <- lapply(mascaras, function(m) {
  f <- file.path(dir_res, paste0("quebras_por_pixel_", m, ".csv"))
  if (!file.exists(f)) return(NULL)
  q <- read.csv(f, stringsAsFactors = FALSE)
  q$data_quebra <- as.Date(q$data_quebra)
  q[!is.na(q$data_quebra), ]
})
names(quebras) <- mascaras
if (all(vapply(quebras, is.null, logical(1))))
  stop("nenhum resultado em ", dir_res, ". Rode antes: Rscript R/analise.R")

arq_centroide <- file.path(dir_res, "centroide.csv")
centroide <- if (file.exists(arq_centroide))
  read.csv(arq_centroide, stringsAsFactors = FALSE)

# mesmas faixas de cor nas duas mascaras
datas <- do.call(c, lapply(Filter(Negate(is.null), quebras), `[[`, "data_quebra"))
if (length(datas)) {
  faixas  <- pretty(range(datas), n = 6)
  rotulos <- paste(format(head(faixas, -1), "%m/%y"),
                   format(tail(faixas, -1), "%m/%y"), sep = "-")
  paleta  <- colorRampPalette(c("yellow", "orange", "red", "darkred"))(length(rotulos))
}

for (m in mascaras) {
  rot <- sub("_", " ", m)
  q   <- quebras[[m]]

  if (!is.null(q) && nrow(q) > 0) {
    classe <- cut(q$data_quebra, breaks = faixas, labels = rotulos,
                  right = FALSE, include.lowest = TRUE)
    f <- file.path(dir_fig, paste0("mapa_quebras_", m, ".png"))
    png(f, width = 1400, height = 1200, res = 200)
    plot(q$longitude, q$latitude, col = paleta[as.integer(classe)],
         pch = 15, cex = 0.6, asp = 1, xlab = "Longitude", ylab = "Latitude",
         main = sprintf("Quebra por pixel, %s (cor = periodo)", rot))
    legend("topright", legend = rotulos, fill = paleta,
           title = "Periodo", bty = "n", cex = 0.7)
    invisible(dev.off())
    cat(f, "\n")

    f <- file.path(dir_fig, paste0("periodo_quebras_", m, ".png"))
    png(f, width = 1400, height = 1000, res = 200)
    barplot(table(format(q$data_quebra, "%Y-%m")), las = 2, cex.names = 0.6,
            xlab = "", ylab = "N de pixels",
            main = sprintf("Pixels com quebra por mes, %s", rot))
    invisible(dev.off())
    cat(f, "\n")
  } else {
    cat(rot, ": sem quebras por pixel para desenhar\n", sep = "")
  }

  rds <- file.path(dir_res, paste0("centroide_", m, ".rds"))
  if (!file.exists(rds)) next
  bm <- readRDS(rds)
  c1 <- if (!is.null(centroide)) centroide[centroide$mascara == m, ]
  local <- if (!is.null(c1) && nrow(c1))
    sprintf("%.5f, %.5f  |  ", c1$longitude, c1$latitude) else ""

  # res menor para a legenda do plot.bfastmonitor nao cobrir os dados
  f <- file.path(dir_fig, paste0("monitor_centroide_", m, ".png"))
  png(f, width = 1500, height = 850, res = 130)
  par(mar = c(4, 4.5, 3, 1))
  plot(bm, ylab = "NDVI", xlab = "tempo (anos)",
       main = sprintf("Pixel-centroide, %s  |  %s%s  |  magnitude %+.3f", rot, local,
                      if (is.na(bm$breakpoint)) "sem quebra"
                      else paste("quebra em",
                                 format(decimal_para_data(bm$breakpoint), "%d/%m/%Y")),
                      bm$magnitude))
  invisible(dev.off())
  cat(f, "\n")
}
