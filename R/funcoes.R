suppressMessages({
  library(zoo)
  library(bfast)
})

# dia do ano na grade do bfastts (365 dias, 29/02 e 01/03 na mesma posicao)
yday365 <- function(d) {
  x <- as.POSIXlt(d)
  c(0L, 31L, 59L, 90L, 120L, 151L, 181L, 212L, 243L, 273L, 304L, 334L)[1L + x$mon] + x$mday
}

data_para_decimal <- function(d) {
  1900 + as.POSIXlt(d)$year + (yday365(d) - 1) / 365
}

# arredonda em vez de truncar, senao metade das datas volta um dia antes
decimal_para_data <- function(x) {
  out <- as.Date(rep(NA_real_, length(x)), origin = "1970-01-01")
  ok  <- !is.na(x)
  if (!any(ok)) return(out)
  ano <- floor(x[ok])
  k   <- round((x[ok] - ano) * 365)
  bis <- (ano %% 4 == 0 & ano %% 100 != 0) | ano %% 400 == 0
  out[ok] <- as.Date(paste0(ano, "-01-01")) + k + (bis & k >= 59)
  out
}

# um valor por pixel-dia: primeira aquisicao do dia (datetime) ou media de
# todas as imagens do dia. Sem regra o bfastts fica com a ultima linha
agrega_pixel_dia <- function(df, politica = "primeira") {
  stopifnot(all(c("longitude", "latitude", "date", "NDVI") %in% names(df)))
  if (!politica %in% c("media", "primeira"))
    stop("agregacao_dia invalida: ", politica, " (use media ou primeira)")

  df <- df[!is.na(df$NDVI), ]
  n_antes <- nrow(df)

  if (politica == "primeira") {
    ord <- if ("datetime" %in% names(df)) df$datetime else as.character(df$date)
    img <- if ("img_id" %in% names(df)) df$img_id else ""
    df <- df[order(df$longitude, df$latitude, df$date, ord, img), ]
    ag <- df[!duplicated(paste(df$longitude, df$latitude, df$date)),
             c("longitude", "latitude", "date", "NDVI")]
  } else {
    ag <- aggregate(NDVI ~ longitude + latitude + date, data = df, FUN = mean)
  }
  ag <- ag[order(ag$longitude, ag$latitude, ag$date), ]

  attr(ag, "n_antes")   <- n_antes
  attr(ag, "n_depois")  <- nrow(ag)
  attr(ag, "politica")  <- politica
  ag
}

le_serie <- function(caminho, verbose = TRUE, politica = "primeira") {
  if (!file.exists(caminho))
    stop("serie nao encontrada: ", caminho, "\nRode antes: node gee/extrai_serie.js")
  df <- read.csv(caminho, stringsAsFactors = FALSE)
  df$date <- as.Date(df$date)
  ag <- agrega_pixel_dia(df, politica)
  if (verbose) {
    cat(sprintf("serie: %d linhas -> %d observacoes pixel-dia\n",
                attr(ag, "n_antes"), attr(ag, "n_depois")))
    cat(sprintf("  imagens repetidas no mesmo pixel-dia resolvidas por '%s': %d\n",
                attr(ag, "politica"), attr(ag, "n_antes") - attr(ag, "n_depois")))
    cat(sprintf("pixels: %d | periodo: %s a %s\n",
                length(unique(paste(ag$longitude, ag$latitude))),
                format(min(ag$date)), format(max(ag$date))))
  }
  ag
}

id_pixel <- function(lon, lat) paste(lon, lat, sep = "_")

# ts diario (frequencia 365), NA nos dias sem imagem, sem interpolacao
monta_ts <- function(datas, valores) {
  bfastts(valores, datas, type = "irregular")
}

# h e end so aceitam os valores tabelados do OLS-MOSUM
ajusta_monitor <- function(nts, monitor_inicio, cfg) {
  bfastmonitor(nts,
               start   = data_para_decimal(monitor_inicio),
               formula = as.formula(paste("response ~", cfg$bfast_formula)),
               order   = as.integer(cfg$bfast_order),
               history = cfg_historico(cfg),
               type    = "OLS-MOSUM",
               h       = cfg_num(cfg, "bfast_h"),
               end     = cfg_num(cfg, "bfast_end"),
               level   = cfg_num(cfg, "bfast_level"))
}

# bm = NULL se o historico for curto ou o ajuste falhar; avisos ficam em r$aviso
roda_monitor <- function(datas, valores, monitor_inicio, cfg) {
  r <- list(bm = NULL, n_obs = length(valores), aviso = NA_character_)

  n_hist <- sum(datas < monitor_inicio)
  if (n_hist < cfg_num(cfg, "min_obs_historico")) {
    r$aviso <- sprintf("historico com %d observacoes", n_hist)
    return(r)
  }

  avisos <- character()
  r$bm <- withCallingHandlers(
    tryCatch(ajusta_monitor(monta_ts(datas, valores), monitor_inicio, cfg),
             error = function(e) {
               avisos <<- c(avisos, paste("erro:", conditionMessage(e)))
               NULL
             }),
    warning = function(w) {
      avisos <<- c(avisos, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  if (length(avisos)) r$aviso <- paste(unique(avisos), collapse = "; ")
  r
}

# mediana do residuo na janela MOSUM que cruzou a fronteira (sinal da quebra).
# tspp e data.frame no metodo padrao e matriz no matricial
desvio_quebra <- function(bm, h) {
  if (is.na(bm$breakpoint)) return(NA_real_)
  tp <- bm$tspp
  if (is.data.frame(tp)) {
    y <- tp$response; tempo <- tp$time; prev <- tp$prediction
  } else {
    y <- tp[, 1]; tempo <- tp[, "time"]; prev <- tp[, 3]
  }
  i <- which(tempo == bm$breakpoint)
  k <- floor(h * nrow(bm$model$model))
  janela <- max(1, i - k + 1):i
  median(y[janela] - prev[janela], na.rm = TRUE)
}

# uma linha por execucao do bfastmonitor
resumo_monitor <- function(r, cfg) {
  bm <- r$bm
  ok <- !is.null(bm)
  data.frame(
    n_obs            = r$n_obs,
    historico_inicio = if (ok) decimal_para_data(bm$history[1]) else as.Date(NA),
    historico_fim    = if (ok) decimal_para_data(bm$history[2]) else as.Date(NA),
    n_historico      = if (ok) nrow(bm$model$model) else NA_integer_,
    r2_historico     = if (ok) round(summary(bm$model)$r.squared, 4) else NA_real_,
    sigma_historico  = if (ok) round(sd(residuals(bm$model)), 4) else NA_real_,
    data_quebra      = if (ok) decimal_para_data(bm$breakpoint) else as.Date(NA),
    desvio_quebra    = if (ok) round(desvio_quebra(bm, cfg_num(cfg, "bfast_h")), 6) else NA_real_,
    magnitude        = if (ok) round(bm$magnitude, 6) else NA_real_,
    aviso            = r$aviso,
    stringsAsFactors = FALSE
  )
}

# pixel mais proximo do centroide do maior poligono; se o centroide cair fora
# (poligono concavo), o pixel mais distante da borda
pixel_centroide <- function(serie, geojson) {
  gj <- jsonlite::fromJSON(geojson, simplifyVector = FALSE)
  geoms <- switch(gj$type,
                  FeatureCollection = lapply(gj$features, function(f) f$geometry),
                  Feature           = list(gj$geometry),
                  list(gj))
  aneis <- list()
  for (g in geoms) {
    partes <- if (g$type == "MultiPolygon") g$coordinates else list(g$coordinates)
    for (p in partes) {
      r <- matrix(unlist(p[[1]]), ncol = 2, byrow = TRUE)
      if (any(r[1, ] != r[nrow(r), ])) r <- rbind(r, r[1, ])
      aneis[[length(aneis) + 1]] <- r
    }
  }
  if (!length(aneis)) stop("nenhum poligono em ", geojson)

  # graus para metros na latitude da area
  kx <- 111320 * cos(mean(aneis[[1]][, 2]) * pi / 180)
  ky <- 110574

  shoelace <- function(r) {
    n <- nrow(r); x1 <- r[-n, 1]; y1 <- r[-n, 2]; x2 <- r[-1, 1]; y2 <- r[-1, 2]
    cr <- x1 * y2 - x2 * y1; a <- sum(cr) / 2
    c(area_m2 = abs(a) * kx * ky,
      lon = sum((x1 + x2) * cr) / (6 * a), lat = sum((y1 + y2) * cr) / (6 * a))
  }
  dentro <- function(x0, y0, r) {
    ok <- logical(length(x0))
    for (i in seq_len(nrow(r) - 1)) {
      x1 <- r[i, 1]; y1 <- r[i, 2]; x2 <- r[i + 1, 1]; y2 <- r[i + 1, 2]
      corta <- (y1 > y0) != (y2 > y0) & x0 < (x2 - x1) * (y0 - y1) / (y2 - y1) + x1
      ok <- xor(ok, corta)
    }
    ok
  }
  dist_borda <- function(x0, y0, r) {
    x <- r[, 1] * kx; y <- r[, 2] * ky; x0 <- x0 * kx; y0 <- y0 * ky
    d <- rep(Inf, length(x0))
    for (i in seq_len(nrow(r) - 1)) {
      dx <- x[i + 1] - x[i]; dy <- y[i + 1] - y[i]
      u <- pmin(1, pmax(0, ((x0 - x[i]) * dx + (y0 - y[i]) * dy) / max(dx^2 + dy^2, 1e-12)))
      d <- pmin(d, sqrt((x0 - x[i] - u * dx)^2 + (y0 - y[i] - u * dy)^2))
    }
    d
  }

  s  <- t(sapply(aneis, shoelace))
  k  <- which.max(s[, "area_m2"])
  r  <- aneis[[k]]
  px <- unique(serie[, c("longitude", "latitude")])

  if (dentro(s[k, "lon"], s[k, "lat"], r)) {
    i <- which.min((px$longitude - s[k, "lon"])^2 + (px$latitude - s[k, "lat"])^2)
    criterio <- "centroide do maior poligono"
  } else {
    ins <- which(dentro(px$longitude, px$latitude, r))
    if (!length(ins)) stop("nenhum pixel dentro do maior poligono de ", geojson)
    i <- ins[which.max(dist_borda(px$longitude[ins], px$latitude[ins], r))]
    criterio <- "pixel mais interior do maior poligono"
  }
  list(longitude = px$longitude[i], latitude = px$latitude[i],
       poligono = k, area_ha = unname(s[k, "area_m2"]) / 1e4,
       criterio = criterio,
       dist_borda_m = dist_borda(px$longitude[i], px$latitude[i], r))
}
