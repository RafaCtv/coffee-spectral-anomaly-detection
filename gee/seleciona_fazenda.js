// Seleciona os talhoes de uma fazenda a partir do mapeamento municipal e
// exporta como GeoJSON para area/fazenda.geojson.
//
// 1. Rode com RECORTE = null para ver todos os talhoes do municipio.
// 2. Desenhe um retangulo em volta da fazenda escolhida (ferramenta de
//    geometria) e nomeie a variavel como "recorte".
// 3. Rode de novo. Confira o console e a tabela de tiles.
// 4. Dispare a task de export e baixe o GeoJSON.

var ASSET   = 'projects/spad05/assets/BomSucesso';
var RECORTE = null;          // trocar por: recorte
var AREA_MIN = 1.0;          // ha; descarta fragmentos pequenos demais
var RECUO    = -15;          // m; buffer negativo para dropar pixels de borda

var todos = ee.FeatureCollection(ASSET);
print('Talhoes no municipio:', todos.size());
print('Area total (ha):', todos.aggregate_sum('Area_ha'));
print('Maior talhao (ha):', todos.aggregate_max('Area_ha'));

Map.addLayer(todos.style({color: 'black', fillColor: '00000044'}), {}, 'Todos os talhoes');

if (RECORTE === null) {
  Map.centerObject(todos, 11);
  print('Desenhe um retangulo em volta da fazenda e nomeie como "recorte".');
} else {

  // --- selecao ---------------------------------------------------
  var sel = todos.filterBounds(RECORTE).filter(ee.Filter.gte('Area_ha', AREA_MIN));

  print('--- selecao ---');
  print('Talhoes selecionados:', sel.size());
  print('Area selecionada (ha):', sel.aggregate_sum('Area_ha'));
  print('Areas individuais (ha):', sel.aggregate_array('Area_ha').sort());

  // Buffer negativo remove a primeira fileira de pixels, que sao mistos
  // (parte cafe, parte carreador ou mata).
  var comRecuo = sel.map(function (f) {
    return f.setGeometry(f.geometry().buffer(RECUO));
  }).filter(ee.Filter.notNull(['Area_ha']));

  var geom = comRecuo.geometry();
  print('Area apos recuo de ' + RECUO + ' m (ha):', geom.area(1).divide(1e4));

  Map.centerObject(sel, 14);
  Map.addLayer(sel.style({color: 'red', fillColor: '00000000', width: 2}), {}, 'Selecionados');
  Map.addLayer(comRecuo.style({color: 'yellow', fillColor: 'ffff0044'}), {}, 'Com recuo');

  // --- quadriculas que cobrem a selecao --------------------------
  var s2 = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
             .filterBounds(geom)
             .filterDate('2026-01-01', '2026-12-31');

  var tiles = s2.aggregate_array('MGRS_TILE').distinct();
  print('--- cobertura ---');
  print('Quadriculas MGRS:', tiles);
  print('Orbitas:', s2.aggregate_array('SENSING_ORBIT_NUMBER').distinct());
  print('Mais de uma quadricula = area na faixa de sobreposicao.');

  var contornos = ee.FeatureCollection(tiles.map(function (t) {
    var img = s2.filter(ee.Filter.eq('MGRS_TILE', t)).first();
    return ee.Feature(ee.Image(img).geometry(), {tile: t});
  }));
  Map.addLayer(contornos.style({color: 'cyan', fillColor: '00000000', width: 2}),
               {}, 'Limites das quadriculas');

  // --- contexto visual -------------------------------------------
  var cs = ee.ImageCollection('GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED');
  var limpa = s2.linkCollection(cs, ['cs_cdf'])
                .map(function (img) {
                  return img.updateMask(img.select('cs_cdf').gte(0.6));
                });

  Map.addLayer(limpa.median(), {bands: ['B4','B3','B2'], min: 0, max: 3000},
               'Cor verdadeira 2026', false);
  Map.addLayer(limpa.median(), {bands: ['B8','B4','B3'], min: 0, max: 5000},
               'Falsa cor 2026', false);

  var ndvi = limpa.map(function (img) {
    return img.normalizedDifference(['B8','B4']).rename('NDVI');
  });
  print('Observacoes validas por pixel em 2026:', ndvi.count().reduceRegion({
    reducer: ee.Reducer.minMax().combine(ee.Reducer.mean(), '', true),
    geometry: geom, scale: 10, maxPixels: 1e9
  }));

  print(ui.Chart.image.series({
    imageCollection: ndvi, region: geom, reducer: ee.Reducer.mean(), scale: 10
  }).setOptions({title: 'NDVI medio da selecao (2026)', lineWidth: 2, pointSize: 3}));

  // --- export ----------------------------------------------------
  Export.table.toDrive({
    collection: comRecuo,
    description: 'fazenda_geojson',
    fileFormat: 'GeoJSON'
  });
}
