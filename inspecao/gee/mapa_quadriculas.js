// Sobreposicao das quadriculas do Sentinel-2 sobre o municipio.
// Camada Cobertura: verde = 1 quadricula, vermelho = 2 ou mais

var ASSET = 'projects/spad05/assets/BomSucesso';
var ANO   = 2026;

var cafe = ee.FeatureCollection(ASSET);
var area = cafe.geometry().bounds();

var s2 = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
           .filterBounds(area)
           .filterDate(ANO + '-01-01', ANO + '-06-30');

var tiles = s2.aggregate_array('MGRS_TILE').distinct().sort();
print('Quadriculas que cobrem o municipio:', tiles);

// contorno de cada quadricula
var footprints = ee.FeatureCollection(tiles.map(function (t) {
  var img = s2.filter(ee.Filter.eq('MGRS_TILE', t)).first();
  return ee.Feature(ee.Image(img).geometry(), {tile: t});
}));

// quantas quadriculas cobrem cada pixel
var cobertura = ee.ImageCollection.fromImages(
  tiles.map(function (t) {
    var img = s2.filter(ee.Filter.eq('MGRS_TILE', t)).first();
    return ee.Image(1).clip(ee.Image(img).geometry()).rename('n');
  })
).sum().unmask(0).clip(area);

Map.centerObject(cafe, 10);

Map.addLayer(cobertura.updateMask(cobertura.gt(0)),
             {min: 1, max: 3, palette: ['00b050', 'ff8c00', 'ff0000']},
             'Cobertura (verde=1, laranja=2, vermelho=3+)');

Map.addLayer(footprints.style({color: 'blue', fillColor: '00000000', width: 2}),
             {}, 'Limites das quadriculas');

Map.addLayer(footprints.map(function (f) {
  return ee.Feature(f.geometry().centroid(100)).set('tile', f.get('tile'));
}), {color: 'blue'}, 'Nome das quadriculas', false);

Map.addLayer(cafe.style({color: 'black', fillColor: '00000088'}), {}, 'Talhoes de cafe');

// numero de quadriculas por talhao
var classificados = cafe.map(function (f) {
  var n = cobertura.reduceRegion({
    reducer: ee.Reducer.max(),
    geometry: f.geometry(),
    scale: 200,
    bestEffort: true
  }).get('n');
  return f.set('n_quadriculas', n);
});

var limpos = classificados.filter(ee.Filter.eq('n_quadriculas', 1));
var sobrepostos = classificados.filter(ee.Filter.gt('n_quadriculas', 1));

print('--- talhoes ---');
print('Total:', cafe.size());
print('Em uma quadricula so (usar):', limpos.size());
print('Na sobreposicao (evitar):', sobrepostos.size());

Map.addLayer(limpos.style({color: '00b050', fillColor: '00b05088'}),
             {}, 'Talhoes OK', false);
Map.addLayer(sobrepostos.style({color: 'ff0000', fillColor: 'ff000088'}),
             {}, 'Talhoes na sobreposicao', false);

// exporta os talhoes fora da sobreposicao
Export.table.toDrive({
  collection: limpos,
  description: 'talhoes_fora_da_sobreposicao',
  fileFormat: 'GeoJSON'
});
