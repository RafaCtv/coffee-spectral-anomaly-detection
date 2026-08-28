// =========================================================
// Série temporal de NDVI - Sentinel-2 SR (L2A) COM máscara de nuvem
// Máscara combinada: Cloud Score+ (cs_cdf) + QA60
// Período: 2019-01-01 a 2023-01-01
// =========================================================

// Seleciona o maior polígono do shapefile (maior Area_ha = mais pixels)
var poligono = ee.Feature(BS.sort('Area_ha', false).first());
var regiao = poligono.geometry();
print('Polígono escolhido:', poligono);

// Centraliza o mapa no polígono e desenha ele
Map.centerObject(regiao, 16);
Map.addLayer(BS, {color: 'gray'}, 'Todos os polígonos');
Map.addLayer(regiao, {color: 'red'}, 'Polígono selecionado');

// Parâmetros do Cloud Score+
var csPlus = ee.ImageCollection('GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED');
var QA_BAND = 'cs_cdf';
var CLEAR_THRESHOLD = 0.6;  // probabilidade mínima de pixel limpo

// Máscara combinada: pixel precisa estar limpo no QA60 E no Cloud Score+
function maskClouds(imagem) {
  var qa = imagem.select('QA60');
  var cloudBitMask = 1 << 10;
  var cirrusBitMask = 1 << 11;
  var qaMask = qa.bitwiseAnd(cloudBitMask).eq(0)
                 .and(qa.bitwiseAnd(cirrusBitMask).eq(0));
  var csMask = imagem.select(QA_BAND).gte(CLEAR_THRESHOLD);
  return imagem.updateMask(qaMask).updateMask(csMask);
}

// Coleção Sentinel-2 SR com máscara combinada aplicada
var colecao = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
                .filterBounds(regiao)
                .filterDate('2019-01-01', '2023-01-01')
                .linkCollection(csPlus, [QA_BAND])
                .map(maskClouds);

// Calcula o NDVI = (B8 - B4) / (B8 + B4) e adiciona como banda
var calculaNDVI = function(imagem) {
  var ndvi = imagem.normalizedDifference(['B8', 'B4']).rename('NDVI');
  return imagem.addBands(ndvi);
};

var colecaoNDVI = colecao.map(calculaNDVI);
print('Número de imagens:', colecao.size());

// Gráfico da série temporal de NDVI (média do polígono por data)
var chart = ui.Chart.image.series({
  imageCollection: colecaoNDVI.select('NDVI'),
  region: regiao,
  reducer: ee.Reducer.mean(),
  scale: 10
}).setOptions({
  title: 'Série temporal NDVI (Cloud Score+ + QA60) - Sentinel-2',
  hAxis: {title: 'data'},
  vAxis: {title: 'NDVI', minValue: -1, maxValue: 1},
  lineWidth: 2,
  pointSize: 4
});
print(chart);

// Amostra TODOS os pixels do polígono em cada data, sem agregação.
// Pixels mascarados (nuvem) viram nulos e são descartados por dropNulls.
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
      'img_id': imagem.get('system:index'),
      'orbit': imagem.get('SENSING_ORBIT_NUMBER')
    });
  });
}).flatten();

// Exporta a série temporal por pixel como CSV
Export.table.toDrive({
  collection: amostras,
  description: 'serie_NDVI_com_mascara',
  fileFormat: 'CSV',
  selectors: ['longitude', 'latitude', 'date', 'datetime', 'img_id', 'orbit', 'NDVI']
});
