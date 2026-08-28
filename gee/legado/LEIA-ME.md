# Scripts da versão anterior

Mantidos para referência. Não são usados pelo pipeline — foram reescritos em
`gee/extrai_serie.py` e `R/monitora.R`.

| Arquivo | O que era |
|---|---|
| `SentinelBS.js` | primeiro recorte da área de Bom Sucesso |
| `NDVI_com_mascara.js` | análise agregada (média do talhão), descartada |
| `NDVI_pixel_centroide_com_mascaraNuvem.js` | extração do pixel-centroide, com máscara |
| `NDVI_pixel_centroid_sem_mascaraNuvem.js` | idem, sem máscara |
| `bfast_pixel_centroide.R` | BFAST Monitor no centroide |
| `bfast_por_pixel.R` | BFAST Monitor em todos os pixels do talhão |

## O que mudou

**Extração incremental.** Os `.js` reextraíam todo o período a cada execução e
dependiam de `Export.table.toDrive`, que é assíncrono e não pode ser agendado a
partir do Code Editor.

**Deduplicação.** `bfast_pixel_centroide.R` filtrava por
`duplicated(datetime, NDVI)`, combinação que nunca se repete — as entregas
redundantes vêm de quadrículas diferentes, com instantes separados por segundos.
O filtro removia zero linhas. `bfast_por_pixel.R` não tinha filtro. A agregação
agora é explícita, por pixel e dia.

**Estado.** Os scripts antigos recomeçavam do zero e reportavam sempre a mesma
quebra. `R/monitora.R` mantém estado por pixel e redefine o período histórico
após uma detecção.

**Parâmetros.** Área, datas, limiar de nuvem e parâmetros do BFAST estavam
repetidos entre `.js` e `.R`, e divergiam. Agora ficam só no `config.yml`.
