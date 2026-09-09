# coffee-spectral-anomaly-detection

Pipeline de detecção de anomalias em séries temporais espectrais de áreas
cafeeiras, com Sentinel-2 e BFAST Monitor.

Código de apoio ao TFG *Detecção de anomalias em séries temporais espectrais da
cafeicultura no Sul de Minas Gerais* (UNIFEI). O texto da monografia não faz
parte deste repositório.

## O que faz

Extrai séries de NDVI de uma fazenda a partir do Sentinel-2, aplica o BFAST
Monitor a cada pixel e registra alertas quando detecta quebra estrutural. Roda
sozinho, uma vez por dia.

```
Earth Engine  ->  dados/serie_ndvi.csv  ->  R/monitora.R  ->  estado/alertas.csv
 (incremental)     (bruto, fora do git)     (bfastts +        (versionado)
                                             bfastmonitor)
```

Diferente de uma análise retrospectiva, o pipeline mantém estado: não recomeça
do zero a cada execução e redefine o período histórico depois de uma quebra.

## Uso

```bash
Rscript R/instala_dependencias.R
pip install earthengine-api
earthengine authenticate

# definir a área (ver docs/escolha_da_area.md), salvar em area/fazenda_car.geojson
# e atualizar area_geojson e area_nome no config.yml

python gee/checa_area.py       # valida a área escolhida
python gee/extrai_serie.py     # extrai a série
Rscript R/monitora.R replay    # valida o método contra a geada de 2021
Rscript R/monitora.R operacao  # uso corrente
Rscript R/figuras.R
```

No Windows: `.\executa.ps1 -ComFiguras`

## Modos

| Modo | O que faz |
|---|---|
| `replay` | Alimenta as observações em ordem cronológica sobre o passado, medindo quando o alerta teria sido emitido. Calcula o MTTD contra um evento conhecido. Evita esperar meses de operação real |
| `operacao` | Avalia apenas o que é novo, a partir de `monitor_inicio` |

## Estrutura

```
config.yml                 parâmetros (Python e R leem daqui)
area/fazenda_car.geojson   polígono da área de estudo
gee/
  comum.py                 auth, config, área, coleção NDVI
  checa_area.py            diagnóstico de área candidata
  extrai_serie.py          extração incremental
  inspeciona_area.js       inspeção visual no Code Editor
  legado/                  scripts da versão anterior
R/
  config.R                 leitor do config.yml
  funcoes.R                agregação pixel-dia, montagem da série
  monitora.R               máquina de estados
  inspeciona_serie.R       execução avulsa, fora da máquina de estados
  figuras.R                mapa, histograma, saída do bfastmonitor
dados/                     série bruta (fora do git)
estado/                    estado por pixel, resumo e alertas
executa.ps1                orquestrador local
.github/workflows/         agendamento
```

## Notas de implementação

**Observações concorrentes no mesmo dia.** Duas causas distintas. Reprocessamento
da ESA entrega a mesma aquisição em dois produtos (mesmo datatake, tempos de
geração diferentes): fica a versão mais recente, sem critério a escolher.
Datatakes distintos no mesmo dia são medições reais e concorrentes; `agregacao_dia`
define se fica a primeira ou a média. Como o `bfastts` indexa por ano e dia, sem
regra explícita ele manteria a última linha, arbitrariamente. Resolver isso antes,
em `R/funcoes.R`, faz o número de observações reportado ser o usado no ajuste.

**Saída do `bfastts(type = "irregular")`.** Um `ts` de frequência 365: grade
diária da primeira à última observação, dias sem imagem como `NA`, sem
interpolação. O ciclo é anual, a frequência é diária. O dia do ano vem de um
calendário fixo de 365 dias, o que desloca em um dia as datas posteriores a
fevereiro em anos bissextos.

## Credenciais

A chave da service account não entra no repositório. Localmente, usar
`earthengine authenticate`. No GitHub Actions, os secrets
`EE_SERVICE_ACCOUNT_JSON` e `EE_PROJECT`.

## Pendente

- Validação em modo `replay` contra a geada de julho de 2021, para o MTTD
- Ajuste dos polígonos sobre imagem recente; o mapeamento de origem é de 13/06/2022
- `decimal_para_data` em `R/funcoes.R` usa o comprimento real do ano, enquanto o
  `bfastts` usa grade fixa de 365 dias: datas de quebra em anos bissextos saem
  com um dia de diferença
- Varredura de `bfast_order` e da largura da janela MOSUM
