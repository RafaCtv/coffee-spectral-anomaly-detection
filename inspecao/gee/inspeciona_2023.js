// Composicoes de ago-set por ano sobre a queda de NDVI de 2023 (recepa).
// Sempre a mesma janela do ano para nao misturar sazonalidade

var IMOVEL = 'projects/spad05/assets/Area_do_Imovel';
var CAFE   = 'projects/spad05/assets/BomSucesso';
var ANOS   = [2022, 2023, 2024, 2026];
var JANELA = ['-08-01', '-09-30'];

// o CAR traz duas feicoes com o mesmo perimetro, geometry() une as duas
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

// falsa cor e cor verdadeira por ano
ANOS.forEach(function (a) {
  Map.addLayer(composicao(a), {bands: ['B8', 'B4', 'B3'], min: 0, max: 5000},
               'Falsa cor ago-set ' + a, false);
});
ANOS.forEach(function (a) {
  Map.addLayer(composicao(a), {bands: ['B4', 'B3', 'B2'], min: 0, max: 3000},
               'Cor verdadeira ago-set ' + a, false);
});

// NDVI da mesma janela
function ndvi(ano) {
  return composicao(ano).normalizedDifference(['B8', 'B4']).rename('NDVI');
}
ANOS.forEach(function (a) {
  Map.addLayer(ndvi(a), {min: 0.2, max: 0.9,
               palette: ['brown', 'yellow', 'green', 'darkgreen']},
               'NDVI ago-set ' + a, false);
});

// diferenca 2024 - 2022, vermelho = perda de vigor
Map.addLayer(ndvi(2024).subtract(ndvi(2022)),
             {min: -0.4, max: 0.4, palette: ['red', 'white', 'blue']},
             'NDVI 2024 - 2022 (vermelho = perda)', true);

Map.addLayer(ee.Image().paint(ee.FeatureCollection([ee.Feature(imovel)]), 0, 2),
             {palette: 'blue'}, 'Perimetro do imovel');
Map.addLayer(ee.Image().paint(talhoes, 0, 2),
             {palette: 'yellow'}, 'Talhoes de cafe');

// NDVI medio dos talhoes por ano
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
