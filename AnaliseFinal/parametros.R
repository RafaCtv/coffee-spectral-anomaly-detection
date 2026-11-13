# Parametros da analise

# BFAST Lite: votacao por area amostral
tolerancia_dias <- 30   # quebras a ate 30 dias da quebra de referencia formam um grupo
maioria <- 0.5          # grupo aceito se tiver mais que esta fracao dos pixels

# BFAST Monitor
par_monitor <- list(
  # parametros do pacote
  history = "all",                     # usa todo o periodo estavel definido pelo Lite
  formula = response ~ trend + harmon,
  order = 3,
  h = 0.25,
  level = 0.05,
  # parametros do experimento
  dias_minimos = 730,   # historico minimo antes do inicio do monitoramento (2 ciclos do cafe)
  recuo_dias = 15,      # o monitoramento comeca este numero de dias antes da quebra
  janela_dias = 90      # alarme ate este numero de dias depois da quebra conta como deteccao
)
