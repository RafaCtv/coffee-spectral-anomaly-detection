// Agrupa talhoes proximos em blocos (candidatos a fazenda) e exporta um bloco.
// PONTO = null desenha os blocos; depois marcar um ponto no bloco, nomear
// como "ponto" e usar PONTO = ponto

// DIST e RECUO em metros, AREA_MIN em hectares
var ASSET    = 'projects/spad05/assets/BomSucesso';
var DIST     = 250;
var AREA_MIN = 1.0;
var RECUO    = -15;
var ANO      = 2026;
var PONTO    = null;

var todos = ee.FeatureCollection(ASSET).filter(ee.Filter.gte('Area_ha', AREA_MIN));
print('Talhoes (apos filtro de area):', todos.size());

// infla, une o que se toca e separa os componentes
var partes = todos.geometry().buffer(DIST).dissolve(10).geometries();
print('Blocos encontrados:', partes.size());

var blocos = ee.FeatureCollection(
  ee.List.sequence(0, partes.size().subtract(1)).map(function (i) {
    i = ee.Number(i);
    var g = ee.Geometry(partes.get(i));
    return ee.Feature(g, {bloco: i, extensao_ha: g.area(10).divide(1e4)});
  })
);

if (PONTO === null) {

  print('Blocos ordenados por extensao:', blocos.sort('extensao_ha', false).limit(25));

  Map.centerObject(todos, 11);
  Map.addLayer(blocos.style({color: 'blue', fillColor: '0000ff22', width: 1}),
               {}, 'Blocos');
  Map.addLayer(todos.style({color: 'black', fillColor: '00000066'}),
               {}, 'Talhoes');

  print('Marque um ponto sobre o bloco desejado, nomeie a variavel como "ponto"');
  print('e troque PONTO = null por PONTO = ponto.');

} else {

  var escolhido = ee.Feature(blocos.filterBounds(PONTO).first());
  var talhoes = todos.filterBounds(escolhido.geometry());

  print('--- bloco selecionado ---');
  print('Indice do bloco:', escolhido.get('bloco'));
  print('Talhoes:', talhoes.size());
  print('Area de cafe (ha):', talhoes.aggregate_sum('Area_ha'));
  print('Areas individuais (ha):', talhoes.aggregate_array('Area_ha').sort());

  // recuo tira os pixels mistos da borda
  var comRecuo = talhoes.map(function (f) {
    return f.setGeometry(f.geometry().buffer(RECUO));
  }).filter(ee.Filter.notNull(['Area_ha']));
  var geom = comRecuo.geometry();
  print('Area apos recuo de ' + RECUO + ' m (ha):', geom.area(10).divide(1e4));

  Map.centerObject(talhoes, 14);
  Map.addLayer(escolhido.geometry(), {color: 'blue'}, 'Bloco');
  Map.addLayer(talhoes.style({color: 'red', fillColor: '00000000', width: 2}),
               {}, 'Talhoes do bloco');
  Map.addLayer(comRecuo.style({color: 'yellow', fillColor: 'ffff0044'}),
               {}, 'Com recuo');

  // mais de uma quadricula = faixa de sobreposicao
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

  print(ui.Chart.image.series({
    imageCollection: ndvi, region: geom, reducer: ee.Reducer.mean(), scale: 10
  }).setOptions({title: 'NDVI medio do bloco (' + ANO + ')',
                 lineWidth: 2, pointSize: 3}));

  Export.table.toDrive({
    collection: comRecuo,
    description: 'fazenda_geojson',
    fileFormat: 'GeoJSON'
  });
}
