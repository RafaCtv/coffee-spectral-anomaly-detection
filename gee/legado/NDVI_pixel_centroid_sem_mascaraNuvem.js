// =========================================================
// Série temporal de NDVI - UM pixel (centroide do maior talhão)
// Sentinel-2 SR (L2A) com máscara Cloud Score+, 2019-01-01 a 2023-01-01
// Um pixel = um valor por data, sem agregação espacial.
// =========================================================

// Seleciona o maior talhão e pega o pixel do seu centroide
var poligono = ee.Feature(BS.sort('Area_ha', false).first());
var ponto = poligono.geometry().centroid(10);  // erro máx. de 10 m
print('Talhão escolhido:', poligono);

Map.centerObject(ponto, 16);
Map.addLayer(poligono.geometry(), {color: 'gray'}, 'Talhão');
Map.addLayer(ponto, {color: 'red'}, 'Pixel (centroide)');

// Coleção Sentinel-2 com máscara de nuvem, filtrada pelo ponto
var colecao = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
                .filterBounds(ponto)
                .filterDate('2019-01-01', '2023-01-01')

// Calcula o NDVI = (B8 - B4) / (B8 + B4)
var calculaNDVI = function(imagem) {
  var ndvi = imagem.normalizedDifference(['B8', 'B4']).rename('NDVI');
  return imagem.addBands(ndvi);
};

var colecaoNDVI = colecao.map(calculaNDVI);
print('Número de imagens:', colecao.size());

// Gráfico da série temporal do pixel
var chart = ui.Chart.image.series({
  imageCollection: colecaoNDVI.select('NDVI'),
  region: ponto,
  reducer: ee.Reducer.first(),  // 1 pixel -> pega o valor puro, sem combinar nada
  scale: 10
}).setOptions({
  title: 'NDVI série temporal - pixel centroide do maior talhão',
  hAxis: {title: 'Data'},
  vAxis: {title: 'NDVI', minValue: 0, maxValue: 1},
  lineWidth: 2,
  pointSize: 3
});
print(chart);

// Extrai o valor do pixel em cada data -> 1 valor por data
var serie = colecaoNDVI.select('NDVI').map(function(imagem) {
  var valor = imagem.reduceRegion({
    reducer: ee.Reducer.first(),  // 1 pixel: pega o valor puro, sem combinar nada
    geometry: ponto,
    scale: 10
  });
  return ee.Feature(null, {
    'date': imagem.date().format('YYYY-MM-dd'),
    'datetime': imagem.date().format('YYYY-MM-dd HH:mm:ss'),
    'NDVI': valor.get('NDVI')
  });
});

// Remove datas nubladas (pixel mascarado -> nulo)
var serieValida = serie.filter(ee.Filter.notNull(['NDVI']));

// Exporta a série temporal (uma linha por data) como CSV
Export.table.toDrive({
  collection: serieValida,
  description: 'serie_NDVI_pixel_centroide',
  fileFormat: 'CSV',
  selectors: ['date', 'datetime', 'NDVI']
});
