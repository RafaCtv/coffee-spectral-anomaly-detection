# Escolha e ajuste da área de estudo

Notas de apoio à definição da nova área (uma fazenda, em substituição ao
talhão de Bom Sucesso).

## Bordas a evitar

**Borda de quadrícula.** O Sentinel-2 imageia uma faixa contínua de 290 km, mas
é distribuído recortado na grade MGRS. As quadrículas têm 110 km e são
espaçadas de 100 km, logo vizinhas se sobrepõem em ~10 km. Uma área nessa faixa
recebe o mesmo pixel em dois produtos por passagem, com instantes separados por
poucos segundos e NDVI ligeiramente diferente pela reamostragem independente.

Foi o caso da área original: 50,1% das linhas do CSV eram entregas redundantes
das quadrículas `T23KMS` e `T23KNS`. O pipeline trata isso agregando por
pixel-dia, mas escolher uma área dentro de uma única quadrícula elimina o
problema na origem.

**Borda de talhão.** Um pixel de 10 m sobre a divisa é misto — parte café,
parte carreador, mata ou pasto. A série combina duas dinâmicas e gera quebras
que não correspondem a nada acontecendo no cafeeiro. Mitigação: recuo
(*buffer* negativo) de 10 a 20 m no polígono.

## Verificação de uma candidata

Visual, no Code Editor: `gee/inspeciona_area.js` desenha os contornos das
quadrículas sobre o mapa, a composição de 2026, o NDVI mediano, a contagem de
observações válidas por pixel e a série temporal média.

Numérico, com o polígono salvo:

```bash
python gee/checa_area.py --area area/candidata_01.geojson
```

| Critério | Alvo | Motivo |
|---|---|---|
| Quadrículas MGRS | 1 | 2 ou mais = faixa de sobreposição |
| Órbitas | 1 | mais de uma varia a geometria de visada |
| Observações válidas por pixel | ≥ 60 no histórico | histórico curto desestabiliza o ajuste sazonal |
| Ciclo sazonal visível | sim | sem ciclo, o modelo harmônico não tem o que ajustar |
| Tamanho | dezenas a poucas centenas de ha | mantém a execução diária barata |

## Ajuste dos polígonos

Os polígonos existentes (`ConceicaoCafeAjustado.shp`, `cafeMinasCorrigido.shp`)
foram digitalizados sobre imagens de anos atrás. Entre aquela data e 2026, os
talhões podem ter passado por renovação, replantio, recepa, ampliação ou
abandono, e carreadores podem ter sido abertos. Polígono desatualizado inclui
na análise pixels que não são café, cada um com sua própria dinâmica espectral —
o BFAST detecta quebras neles, reais, mas de outra coisa.

O ajuste consiste em redesenhar os limites sobre uma imagem recente, tipicamente
no QGIS: carregar a imagem de 2026 como fundo, sobrepor o shapefile, ativar a
edição e mover os vértices até coincidirem com o café visível; remover o que
deixou de ser café e acrescentar o que passou a ser. Em falsa cor
(NIR-vermelho-verde) o café aparece em vermelho intenso e se separa bem de
pasto e mata.

Registrar, para a metodologia:

- sensor e data exata da imagem de referência;
- se os limites foram editados a partir do mapeamento anterior ou digitalizados
  do zero;
- se o polígono já vem com recuo da borda;
- talhões com renovação ou recepa em data conhecida.

O último item fornece casos de teste com verdade de campo: são quebras que o
método deve detectar, com data verdadeira conhecida.

**Consequência metodológica.** Polígonos ajustados sobre imagem de 2026
descrevem a lavoura em 2026. Aplicá-los a uma série iniciada em 2019 assume que
aquela área era café durante todo o período — falso para talhões renovados no
meio da série. Ou o período de análise começa após a última mudança conhecida,
ou a mudança entra como evento esperado na interpretação.

## Formato

Salvar como GeoJSON em `area/fazenda.geojson`, EPSG:4326, e atualizar o
`config.yml`:

```yaml
area_geojson: area/fazenda.geojson
area_nome: Fazenda XYZ - Município (MG)
```

GeoJSON em vez de shapefile: um arquivo em vez de cinco, é texto e versiona bem
no git, e é lido diretamente pelo Earth Engine. Conversão no QGIS:
`Camada > Salvar como... > GeoJSON`, SRC EPSG:4326.
