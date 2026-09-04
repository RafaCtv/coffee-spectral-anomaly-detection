// Verifica se um ponto qualquer cai na faixa de sobreposicao entre quadriculas
// do Sentinel-2, sem depender de asset nenhum.
//
// As quadriculas MGRS tem 110 km e sao espacadas de 100 km, entao vizinhas se
// sobrepoem em ~10 km. Um alvo nessa faixa recebe o mesmo pixel em dois
// produtos por passagem, e o bfastts descarta um deles silenciosamente.
//
// Camada "Cobertura": verde = 1 quadricula (usar), laranja/vermelho = 2 ou mais.

var LON  = -45.112189;
var LAT  = -22.134052;
var RAIO = 8000;      // m; extensao inspecionada em volta do ponto
var ANO  = 2026;

var ponto = ee.Geometry.Point([LON, LAT]);
var area  = ponto.buffer(RAIO).bounds();

// --- quadriculas exatamente sobre o ponto ---------------------------
var noPonto = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
                .filterBounds(ponto)
                .filterDate(ANO + '-01-01', ANO + '-12-31');

print('--- ponto ' + LON + ', ' + LAT + ' ---');
print('Quadriculas MGRS:', noPonto.aggregate_array('MGRS_TILE').distinct().sort());
print('Orbitas:', noPonto.aggregate_array('SENSING_ORBIT_NUMBER').distinct().sort());
print('Imagens em ' + ANO + ':', noPonto.size());
print('Uma quadricula = fora da sobreposicao.');

// --- cobertura na vizinhanca ----------------------------------------
var s2 = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
           .filterBounds(area)
           .filterDate(ANO + '-01-01', ANO + '-06-30');

var tiles = s2.aggregate_array('MGRS_TILE').distinct().sort();
print('Quadriculas num raio de ' + (RAIO / 1000) + ' km:', tiles);

// Quantas quadriculas cobrem cada pixel.
var cobertura = ee.ImageCollection.fromImages(
  tiles.map(function (t) {
    var img = s2.filter(ee.Filter.eq('MGRS_TILE', t)).first();
    return ee.Image(1).clip(ee.Image(img).geometry()).rename('n');
  })
).sum().unmask(0).clip(area);

var footprints = ee.FeatureCollection(tiles.map(function (t) {
  var img = s2.filter(ee.Filter.eq('MGRS_TILE', t)).first();
  return ee.Feature(ee.Image(img).geometry(), {tile: t});
}));

Map.centerObject(ponto, 12);
Map.addLayer(cobertura.updateMask(cobertura.gt(0)),
             {min: 1, max: 3, palette: ['00b050', 'ff8c00', 'ff0000']},
             'Cobertura (verde=1, laranja=2, vermelho=3+)');
Map.addLayer(footprints.style({color: 'blue', fillColor: '00000000', width: 2}),
             {}, 'Limites das quadriculas');
Map.addLayer(ponto, {color: 'black'}, 'Ponto');

// --- densidade e contexto visual -------------------------------------
var cs = ee.ImageCollection('GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED');
var limpa = noPonto.linkCollection(cs, ['cs_cdf'])
                   .map(function (img) {
                     return img.updateMask(img.select('cs_cdf').gte(0.6));
                   });

var ndvi = limpa.map(function (img) {
  return img.normalizedDifference(['B8', 'B4']).rename('NDVI');
});
print('Observacoes validas em ' + ANO + ' no ponto:', ndvi.count().reduceRegion({
  reducer: ee.Reducer.first(), geometry: ponto, scale: 10
}));

Map.addLayer(limpa.median(), {bands: ['B4', 'B3', 'B2'], min: 0, max: 3000},
             'Cor verdadeira ' + ANO, false);
Map.addLayer(limpa.median(), {bands: ['B8', 'B4', 'B3'], min: 0, max: 5000},
             'Falsa cor ' + ANO, false);

print(ui.Chart.image.series({
  imageCollection: ndvi, region: ponto, reducer: ee.Reducer.first(), scale: 10
}).setOptions({title: 'NDVI no ponto (' + ANO + ')', lineWidth: 2, pointSize: 3}));
