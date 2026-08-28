# Leitor do config.yml. Aceita apenas "chave: valor" (formato plano),
# para nao depender do pacote yaml.

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

cfg_modo <- function(cfg, modo = NULL) {
  m <- if (is.null(modo)) cfg$modo else modo
  if (!m %in% c("operacao", "replay")) stop("modo invalido: ", m)
  list(
    modo           = m,
    monitor_inicio = if (m == "replay") cfg_data(cfg, "replay_monitor_inicio")
                     else               cfg_data(cfg, "monitor_inicio"),
    evento_ref     = if (m == "replay") cfg_data(cfg, "replay_evento_ref") else NA
  )
}
