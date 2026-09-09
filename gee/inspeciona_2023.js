// Inspecao visual da perturbacao detectada no 2o semestre de 2023.
//
// A analise em R apontou 170 pixels (~1,6 ha) com queda de NDVI entre set e
// dez/2023, seguida de recuperacao lenta. O padrao (bordas retas, grupo mais
// vigoroso que o resto ate 2022, queda permanente) sugere recepa.
//
// Recepa preserva as fileiras de plantio: as plantas continuam vivas, so
// decepadas. Erradicacao e replantio revolvem o solo e apagam o alinhamento.
//
// Compara sempre o mesmo periodo do ano (ago-set, contraste maximo entre
// cafe e solo na estiagem), senao a comparacao mistura sazonalidade.

var IMOVEL = 'projects/spad05/assets/Area_do_Imovel';
var CAFE   = 'projects/spad05/assets/BomSucesso';
var ANOS   = [2022, 2023, 2024, 2026];
var JANELA = ['-08-01', '-09-30'];

// O shapefile do CAR traz duas feicoes com o mesmo perimetro; geometry() une.
var imovel = ee.FeatureCollection(IMOVEL).geometry();

var talhoes = ee.FeatureCollection(CAFE)
                .filterBounds(imovel)
                .map(function (f) {
                  return f.setGeometry(f.geometry().intersection(imovel, 1));
                })
                .filter(ee.Filter.gt('Area_ha', 0.5));

print('Talhoes de cafe no imovel:', talhoes.size());
print('Area de cafe (ha):', talhoes.geometry().area(10).divide(1e4));

var cs = ee.ImageCollection('GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED');

function composicao(ano) {
  return ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
           .filterBounds(imovel)
           .filterDate(ano + JANELA[0], ano + JANELA[1])
           .linkCollection(cs, ['cs_cdf'])
           .map(function (img) {
             return img.updateMask(img.select('cs_cdf').gte(0.6));
           })
           .median()
           .clip(imovel.buffer(300));
}

Map.centerObject(talhoes, 15);

// Falsa cor: cafe adulto em vermelho intenso e texturado, solo em ciano/cinza.
ANOS.forEach(function (a) {
  Map.addLayer(composicao(a), {bands: ['B8', 'B4', 'B3'], min: 0, max: 5000},
               'Falsa cor ago-set ' + a, false);
});
ANOS.forEach(function (a) {
  Map.addLayer(composicao(a), {bands: ['B4', 'B3', 'B2'], min: 0, max: 3000},
               'Cor verdadeira ago-set ' + a, false);
});

// NDVI do mesmo periodo, para quantificar a diferenca.
function ndvi(ano) {
  return composicao(ano).normalizedDifference(['B8', 'B4']).rename('NDVI');
}
ANOS.forEach(function (a) {
  Map.addLayer(ndvi(a), {min: 0.2, max: 0.9,
               palette: ['brown', 'yellow', 'green', 'darkgreen']},
               'NDVI ago-set ' + a, false);
});

// Diferenca 2024 - 2022: onde a lavoura perdeu vigor entre os dois anos.
Map.addLayer(ndvi(2024).subtract(ndvi(2022)),
             {min: -0.4, max: 0.4, palette: ['red', 'white', 'blue']},
             'NDVI 2024 - 2022 (vermelho = perda)', true);

Map.addLayer(ee.Image().paint(ee.FeatureCollection([ee.Feature(imovel)]), 0, 2),
             {palette: 'blue'}, 'Perimetro do imovel');
Map.addLayer(ee.Image().paint(talhoes, 0, 2),
             {palette: 'yellow'}, 'Talhoes de cafe');

// NDVI medio dos talhoes em cada ano, no mesmo periodo.
var serie = ee.FeatureCollection(ANOS.map(function (a) {
  var m = ndvi(a).reduceRegion({
    reducer: ee.Reducer.mean(), geometry: talhoes.geometry(),
    scale: 10, maxPixels: 1e9
  }).get('NDVI');
  return ee.Feature(null, {ano: a, NDVI: m});
}));
print('NDVI medio dos talhoes em ago-set:', serie);
print(ui.Chart.feature.byFeature(serie, 'ano', ['NDVI'])
        .setChartType('ColumnChart')
        .setOptions({title: 'NDVI medio ago-set por ano',
                     vAxis: {viewWindow: {min: 0, max: 1}}}));
