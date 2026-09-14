// Inspecao visual da area candidata. Rodar no Code Editor do Earth Engine.
//
// 1. Desenhe o poligono com a ferramenta de geometria e nomeie como "area",
//    ou importe o shapefile como asset.
// 2. Rode e leia o console.
// 3. Copie o GeoJSON impresso no final para area/fazenda_car.geojson.

var DATA_INICIO  = '2026-01-01';
var DATA_FIM     = '2026-12-31';
var LIMIAR_NUVEM = 0.6;

var col = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
            .filterBounds(area)
            .filterDate(DATA_INICIO, DATA_FIM);

print('Imagens no periodo:', col.size());

// Mais de uma quadricula = a area esta na faixa de sobreposicao (110 km de
// lado, espacadas de 100 km), o que gera observacoes redundantes por passagem.
var tiles = col.aggregate_array('MGRS_TILE').distinct();
print('Quadriculas MGRS:', tiles);
print('Orbitas:', col.aggregate_array('SENSING_ORBIT_NUMBER').distinct());

var contornos = ee.FeatureCollection(
  tiles.map(function (t) {
    var img = col.filter(ee.Filter.eq('MGRS_TILE', t)).first();
    return ee.Feature(ee.Image(img).geometry(), {tile: t});
  })
);
Map.addLayer(contornos.style({color: 'yellow', fillColor: '00000000', width: 2}),
             {}, 'Limites das quadriculas');

var cs = ee.ImageCollection('GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED');
var limpa = col.linkCollection(cs, ['cs_cdf'])
               .map(function (img) {
                 return img.updateMask(img.select('cs_cdf').gte(LIMIAR_NUVEM));
               });

Map.centerObject(area, 14);
Map.addLayer(limpa.median(), {bands: ['B4', 'B3', 'B2'], min: 0, max: 3000},
             'Cor verdadeira');
// Em falsa cor o cafe aparece em vermelho intenso, separando bem de pasto e mata.
Map.addLayer(limpa.median(), {bands: ['B8', 'B4', 'B3'], min: 0, max: 5000},
             'Falsa cor', false);

var ndvi = limpa.map(function (img) {
  return img.normalizedDifference(['B8', 'B4']).rename('NDVI');
});
Map.addLayer(ndvi.median().clip(area),
             {min: 0.2, max: 0.9, palette: ['white', 'yellow', 'green', 'darkgreen']},
             'NDVI mediano', false);
Map.addLayer(area, {color: 'red'}, 'Area de estudo');

var contagem = ndvi.count().clip(area);
Map.addLayer(contagem, {min: 0, max: 80, palette: ['red', 'orange', 'green']},
             'Observacoes validas por pixel', false);

print('Observacoes validas por pixel:', contagem.reduceRegion({
  reducer: ee.Reducer.minMax().combine(ee.Reducer.mean(), '', true),
  geometry: area, scale: 10, maxPixels: 1e9
}));

print(ui.Chart.image.series({
  imageCollection: ndvi,
  region: area,
  reducer: ee.Reducer.mean(),
  scale: 10
}).setOptions({
  title: 'NDVI medio da area candidata',
  hAxis: {title: 'Data'},
  vAxis: {title: 'NDVI', minValue: 0, maxValue: 1},
  lineWidth: 2, pointSize: 3
}));

print('GeoJSON da area:', area);
