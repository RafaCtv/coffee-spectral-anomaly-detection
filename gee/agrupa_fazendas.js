// Agrupa os talhoes do mapeamento municipal em blocos por proximidade e exporta
// os talhoes de um bloco como GeoJSON.
//
// Talhoes da mesma fazenda ficam proximos entre si. Inflando cada poligono em
// DIST metros e unindo os que se tocam, cada bloco resultante e um candidato a
// fazenda. Os poligonos originais sao recuperados depois, sem redesenhar nada.
//
// Etapa 1: BLOCO = null   -> lista e ranqueia os blocos
// Etapa 2: BLOCO = <n>    -> seleciona um bloco e exporta

var ASSET    = 'projects/spad05/assets/BomSucesso';
var DIST     = 250;    // m; distancia maxima entre talhoes da mesma fazenda
var AREA_MIN = 1.0;    // ha; descarta fragmentos
var RECUO    = -15;    // m; buffer negativo, remove pixels de borda do talhao
var BLOCO    = null;   // indice do bloco escolhido na etapa 1

var todos = ee.FeatureCollection(ASSET).filter(ee.Filter.gte('Area_ha', AREA_MIN));
print('Talhoes (apos filtro de area):', todos.size());

// Infla, une o que se toca e separa os componentes resultantes.
var partes = todos.geometry().buffer(DIST).dissolve(10).geometries();
print('Blocos encontrados:', partes.size());

var blocos = ee.FeatureCollection(
  ee.List.sequence(0, partes.size().subtract(1)).map(function (i) {
    i = ee.Number(i);
    var g = ee.Geometry(partes.get(i));
    return ee.Feature(g, {bloco: i, extensao_ha: g.area(10).divide(1e4)});
  })
);

if (BLOCO === null) {

  var ranking = blocos.sort('extensao_ha', false);
  print('Blocos ordenados por extensao:', ranking.limit(25));

  Map.centerObject(todos, 11);
  Map.addLayer(blocos.style({color: 'blue', fillColor: '0000ff22', width: 1}),
               {}, 'Blocos');
  Map.addLayer(todos.style({color: 'black', fillColor: '00000066'}),
               {}, 'Talhoes');

  // Rotulos com o indice de cada bloco, para escolher no mapa.
  Map.addLayer(blocos.map(function (f) {
    return ee.Feature(f.geometry().centroid(10)).set('bloco', f.get('bloco'));
  }), {color: 'red'}, 'Centroides dos blocos');

  print('Escolha um bloco pelo indice e defina BLOCO = <indice>.');
  print('Use o Inspector para clicar num bloco e ver seu indice.');

} else {

  var escolhido = ee.Feature(blocos.filter(ee.Filter.eq('bloco', BLOCO)).first());
  var talhoes = todos.filterBounds(escolhido.geometry());

  print('--- bloco ' + BLOCO + ' ---');
  print('Talhoes:', talhoes.size());
  print('Area de cafe (ha):', talhoes.aggregate_sum('Area_ha'));
  print('Areas individuais (ha):', talhoes.aggregate_array('Area_ha').sort());

  // Pixel de 10 m sobre a divisa e misto (parte cafe, parte carreador).
  var comRecuo = talhoes.map(function (f) {
    return f.setGeometry(f.geometry().buffer(RECUO));
  });
  var geom = comRecuo.geometry();
  print('Area apos recuo de ' + RECUO + ' m (ha):', geom.area(10).divide(1e4));

  Map.centerObject(talhoes, 14);
  Map.addLayer(escolhido.geometry(), {color: 'blue'}, 'Bloco');
  Map.addLayer(talhoes.style({color: 'red', fillColor: '00000000', width: 2}),
               {}, 'Talhoes do bloco');
  Map.addLayer(comRecuo.style({color: 'yellow', fillColor: 'ffff0044'}),
               {}, 'Com recuo');

  // Mais de uma quadricula = area na faixa de sobreposicao.
  var s2 = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
             .filterBounds(geom)
             .filterDate('2026-01-01', '2026-12-31');
  print('Quadriculas MGRS:', s2.aggregate_array('MGRS_TILE').distinct());
  print('Orbitas:', s2.aggregate_array('SENSING_ORBIT_NUMBER').distinct());

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

  Export.table.toDrive({
    collection: comRecuo,
    description: 'fazenda_geojson',
    fileFormat: 'GeoJSON',
    selectors: ['Area_ha', 'CD_MUN', 'NM_MUN', 'Name']
  });
}
