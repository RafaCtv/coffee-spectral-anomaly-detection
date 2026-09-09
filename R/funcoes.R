# Leitura da serie, agregacao e execucao do BFAST Monitor.

suppressMessages({
  library(zoo)
  library(bfast)
})

# bfastmonitor devolve a data da quebra em ano decimal.
decimal_para_data <- function(x) {
  out <- as.Date(rep(NA_real_, length(x)), origin = "1970-01-01")
  ok  <- !is.na(x)
  if (!any(ok)) return(out)
  ano <- floor(x[ok])
  ini <- as.Date(paste0(ano, "-01-01"))
  fim <- as.Date(paste0(ano + 1, "-01-01"))
  out[ok] <- ini + (x[ok] - ano) * as.numeric(fim - ini)
  out
}

data_para_decimal <- function(d) {
  ano <- as.integer(format(d, "%Y"))
  ini <- as.Date(paste0(ano, "-01-01"))
  fim <- as.Date(paste0(ano + 1, "-01-01"))
  ano + as.numeric(d - ini) / as.numeric(fim - ini)
}

# Mais de uma linha por pixel-dia tem duas causas. Reprocessamento da ESA
# entrega a mesma aquisicao (mesmo datatake) em dois produtos: fica a mais
# recente. Datatakes distintos no mesmo dia sao medicoes concorrentes, e
# politica decide entre elas. bfastts comporta um valor por dia e, sem regra
# explicita, mantem a ultima linha do arquivo.
agrega_pixel_dia <- function(df, politica = "media") {
  stopifnot(all(c("longitude", "latitude", "date", "NDVI") %in% names(df)))
  if (!politica %in% c("media", "primeira"))
    stop("agregacao_dia invalida: ", politica, " (use media ou primeira)")

  df <- df[!is.na(df$NDVI), ]
  n_antes <- nrow(df)

  n_reproc <- 0L
  if ("img_id" %in% names(df)) {
    df$datatake <- sub("_.*$", "", df$img_id)
    df <- df[order(df$longitude, df$latitude, df$date, df$datatake, df$img_id), ]
    chave <- paste(df$longitude, df$latitude, df$datatake)
    df <- df[!duplicated(chave, fromLast = TRUE), ]
    n_reproc <- n_antes - nrow(df)
  }
  n_pre <- nrow(df)

  if (politica == "primeira") {
    ord <- if ("datetime" %in% names(df)) df$datetime else as.character(df$date)
    df <- df[order(df$longitude, df$latitude, df$date, ord), ]
    ag <- df[!duplicated(paste(df$longitude, df$latitude, df$date)),
             c("longitude", "latitude", "date", "NDVI")]
  } else {
    ag <- aggregate(NDVI ~ longitude + latitude + date, data = df, FUN = mean)
  }
  ag <- ag[order(ag$longitude, ag$latitude, ag$date), ]

  attr(ag, "n_antes")   <- n_antes
  attr(ag, "n_depois")  <- nrow(ag)
  attr(ag, "reproc")    <- n_reproc
  attr(ag, "mesmo_dia") <- n_pre - nrow(ag)
  attr(ag, "politica")  <- politica
  ag
}

le_serie <- function(caminho, verbose = TRUE, politica = "media") {
  if (!file.exists(caminho))
    stop("serie nao encontrada: ", caminho, "\nRode antes: python gee/extrai_serie.py")
  df <- read.csv(caminho, stringsAsFactors = FALSE)
  df$date <- as.Date(df$date)
  ag <- agrega_pixel_dia(df, politica)
  if (verbose) {
    cat(sprintf("serie: %d linhas -> %d observacoes pixel-dia\n",
                attr(ag, "n_antes"), attr(ag, "n_depois")))
    cat(sprintf("  reprocessamento descartado: %d | mesmo dia (%s): %d\n",
                attr(ag, "reproc"), attr(ag, "politica"), attr(ag, "mesmo_dia")))
    cat(sprintf("pixels: %d | periodo: %s a %s\n",
                length(unique(paste(ag$longitude, ag$latitude))),
                format(min(ag$date)), format(max(ag$date))))
  }
  ag
}

id_pixel <- function(lon, lat) paste(lon, lat, sep = "_")

# type="irregular" devolve um ts de frequencia 365: grade diaria, NA nos dias
# sem imagem, sem interpolacao. O dia do ano vem de um calendario fixo de 365
# dias, o que desloca as datas pos-fevereiro de ano bissexto.
monta_ts <- function(datas, valores) {
  bfastts(valores, datas, type = "irregular")
}

# NULL quando nao ha dados suficientes ou o ajuste falha.
roda_monitor <- function(datas, valores, monitor_inicio, cfg) {
  if (length(valores) < cfg_num(cfg, "min_obs_historico")) return(NULL)

  nts <- tryCatch(monta_ts(datas, valores), error = function(e) NULL)
  if (is.null(nts)) return(NULL)

  formula <- as.formula(paste("response ~", cfg$bfast_formula))

  out <- tryCatch(
    bfastmonitor(nts,
                 start   = data_para_decimal(monitor_inicio),
                 formula = formula,
                 order   = as.integer(cfg$bfast_order),
                 history = cfg_historico(cfg),
                 level   = cfg_num(cfg, "bfast_level")),
    error = function(e) NULL, warning = function(w) NULL
  )
  if (is.null(out)) return(NULL)

  r2 <- tryCatch(summary(out$model)$r.squared, error = function(e) NA_real_)
  list(
    breakpoint  = out$breakpoint,
    data_quebra = decimal_para_data(out$breakpoint),
    magnitude   = out$magnitude,
    r2          = r2,
    n_obs       = length(valores)
  )
}
