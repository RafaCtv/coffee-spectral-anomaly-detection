// Seleciona o maior polígono do shapefile (maior Area_ha = mais pixels)
var poligono = ee.Feature(BS.sort('Area_ha', false).first());
var regiao = poligono.geometry();
print('Polígono escolhido:', poligono);

// Centraliza o mapa no polígono escolhido e desenha ele
Map.centerObject(regiao, 16);
Map.addLayer(BS, {color: 'gray'}, 'Todos os polígonos');
Map.addLayer(regiao, {color: 'red'}, 'Polígono selecionado');

// Coleção Sentinel-2 sem nenhum pré-processamento, apenas filtrada por data e área
var colecao = ee.ImageCollection('COPERNICUS/S2_HARMONIZED')
                .filterBounds(regiao)
                .filterDate('2017-01-01', '2019-01-01');

// Calcula o NDVI = (B8 - B4) / (B8 + B4) e adiciona como banda
var calculaNDVI = function(imagem) {
  var ndvi = imagem.normalizedDifference(['B8', 'B4']).rename('NDVI');
  return imagem.addBands(ndvi);
};

var colecaoNDVI = colecao.map(calculaNDVI);

// Gráfico da série temporal de NDVI (reducer padrão = ee.Reducer.mean)
var chart = ui.Chart.image.series({
  imageCollection: colecaoNDVI.select('NDVI'),
  region: regiao,
  reducer: ee.Reducer.mean(),
  scale: 10 // Sentinel-2: resolução 10m para B4 e B8
}).setOptions({
  title: 'Série temporal NDVI - Sentinel-2',
  hAxis: {title: 'data'},
  vAxis: {title: 'NDVI', minValue: -1, maxValue: 1},
  lineWidth: 2,
  pointSize: 4
});

print(chart);
print(colecao.size());

// Amostra TODOS os pixels do polígono em cada data, sem agregação.
// longitude/latitude identificam cada pixel ao longo do tempo.
var amostras = colecaoNDVI.select('NDVI').map(function(imagem) {
  var comCoord = imagem.addBands(ee.Image.pixelLonLat());
  return comCoord.sample({
    region: regiao,
    scale: 10,
    projection: 'EPSG:4326',
    dropNulls: true,
    geometries: false
  }).map(function(f) {
    return f.set({
      'date': imagem.date().format('YYYY-MM-dd'),
      'datetime': imagem.date().format('YYYY-MM-dd HH:mm:ss'),
      'img_id': imagem.get('system:index'),  // granule de origem
      'orbit': imagem.get('SENSING_ORBIT_NUMBER')
    });
  });
}).flatten();

// Exporta a série temporal por pixel como CSV para o Google Drive
Export.table.toDrive({
  collection: amostras,
  description: 'serie_NDVI_BomSucesso_porpixel',
  fileFormat: 'CSV',
  selectors: ['longitude', 'latitude', 'date', 'datetime', 'img_id', 'orbit', 'NDVI']
});