# Rscript inspecao/R/inspeciona_serie.R [com|sem]
# serie do pixel-centroide antes e depois do bfastts e saida do bfastmonitor

source("R/config.R")
source("R/funcoes.R")

args <- commandArgs(trailingOnly = TRUE)
MASC <- if (length(args) >= 1) args[1] else "com"
stopifnot(MASC %in% c("com", "sem"))

cfg <- le_config()
a   <- cfg_analise(cfg)
dir_insp <- dir_saida("inspecao")
dir.create(dir_insp, recursive = TRUE, showWarnings = FALSE)

serie <- le_serie(arq_serie(cfg, MASC == "com"), politica = cfg$agregacao_dia)
serie <- serie[serie$date <= a$fim, ]

pc <- pixel_centroide(serie, cfg$area_geojson)
s  <- serie[serie$longitude == pc$longitude & serie$latitude == pc$latitude,
            c("date", "NDVI")]
s  <- s[order(s$date), ]

cat(sprintf("\npixel-centroide (%.5f, %.5f), %s mascara\n", pc$longitude, pc$latitude, MASC))
cat("observacoes:", nrow(s), "| periodo:", format(min(s$date)), "a", format(max(s$date)), "\n")
g <- as.numeric(diff(s$date))
cat("intervalo entre datas (dias): min", min(g), "| mediana", median(g), "| max", max(g), "\n")

nts <- monta_ts(s$date, s$NDVI)
v   <- as.numeric(nts); ok <- !is.na(v)
depois <- data.frame(date = decimal_para_data(as.numeric(time(nts)))[ok], NDVI = v[ok])
cat(sprintf("apos bfastts: %d pontos | %d posicoes no ts (%.1f%% com dado)\n",
            nrow(depois), length(v), 100 * mean(ok)))
if (nrow(s) != nrow(depois))
  cat("  ATENCAO:", nrow(s) - nrow(depois), "observacoes colapsadas pelo bfastts\n")

r <- roda_monitor(s$date, s$NDVI, a$monitor_inicio, cfg)
l <- resumo_monitor(r, cfg)
if (!is.na(l$aviso)) cat("aviso:", l$aviso, "\n")
if (is.null(r$bm)) stop("sem ajuste")
bm <- r$bm

cat("\nhistorico:", format(l$historico_inicio), "a", format(l$historico_fim),
    sprintf("(%d obs) | R2 %.3f | sigma %.4f\n", l$n_historico, l$r2_historico, l$sigma_historico))
if (is.na(l$data_quebra)) {
  cat("nenhuma quebra detectada\n")
} else {
  cat("quebra:", format(l$data_quebra, "%d/%m/%Y"), "| desvio na janela", l$desvio_quebra,
      "| magnitude", l$magnitude, "\n")
  if (!is.na(a$evento_ref))
    cat("defasagem em relacao a", format(a$evento_ref), ":",
        as.numeric(l$data_quebra - a$evento_ref), "dias\n")
}

f <- file.path(dir_insp, paste0("centroide_", MASC, "_mascara.png"))
png(f, width = 1400, height = 1500, res = 120)
par(mfrow = c(5, 1), mar = c(4, 4.5, 2.5, 1))

plot(s$date, s$NDVI, type = "p", pch = 19, cex = 0.5, col = "grey30",
     xlab = "", ylab = "NDVI", ylim = c(0, 1),
     main = sprintf("Antes: serie do CSV, %d observacoes", nrow(s)))

plot(depois$date, depois$NDVI, type = "o", pch = 19, cex = 0.5, col = "steelblue",
     xlab = "", ylab = "NDVI", ylim = c(0, 1),
     main = sprintf("Depois: serie usada pelo bfastmonitor (%d pontos)", nrow(depois)))
for (i in which(g > 20)) rect(s$date[i], 0, s$date[i + 1], 1,
                              col = "#ff000012", border = NA)
abline(v = a$monitor_inicio, col = "red", lty = 2)
legend("bottomleft", c("lacuna > 20 dias", "inicio do monitoramento"),
       fill = c("#ff000030", NA), border = NA, lty = c(NA, 2),
       col = c(NA, "red"), bty = "n", cex = 0.9)

# type="p": com a grade quase toda em NA a linha nao aparece
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
invisible(dev.off())
cat("\nfigura:", f, "\n")
