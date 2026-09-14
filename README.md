# coffee-spectral-anomaly-detection

Detecção de anomalias em séries temporais de NDVI de áreas cafeeiras com
Sentinel-2 e BFAST Monitor. Código do TFG *Detecção de anomalias em séries
temporais espectrais da cafeicultura no Sul de Minas Gerais* (UNIFEI).

## Análises

`bfastmonitor` em quatro combinações:

| | sem máscara de nuvem | com máscara de nuvem |
|---|---|---|
| por pixel | um ajuste por pixel | um ajuste por pixel |
| pixel-centroide | um ajuste | um ajuste |

## Execução

```bash
npm ci
Rscript R/instala_dependencias.R

node gee/extrai_serie.js
Rscript R/analise.R
Rscript R/figuras.R
```

As saídas vão para `local/` (fora do git). O workflow `analise.yml` roda os
mesmos três passos todo dia com `DIR_SAIDA=.` e commita `resultados/*.csv`.

Autenticação no Earth Engine: service account em `EE_SERVICE_ACCOUNT_JSON`,
`EE_SERVICE_ACCOUNT_FILE` ou `local/service_account.json`. `EE_PROJECT` define
o projeto.

## Parâmetros do bfastmonitor

Verbesselt, Zeileis e Herold (2012), *Near real-time disturbance detection using
satellite image time series*, Remote Sensing of Environment 123, 98–108.

| Parâmetro | Valor |
|---|---|
| `start` (`monitor_inicio`) | 2021-06-01 |
| `formula` | `response ~ harmon` |
| `order` | 3 |
| `history` | `all` |
| `type` | `OLS-MOSUM` |
| `h` | 0.25 |
| `end` | 10 |
| `level` | 0.05 |
| `min_obs_historico` | 46 |

## Saídas

| Arquivo | Conteúdo |
|---|---|
| `resultados/quebras_por_pixel_<mascara>.csv` | uma linha por pixel |
| `resultados/quebras_por_mes_<mascara>.csv` | pixels com quebra por mês |
| `resultados/centroide.csv` | pixel-centroide, uma linha por máscara |
| `resultados/centroide_<mascara>.rds` | objeto do `bfastmonitor` |
| `figuras/mapa_quebras_<mascara>.png` | data da quebra por pixel |
| `figuras/periodo_quebras_<mascara>.png` | pixels com quebra por mês |
| `figuras/monitor_centroide_<mascara>.png` | saída do `bfastmonitor` no centroide |

`desvio_quebra` é a mediana do resíduo na janela MOSUM que cruzou a fronteira
(negativo = NDVI abaixo do modelo). `magnitude` é a do `bfastmonitor`, calculada
sobre todo o monitoramento.

## Estrutura

```
config.yml          parâmetros
area/               talhões da área de estudo
gee/                extração no Earth Engine (Node)
R/                  agregação, bfastmonitor e figuras
inspecao/           seleção da área e diagnósticos
resultados/         tabelas commitadas pelo workflow
```
