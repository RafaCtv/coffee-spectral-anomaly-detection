# leitor do config.yml plano ("chave: valor"), sem depender do pacote yaml
le_config <- function(caminho = "config.yml") {
  if (!file.exists(caminho)) stop("config nao encontrado: ", caminho)
  linhas <- trimws(readLines(caminho, warn = FALSE))
  linhas <- linhas[nzchar(linhas) & !startsWith(linhas, "#")]

  cfg <- list()
  for (l in linhas) {
    p <- regexpr(":", l, fixed = TRUE)
    if (p < 1) next
    chave <- trimws(substr(l, 1, p - 1))
    valor <- trimws(substr(l, p + 1, nchar(l)))
    valor <- trimws(sub("\\s+#.*$", "", valor))
    valor <- gsub('^"|"$', "", valor)
    cfg[[chave]] <- valor
  }
  cfg
}

cfg_num <- function(cfg, chave) {
  v <- suppressWarnings(as.numeric(cfg[[chave]]))
  if (is.na(v)) stop("config '", chave, "' nao e numerico: ", cfg[[chave]])
  v
}

cfg_data <- function(cfg, chave) {
  v <- cfg[[chave]]
  if (is.null(v)) stop("config '", chave, "' ausente")
  if (tolower(v) == "hoje") return(Sys.Date())
  d <- as.Date(v)
  if (is.na(d)) stop("config '", chave, "' nao e uma data valida: ", v)
  d
}

# local/ por padrao; no workflow DIR_SAIDA=.
dir_saida <- function(...) file.path(Sys.getenv("DIR_SAIDA", "local"), ...)

cfg_historico <- function(cfg) {
  v <- cfg$bfast_history
  if (!v %in% c("all", "ROC", "BP"))
    stop("config 'bfast_history' invalido: ", v, " (use all, ROC ou BP)")
  v
}

arq_serie <- function(cfg, mascara = TRUE) {
  chave <- if (mascara) "serie_com_mascara" else "serie_sem_mascara"
  if (is.null(cfg[[chave]])) stop("config '", chave, "' ausente")
  dir_saida(cfg[[chave]])
}

cfg_analise <- function(cfg) {
  ref <- cfg$evento_ref
  list(
    monitor_inicio = cfg_data(cfg, "monitor_inicio"),
    fim            = cfg_data(cfg, "analise_fim"),
    evento_ref     = if (is.null(ref) || !nzchar(ref)) as.Date(NA)
                     else cfg_data(cfg, "evento_ref")
  )
}
