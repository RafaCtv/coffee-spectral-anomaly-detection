// Seleciona os talhoes cafeeiros de uma propriedade registrada no CAR.
//
// Substitui o agrupamento por proximidade: em vez de inferir a fazenda pela
// distancia entre talhoes, usa o perimetro declarado do imovel rural.
//
// O SICAR tem dois downloads, com esquemas de atributos diferentes:
//   por propriedade (clicando no mapa): recibo, modfiscais, tema, area
//   base municipal:                     COD_IMOVEL, NUM_AREA, NOM_MUNICI
// FORMATO seleciona qual dos dois. No formato por propriedade, cada shapefile
// traz duas feicoes ("Area do Imovel" e "Area Liquida"), quase coincidentes.
//
// Etapa 1: ALVO = null -> ranqueia os imoveis por area de cafe
// Etapa 2: ALVO = '<codigo>' -> seleciona um imovel e exporta

var FORMATO = 'propriedade';   // 'propriedade' ou 'municipal'

// Um asset por imovel baixado; no formato municipal, um asset so.
var CAR = [
  'projects/spad05/assets/Area_do_Imovel'
];

var CAFE  = 'projects/spad05/assets/BomSucesso';
var ALVO  = 'MG-3108008-8D60BF7DCAF14B72A73918EB8892BE5A';
var RECUO = -15;    // m; buffer negativo, remove pixels de borda do talhao
var ANO   = 2026;

var CAMPO_COD = FORMATO === 'propriedade' ? 'recibo' : 'COD_IMOVEL';
var CAMPO_AREA = FORMATO === 'propriedade' ? 'area' : 'NUM_AREA';

// map do lado do cliente: CAR e um array JavaScript, nao um ee.List.
var car = ee.FeatureCollection(CAR.map(function (id) {
  return ee.FeatureCollection(id);
})).flatten();

// "Area Liquida do Imovel" repete o mesmo perimetro; fica uma feicao por imovel.
if (FORMATO === 'propriedade') {
  car = car.distinct([CAMPO_COD]);
}

var cafe = ee.FeatureCollection(CAFE);

print('Campos do CAR:', car.first());
print('Imoveis:', car.size());
print('Talhoes de cafe no municipio:', cafe.size());

if (ALVO === null) {

  var join = ee.Join.saveAll({matchesKey: 'talhoes'});
  var filtro = ee.Filter.intersects({
    leftField: '.geo', rightField: '.geo', maxError: 10
  });

  var ranking = join.apply(car, cafe, filtro).map(function (f) {
    var t = ee.FeatureCollection(ee.List(f.get('talhoes')));
    var recorte = t.map(function (g) {
      return g.setGeometry(g.geometry().intersection(f.geometry(), 1));
    });
    return f.set({
      n_talhoes: t.size(),
      cafe_ha: recorte.geometry().area(10).divide(1e4)
    }).select([CAMPO_COD, CAMPO_AREA, 'n_talhoes', 'cafe_ha']);
  }).sort('cafe_ha', false);

  print('Imoveis com cafe, do maior para o menor:', ranking);

  Map.centerObject(car, 11);
  Map.addLayer(car.style({color: 'blue', fillColor: '0000ff22', width: 2}),
               {}, 'Imoveis do CAR');
  Map.addLayer(cafe.style({color: 'black', fillColor: '00000088'}),
               {}, 'Talhoes de cafe');

  print('Copie um ' + CAMPO_COD + ' do ranking e defina ALVO.');

} else {

  var imovel = ee.Feature(car.filter(ee.Filter.eq(CAMPO_COD, ALVO)).first());

  // Recorta os talhoes pelo perimetro do imovel: um talhao que atravessa a
  // divisa entra apenas na parte que pertence a esta propriedade.
  var talhoes = cafe.filterBounds(imovel.geometry()).map(function (f) {
    var g = f.geometry().intersection(imovel.geometry(), 1);
    return f.setGeometry(g).set('ha_recorte', g.area(10).divide(1e4));
  }).filter(ee.Filter.gt('ha_recorte', 0.5));

  var comRecuo = talhoes.map(function (f) {
    return f.setGeometry(f.geometry().buffer(RECUO));
  }).filter(ee.Filter.notNull(['Area_ha']));
  var geom = comRecuo.geometry();

  print('--- imovel ' + ALVO + ' ---');
  print('Area declarada (ha):', imovel.get(CAMPO_AREA));
  print('Talhoes de cafe:', talhoes.size());
  print('Areas apos recorte (ha):', talhoes.aggregate_array('ha_recorte').sort());
  print('Area de cafe apos recorte (ha):', talhoes.geometry().area(10).divide(1e4));
  print('Area de cafe apos recuo (ha):', geom.area(10).divide(1e4));

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
  Map.addLayer(limpa.median(), {bands: ['B4','B3','B2'], min: 0, max: 3000},
               'Cor verdadeira ' + ANO, false);
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
    fileFormat: 'GeoJSON'
  });
}
