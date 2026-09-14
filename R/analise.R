# Rscript R/analise.R
# bfastmonitor por pixel e no pixel-centroide, com e sem mascara de nuvem

source("R/config.R")
source("R/funcoes.R")

cfg <- le_config()
a   <- cfg_analise(cfg)
dir_res <- dir_saida("resultados")
dir.create(dir_res, recursive = TRUE, showWarnings = FALSE)

versoes <- c(com_mascara = TRUE, sem_mascara = FALSE)
series  <- list()
for (m in names(versoes)) {
  arq <- arq_serie(cfg, versoes[[m]])
  if (!file.exists(arq)) {
    cat("serie nao encontrada:", arq, "- rode: node gee/extrai_serie.js\n")
    next
  }
  cat(sprintf("\n%s (%s)\n", sub("_", " ", m), arq))
  series[[m]] <- le_serie(arq, politica = cfg$agregacao_dia)
}
if (!length(series)) stop("nenhuma serie disponivel")

# as series sao extraidas separadamente, corta as duas na mesma data
fim <- min(a$fim, do.call(c, lapply(series, function(s) max(s$date))))
cat(sprintf(paste0("\nmonitoramento a partir de %s | serie ate %s\n",
                   "response ~ %s | order %s | history %s | h %s | end %s | level %s\n"),
            format(a$monitor_inicio), format(fim), cfg$bfast_formula, cfg$bfast_order,
            cfg_historico(cfg), cfg$bfast_h, cfg$bfast_end, cfg$bfast_level))

centroides <- list()

for (m in names(series)) {
  cat(sprintf("\n===== %s =====\n", sub("_", " ", m)))
  serie  <- series[[m]][series[[m]]$date <= fim, ]
  grupos <- split(serie[, c("longitude", "latitude", "date", "NDVI")],
                  id_pixel(serie$longitude, serie$latitude))

  # por pixel
  t0  <- Sys.time()
  res <- do.call(rbind, lapply(grupos, function(s) {
    s <- s[order(s$date), ]
    cbind(data.frame(longitude = s$longitude[1], latitude = s$latitude[1]),
          resumo_monitor(roda_monitor(s$date, s$NDVI, a$monitor_inicio, cfg), cfg))
  }))
  rownames(res) <- NULL
  write.csv(res, file.path(dir_res, paste0("quebras_por_pixel_", m, ".csv")),
            row.names = FALSE)

  aval <- !is.na(res$n_historico)
  com  <- res[!is.na(res$data_quebra), ]
  cat(sprintf("pixels: %d | avaliados: %d | com quebra: %d (%.1f%% dos avaliados) | %.1f min\n",
              nrow(res), sum(aval), nrow(com), 100 * nrow(com) / max(1, sum(aval)),
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  cat(sprintf("historico: mediana de %.0f observacoes | R2 mediano %.3f | sigma mediano %.3f\n",
              median(res$n_historico, na.rm = TRUE), median(res$r2_historico, na.rm = TRUE),
              median(res$sigma_historico, na.rm = TRUE)))
  if (any(!is.na(res$aviso))) {
    cat("avisos:\n")
    print(sort(table(res$aviso), decreasing = TRUE))
  }

  if (nrow(com) > 0) {
    com$anomes <- format(com$data_quebra, "%Y-%m")
    mes <- do.call(rbind, lapply(split(com, com$anomes), function(x)
      data.frame(anomes = x$anomes[1], n_pixels = nrow(x),
                 desvio_mediano = round(median(x$desvio_quebra), 4),
                 queda = sum(x$desvio_quebra < 0),
                 alta = sum(x$desvio_quebra > 0))))
    mes <- mes[order(mes$anomes), ]
    write.csv(mes, file.path(dir_res, paste0("quebras_por_mes_", m, ".csv")),
              row.names = FALSE)
    cat("\nmeses com mais quebras (queda = NDVI abaixo do modelo na janela da quebra):\n")
    print(head(mes[order(-mes$n_pixels, mes$anomes), ], 10), row.names = FALSE)

    if (!is.na(a$evento_ref)) {
      dif  <- as.numeric(com$data_quebra - a$evento_ref)
      apos <- dif >= 0 & dif <= 120
      cat(sprintf("\nem relacao a %s: %d quebras antes | %d ate 120 dias depois (%d com queda)\n",
                  format(a$evento_ref), sum(dif < 0), sum(apos),
                  sum(apos & com$desvio_quebra < 0)))
    }
  }

  # pixel-centroide
  pc  <- pixel_centroide(serie, cfg$area_geojson)
  obs <- serie[serie$longitude == pc$longitude & serie$latitude == pc$latitude, ]
  obs <- obs[order(obs$date), ]
  cat(sprintf("\npixel-centroide %.6f, %.6f | %s, %.0f m da borda\n",
              pc$longitude, pc$latitude, pc$criterio, pc$dist_borda_m))

  r <- roda_monitor(obs$date, obs$NDVI, a$monitor_inicio, cfg)
  l <- resumo_monitor(r, cfg)
  if (!is.na(l$aviso)) cat("  aviso:", l$aviso, "\n")
  if (!is.null(r$bm))
    saveRDS(r$bm, file.path(dir_res, paste0("centroide_", m, ".rds")))

  centroides[[m]] <- cbind(
    data.frame(mascara = m, longitude = pc$longitude, latitude = pc$latitude,
               criterio = pc$criterio, dist_borda_m = round(pc$dist_borda_m, 1)),
    l)
  cat(sprintf("  %d observacoes | historico %s a %s (%s obs, R2 %.3f) | %s | desvio %+.4f | magnitude %+.4f\n",
              l$n_obs, format(l$historico_inicio), format(l$historico_fim),
              l$n_historico, l$r2_historico,
              if (is.na(l$data_quebra)) "sem quebra"
              else paste("quebra em", format(l$data_quebra, "%d/%m/%Y")),
              l$desvio_quebra, l$magnitude))
}

if (length(centroides))
  write.csv(do.call(rbind, centroides), file.path(dir_res, "centroide.csv"),
            row.names = FALSE)
