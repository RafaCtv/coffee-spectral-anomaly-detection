# Monitoramento continuo de anomalias espectrais.
#
# Estado por pixel:
#   NORMAL        avalia cada observacao nova contra o modelo do historico.
#                 Quebra detectada -> alerta e vai para RECALIBRANDO.
#   RECALIBRANDO  o modelo antigo nao representa mais a serie. Acumula desde a
#                 data da quebra ate atingir min_obs_historico e
#                 min_meses_historico, entao volta para NORMAL.
#
# Uso: Rscript R/monitora.R [operacao|replay]

source("R/config.R")
source("R/funcoes.R")

ARQ_SERIE   <- "dados/serie_ndvi.csv"
ARQ_PIXELS  <- "estado/estado_pixels.csv"
ARQ_GLOBAL  <- "estado/estado_global.csv"
ARQ_ALERTAS <- "estado/alertas.csv"

estado_inicial <- function(serie, monitor_inicio) {
  px <- unique(serie[, c("longitude", "latitude")])
  data.frame(
    longitude        = px$longitude,
    latitude         = px$latitude,
    estado           = "NORMAL",
    historico_inicio = min(serie$date),
    monitor_inicio   = monitor_inicio,
    ultima_quebra    = as.Date(NA),
    ultima_magnitude = NA_real_,
    n_alertas        = 0L,
    stringsAsFactors = FALSE
  )
}

le_estado <- function(serie, monitor_inicio) {
  if (!file.exists(ARQ_PIXELS)) {
    cat("estado inexistente - inicializando\n")
    return(estado_inicial(serie, monitor_inicio))
  }
  e <- read.csv(ARQ_PIXELS, stringsAsFactors = FALSE)
  e$historico_inicio <- as.Date(e$historico_inicio)
  e$monitor_inicio   <- as.Date(e$monitor_inicio)
  e$ultima_quebra    <- as.Date(e$ultima_quebra)
  e
}

grava_estado <- function(est, serie, cfg, modo, n_alertas_exec) {
  dir.create("estado", showWarnings = FALSE, recursive = TRUE)
  write.csv(est, ARQ_PIXELS, row.names = FALSE)
  write.csv(data.frame(
    ultima_execucao     = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    modo                = modo,
    ultima_data_serie   = format(max(serie$date)),
    n_pixels            = nrow(est),
    n_normal            = sum(est$estado == "NORMAL"),
    n_recalibrando      = sum(est$estado == "RECALIBRANDO"),
    n_alertas_execucao  = n_alertas_exec,
    n_alertas_acumulado = sum(est$n_alertas)
  ), ARQ_GLOBAL, row.names = FALSE)
}

anexa_alertas <- function(novos) {
  if (is.null(novos) || nrow(novos) == 0) return(invisible(NULL))
  dir.create("estado", showWarnings = FALSE, recursive = TRUE)
  if (file.exists(ARQ_ALERTAS)) {
    write.table(novos, ARQ_ALERTAS, sep = ",", row.names = FALSE,
                col.names = FALSE, append = TRUE)
  } else {
    write.csv(novos, ARQ_ALERTAS, row.names = FALSE)
  }
}

# Um passo da maquina de estados. "hoje" e a data da execucao, real ou simulada.
passo <- function(st, obs, cfg, hoje) {
  alerta <- NULL

  obs <- obs[obs$date >= st$historico_inicio & obs$date <= hoje, ]
  if (nrow(obs) == 0) return(list(st = st, alerta = NULL))

  if (st$estado == "RECALIBRANDO") {
    meses <- as.numeric(max(obs$date) - st$historico_inicio) / 30.44
    if (nrow(obs) >= cfg_num(cfg, "min_obs_historico") &&
        meses      >= cfg_num(cfg, "min_meses_historico")) {
      st$estado         <- "NORMAL"
      st$monitor_inicio <- max(obs$date)
    }
    return(list(st = st, alerta = NULL))
  }

  if (is.na(st$monitor_inicio) || hoje < st$monitor_inicio)
    return(list(st = st, alerta = NULL))

  res <- roda_monitor(obs$date, obs$NDVI, st$monitor_inicio, cfg)
  if (is.null(res) || is.na(res$breakpoint)) return(list(st = st, alerta = NULL))

  alerta <- data.frame(
    data_deteccao = format(hoje),
    longitude     = st$longitude,
    latitude      = st$latitude,
    data_quebra   = format(res$data_quebra),
    magnitude     = round(res$magnitude, 6),
    r2_historico  = round(res$r2, 4),
    n_obs         = res$n_obs,
    stringsAsFactors = FALSE
  )

  st$estado           <- "RECALIBRANDO"
  st$ultima_quebra    <- res$data_quebra
  st$ultima_magnitude <- res$magnitude
  st$n_alertas        <- st$n_alertas + 1L
  st$historico_inicio <- res$data_quebra + 1
  st$monitor_inicio   <- as.Date(NA)

  list(st = st, alerta = alerta)
}

roda_operacao <- function(serie, est, cfg, hoje = max(serie$date)) {
  serie$pid <- id_pixel(serie$longitude, serie$latitude)
  est$pid   <- id_pixel(est$longitude, est$latitude)
  por_pixel <- split(serie[, c("date", "NDVI")], serie$pid)

  alertas <- list()
  for (i in seq_len(nrow(est))) {
    obs <- por_pixel[[est$pid[i]]]
    if (is.null(obs)) next
    r <- passo(est[i, ], obs, cfg, hoje)
    est[i, names(r$st)] <- r$st
    if (!is.null(r$alerta)) alertas[[length(alertas) + 1]] <- r$alerta
  }
  est$pid <- NULL
  list(estado = est, alertas = do.call(rbind, alertas))
}

# Alimenta as observacoes em ordem cronologica para medir quando o alerta teria
# sido emitido. Um pixel so e reavaliado nas datas em que recebe observacao nova,
# igual ao que aconteceria em operacao.
roda_replay <- function(serie, est, cfg, monitor_inicio, evento_ref) {
  serie$pid <- id_pixel(serie$longitude, serie$latitude)
  est$pid   <- id_pixel(est$longitude, est$latitude)
  por_pixel <- split(serie[, c("date", "NDVI")], serie$pid)

  datas <- sort(unique(serie$date[serie$date >= monitor_inicio]))
  cat(sprintf("replay: %d datas de %s a %s | %d pixels\n",
              length(datas), format(min(datas)), format(max(datas)), nrow(est)))

  alertas <- list()
  for (d in datas) {
    d <- as.Date(d, origin = "1970-01-01")
    for (i in seq_len(nrow(est))) {
      if (est$estado[i] != "NORMAL") next
      obs <- por_pixel[[est$pid[i]]]
      if (is.null(obs) || !any(obs$date == d)) next
      r <- passo(est[i, ], obs, cfg, d)
      est[i, names(r$st)] <- r$st
      if (!is.null(r$alerta)) alertas[[length(alertas) + 1]] <- r$alerta
    }
  }
  est$pid <- NULL
  a <- do.call(rbind, alertas)

  if (!is.null(a) && nrow(a) > 0 && !is.na(evento_ref)) {
    atraso <- as.numeric(as.Date(a$data_deteccao) - evento_ref)
    val <- atraso[atraso >= 0]
    cat("\n--- MTTD ---\n")
    cat("evento de referencia :", format(evento_ref), "\n")
    cat("pixels com alerta    :", nrow(a), "\n")
    if (length(val)) {
      cat(sprintf("MTTD                 : %.1f dias (mediana %.0f)\n",
                  mean(val), median(val)))
      cat(sprintf("primeiro alerta      : %s (%d dias)\n",
                  format(min(as.Date(a$data_deteccao[atraso >= 0]))), min(val)))
    }
    cat(sprintf("alertas anteriores ao evento: %d\n", sum(atraso < 0)))
  }
  list(estado = est, alertas = a)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  cfg  <- le_config()
  m    <- cfg_modo(cfg, if (length(args) >= 1) args[1] else NULL)

  cat("modo:", m$modo, "| area:", cfg$area_nome, "\n\n")

  serie <- le_serie(ARQ_SERIE)
  est   <- le_estado(serie, m$monitor_inicio)

  r <- if (m$modo == "replay")
         roda_replay(serie, est, cfg, m$monitor_inicio, m$evento_ref)
       else
         roda_operacao(serie, est, cfg)

  n <- if (is.null(r$alertas)) 0 else nrow(r$alertas)
  anexa_alertas(r$alertas)
  grava_estado(r$estado, serie, cfg, m$modo, n)

  cat("\nalertas nesta execucao :", n, "\n")
  cat("pixels NORMAL          :", sum(r$estado$estado == "NORMAL"), "\n")
  cat("pixels RECALIBRANDO    :", sum(r$estado$estado == "RECALIBRANDO"), "\n")
}

if (sys.nframe() == 0) main()
