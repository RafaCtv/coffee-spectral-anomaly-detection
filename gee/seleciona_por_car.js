// Seleciona os talhoes cafeeiros de uma propriedade registrada no CAR.
//
// Substitui o agrupamento por proximidade: em vez de inferir a fazenda pela
// distancia entre talhoes, usa o perimetro declarado do imovel rural.
//
// Etapa 1: ALVO = null           -> ranqueia os imoveis por area de cafe
// Etapa 2: ALVO = 'MG-3108008-…' -> seleciona um imovel e exporta

var CAR   = 'projects/spad05/assets/CAR_BomSucesso';
var CAFE  = 'projects/spad05/assets/BomSucesso';
var ALVO  = null;
var RECUO = -15;    // m; buffer negativo, remove pixels de borda do talhao
var ANO   = 2026;

var car  = ee.FeatureCollection(CAR);
var cafe = ee.FeatureCollection(CAFE);

// Os nomes dos campos variam conforme a versao do download do CAR.
// Confira aqui e ajuste CAMPO_COD se necessario.
print('Campos do CAR:', car.first());
var CAMPO_COD = 'COD_IMOVEL';

print('Imoveis no CAR:', car.size());
print('Talhoes de cafe:', cafe.size());

if (ALVO === null) {

  // Casa cada imovel com os talhoes que o interceptam.
  var join = ee.Join.saveAll({matchesKey: 'talhoes'});
  var filtro = ee.Filter.intersects({
    leftField: '.geo', rightField: '.geo', maxError: 10
  });

  var comCafe = join.apply(car, cafe, filtro);

  var ranking = comCafe.map(function (f) {
    var t = ee.FeatureCollection(ee.List(f.get('talhoes')));
    return f.set({
      n_talhoes: t.size(),
      cafe_ha: t.aggregate_sum('Area_ha')
    }).select([CAMPO_COD, 'NUM_AREA', 'n_talhoes', 'cafe_ha']);
  }).sort('cafe_ha', false);

  print('Imoveis com cafe, do maior para o menor:', ranking.limit(25));

  Map.centerObject(cafe, 11);
  Map.addLayer(car.style({color: 'blue', fillColor: '00000000', width: 1}),
               {}, 'Imoveis do CAR');
  Map.addLayer(cafe.style({color: 'black', fillColor: '00000088'}),
               {}, 'Talhoes de cafe');
  Map.addLayer(ranking.limit(10).style({color: 'orange', fillColor: 'ff8c0044'}),
               {}, '10 imoveis com mais cafe');

  print('Copie um ' + CAMPO_COD + ' do ranking e defina ALVO.');

} else {

  var imovel = ee.Feature(car.filter(ee.Filter.eq(CAMPO_COD, ALVO)).first());

  // Recorta os talhoes pelo perimetro do imovel: um talhao que atravessa a
  // divisa entra apenas na parte que pertence a esta propriedade.
  var talhoes = cafe.filterBounds(imovel.geometry()).map(function (f) {
    return f.setGeometry(f.geometry().intersection(imovel.geometry(), 1));
  }).filter(ee.Filter.gt('Area_ha', 0.5));

  var comRecuo = talhoes.map(function (f) {
    return f.setGeometry(f.geometry().buffer(RECUO));
  });
  var geom = comRecuo.geometry();

  print('--- imovel ' + ALVO + ' ---');
  print('Area total do imovel (ha):', imovel.get('NUM_AREA'));
  print('Talhoes de cafe:', talhoes.size());
  print('Area de cafe apos recorte e recuo (ha):', geom.area(10).divide(1e4));

  Map.centerObject(imovel, 14);
  Map.addLayer(imovel.geometry(), {color: 'blue'}, 'Perimetro do imovel');
  Map.addLayer(talhoes.style({color: 'red', fillColor: '00000000', width: 2}),
               {}, 'Talhoes de cafe');
  Map.addLayer(comRecuo.style({color: 'yellow', fillColor: 'ffff0044'}),
               {}, 'Com recuo');

  // Mais de uma quadricula = area na faixa de sobreposicao.
  var s2 = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
             .filterBounds(geom)
             .filterDate(ANO + '-01-01', ANO + '-12-31');
  print('Quadriculas MGRS:', s2.aggregate_array('MGRS_TILE').distinct());
  print('Orbitas:', s2.aggregate_array('SENSING_ORBIT_NUMBER').distinct());

  var cs = ee.ImageCollection('GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED');
  var limpa = s2.linkCollection(cs, ['cs_cdf'])
                .map(function (img) {
                  return img.updateMask(img.select('cs_cdf').gte(0.6));
                });
  Map.addLayer(limpa.median(), {bands: ['B8','B4','B3'], min: 0, max: 5000},
               'Falsa cor ' + ANO, false);

  var ndvi = limpa.map(function (img) {
    return img.normalizedDifference(['B8','B4']).rename('NDVI');
  });
  print('Observacoes validas por pixel em ' + ANO + ':', ndvi.count().reduceRegion({
    reducer: ee.Reducer.minMax().combine(ee.Reducer.mean(), '', true),
    geometry: geom, scale: 10, maxPixels: 1e9
  }));

  Export.table.toDrive({
    collection: comRecuo,
    description: 'fazenda_geojson',
    fileFormat: 'GeoJSON',
    selectors: ['Area_ha', 'CD_MUN', 'NM_MUN', 'Name']
  });
}
