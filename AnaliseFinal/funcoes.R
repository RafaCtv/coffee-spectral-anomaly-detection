# Funcoes usadas pelos scripts 3, 4, 8 e 10

# serie diaria com os dias sem imagem como NA
monta_ts <- function(datas, valores) bfastts(valores, as.Date(datas), type = "irregular")

# data para ano decimal e volta, na grade de 365 dias do bfastts
dia365 <- function(d) {
  x <- as.POSIXlt(d)
  c(0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334)[1 + x$mon] + x$mday
}
data_para_decimal <- function(d) 1900 + as.POSIXlt(d)$year + (dia365(d) - 1) / 365
decimal_para_data <- function(x) {
  datas <- rep(as.Date(NA), length(x))
  ok <- !is.na(x)
  if (!any(ok)) return(datas)
  ano <- floor(x[ok])
  k <- round((x[ok] - ano) * 365)
  bis <- (ano %% 4 == 0 & ano %% 100 != 0) | ano %% 400 == 0
  datas[ok] <- as.Date(paste0(ano, "-01-01")) + k + (bis & k >= 59)
  datas
}

# BFAST Lite na serie completa de cada pixel, com os parametros padrao do pacote.
# pasta_graficos: se informada, salva o grafico do pacote de cada pixel
roda_lite <- function(ndvi, pixels, coluna = "NDVI", pasta_graficos = NULL) {
  quebras <- data.frame()
  for (p in pixels$pixel) {
    serie <- ndvi[ndvi$pixel == p, ]
    resultado <- bfastlite(monta_ts(serie$date, serie[[coluna]]))

    # grafico do proprio pacote; breaks = "LWZ" para mostrar as mesmas quebras do bfastlite
    if (!is.null(pasta_graficos)) {
      pasta <- sprintf("%s/buffer_%02d", pasta_graficos, pixels$buffer[pixels$pixel == p])
      dir.create(pasta, recursive = TRUE, showWarnings = FALSE)
      png(sprintf("%s/%s.png", pasta, p), width = 1400, height = 600, res = 130)
      plot(resultado, breaks = "LWZ")
      dev.off()
    }

    tabela <- resultado$data_pp
    datas <- decimal_para_data(tabela$time)
    posicoes <- resultado$breakpoints$breakpoints   # ultima imagem antes de cada quebra
    if (is.na(posicoes[1])) next
    limites <- c(0, posicoes, nrow(tabela))

    # magnitude: modelo do trecho depois menos o do trecho antes, na primeira imagem depois da quebra
    for (k in seq_along(posicoes)) {
      antes <- tabela[(limites[k] + 1):limites[k + 1], ]
      depois <- tabela[(limites[k + 1] + 1):limites[k + 2], ]
      magnitude <- predict(lm(response ~ trend + harmon, data = depois), depois[1, ]) -
                   predict(lm(response ~ trend + harmon, data = antes), depois[1, ])
      quebras <- rbind(quebras, data.frame(pixel = p, buffer = pixels$buffer[pixels$pixel == p],
        talhao = pixels$talhao[pixels$pixel == p], data_quebra = datas[limites[k + 1]],
        magnitude = round(as.numeric(magnitude), 4)))
    }
  }
  quebras
}

# Votacao: as quebras a ate tolerancia_dias da quebra de referencia formam um grupo,
# aceito se tiver mais da metade dos pixels da area
agrupa_eventos <- function(quebras, pixels) {
  eventos <- data.frame()
  for (b in sort(unique(pixels$buffer))) {
    n_pixels <- sum(pixels$buffer == b)
    q <- quebras[quebras$buffer == b, ]
    if (nrow(q) == 0) next
    q$usada <- FALSE

    while (any(!q$usada)) {
      livres <- which(!q$usada)
      # referencia: a quebra com mais pixels proximos dela
      contagem <- sapply(livres, function(i) {
        perto <- livres[abs(as.numeric(q$data_quebra[livres] - q$data_quebra[i])) <= tolerancia_dias]
        length(unique(q$pixel[perto]))
      })
      referencia <- livres[which.max(contagem)]

      # uma quebra por pixel, a mais perto da referencia
      distancia <- abs(as.numeric(q$data_quebra - q$data_quebra[referencia]))
      candidatas <- livres[distancia[livres] <= tolerancia_dias]
      candidatas <- candidatas[order(distancia[candidatas])]
      membros <- candidatas[!duplicated(q$pixel[candidatas])]
      q$usada[membros] <- TRUE

      m <- q[membros, ]
      eventos <- rbind(eventos, data.frame(buffer = b, talhao = m$talhao[1],
        data = median(m$data_quebra), primeira = min(m$data_quebra), ultima = max(m$data_quebra),
        pixels_buffer = n_pixels, pixels_com_quebra = nrow(m), aceito = nrow(m) / n_pixels > maioria,
        magnitude_mediana = round(median(m$magnitude), 4)))
    }
  }
  eventos <- eventos[order(eventos$buffer, eventos$data), ]

  # fase pelo mes da quebra (Camargo e Camargo, 2001) e direcao pelo sinal da magnitude
  mes <- as.integer(format(eventos$data, "%m"))
  eventos$fase_ciclo <- ifelse(mes %in% 9:12, "florada",
                        ifelse(mes %in% 1:3, "granacao",
                        ifelse(mes %in% 4:6, "maturacao", "repouso")))
  eventos$direcao <- ifelse(eventos$magnitude_mediana < 0, "queda", "aumento")
  eventos
}

# BFAST Monitor em cada pixel de cada quebra aceita pelo Lite (par: ver parametros.R).
# Retorna as tabelas por pixel e por evento
roda_monitor <- function(ndvi, pixels, eventos, par, pasta_graficos = NULL, coluna = "NDVI") {
  todos_pixels <- data.frame()
  resumo <- data.frame()

  for (b in sort(unique(eventos$buffer))) {
    ev <- eventos[eventos$buffer == b, ]
    ev <- ev[order(ev$data), ]

    for (k in 1:nrow(ev)) {
      # periodo estavel: do dia seguinte ao grupo anterior (ou do inicio da serie) ate a quebra
      estavel_inicio <- if (k == 1) min(ndvi$date) else ev$ultima[k - 1] + 1
      # data da quebra: dia seguinte a primeira quebra do grupo
      quebra <- ev$primeira[k] + 1
      inicio_monit <- quebra - par$recuo_dias
      if (as.numeric(inicio_monit - estavel_inicio) < par$dias_minimos) next
      fim_teste <- if (k < nrow(ev)) ev$primeira[k + 1] else max(ndvi$date)
      fim_janela <- quebra + par$janela_dias

      x <- data.frame()
      for (p in pixels$pixel[pixels$buffer == b]) {
        serie <- ndvi[ndvi$pixel == p & ndvi$date >= estavel_inicio & ndvi$date <= fim_teste, ]
        bm <- bfastmonitor(monta_ts(serie$date, serie[[coluna]]), start = data_para_decimal(inicio_monit),
                           formula = par$formula, order = par$order, history = par$history,
                           h = par$h, level = c(par$level, 0.05))

        if (!is.null(pasta_graficos)) {
          pasta <- sprintf("%s/buffer_%02d/evento_%s", pasta_graficos, b, ev$data[k])
          dir.create(pasta, recursive = TRUE, showWarnings = FALSE)
          png(sprintf("%s/%s.png", pasta, p), width = 1400, height = 600, res = 130)
          plot(bm)
          dev.off()
        }

        alarme <- decimal_para_data(bm$breakpoint)
        situacao <- if (is.na(alarme)) "sem_alarme"
                    else if (alarme < quebra) "antes_da_quebra"
                    else if (alarme <= fim_janela) "na_janela"
                    else "apos_janela"

        x <- rbind(x, data.frame(buffer = b, evento = ev$data[k], pixel = p, alarme = alarme,
          atraso_dias = as.numeric(alarme - quebra), situacao = situacao))
      }
      todos_pixels <- rbind(todos_pixels, x)

      # detectada se mais da metade dos pixels alarmar na janela
      na_janela <- x$situacao == "na_janela"
      resumo <- rbind(resumo, data.frame(
        buffer = b, talhao = ev$talhao[k], evento = ev$data[k], direcao = ev$direcao[k],
        magnitude_lite = ev$magnitude_mediana[k],
        estavel_inicio = estavel_inicio, quebra = quebra,
        monitor_inicio = inicio_monit, monitor_fim = fim_teste,
        dias_historico = as.numeric(inicio_monit - estavel_inicio),
        pixels = nrow(x),
        pixels_antes = sum(x$situacao == "antes_da_quebra"),
        pixels_na_janela = sum(na_janela),
        pixels_apos_janela = sum(x$situacao == "apos_janela"),
        pixels_sem_alarme = sum(x$situacao == "sem_alarme"),
        atraso_mediano_dias = if (any(na_janela)) median(x$atraso_dias[na_janela]) else NA,
        detectado = sum(na_janela) / nrow(x) > 0.5))
    }
  }
  list(pixels = todos_pixels, eventos = resumo)
}
