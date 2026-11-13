# Análise final do TFG

BFAST Lite para definir o período histórico estável de cada área amostral e BFAST Monitor com `history = "all"`, iniciado pouco antes de cada quebra. Parte do código do artigo do SBSR, usando as mesmas 18 áreas amostrais.

## Como rodar

Rodar dentro desta pasta, na ordem:

```
node 1_extrai_ndvi.mjs
Rscript 2_organiza_pixels.R
Rscript 3_bfast_lite.R
Rscript 4_bfast_monitor.R
node 5_extrai_imagens_quebras.mjs
Rscript 6_mapas_diferenca.R
node 7_extrai_bandas.mjs
Rscript 8_indices.R
Rscript 9_cruza_indices.R
Rscript 10_monitor_mesmas_quebras.R
```

Os passos 1, 5 e 7 precisam da chave do Earth Engine (`EE_SERVICE_ACCOUNT_FILE` ou `../local/service_account.json`). Os demais precisam dos pacotes `bfast` e `jsonlite`. Todos os parâmetros ficam em [parametros.R](parametros.R).

## Saídas

- `resultados/quebras_pixel.csv`: quebras do BFAST Lite por pixel.
- `resultados/eventos_buffer.csv`: grupos de quebras por área amostral e resultado da votação.
- `resultados/monitor_pixels.csv`: alarme de cada pixel em cada quebra testada; `situacao` vale `antes_da_quebra`, `na_janela`, `apos_janela` ou `sem_alarme`.
- `resultados/monitor_eventos.csv`: resumo por quebra testada.
- `resultados/diferenca_quebras.csv`: diferença média de NDVI (depois − antes) dentro da área amostral e no restante dos talhões, para cada quebra aceita.
- `resultados/indices/<EVI|NDMI>/`: quebras do BFAST Lite e votação para o EVI e o NDMI.
- `resultados/indices/cruzamento_lite.csv`: quebras aceitas dos três índices agrupadas por área, quando estão a até 30 dias uma da outra e têm a mesma direção.
- `resultados/indices/monitor_mesmas_quebras.csv`: detecção e alarmes dos três índices nas quebras aceitas do NDVI.
- `figuras/mapas_diferenca/` e `figuras/por_pixel/`: mapas de diferença e gráficos do pacote para cada pixel (não versionados, assim como `dados/`).
