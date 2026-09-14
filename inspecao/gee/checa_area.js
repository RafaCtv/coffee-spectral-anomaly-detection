// Diagnostico de uma area candidata: quadriculas, orbitas e observacoes validas.
//
//   node inspecao/gee/checa_area.js
//   node inspecao/gee/checa_area.js --area area/candidata_02.geojson

import { parseArgs } from 'node:util';
import { autentica, avalia, carregaArea, cfgData, colecaoNdvi, ee, leConfig } from '../../gee/comum.js';

const { values: args } = parseArgs({ options: { area: { type: 'string' } } });

const cfg = leConfig();
if (args.area) cfg.area_geojson = args.area;
await autentica();

const area = carregaArea(cfg);
const inicio = cfgData(cfg, 'data_inicio');
const fim = cfgData(cfg, 'data_fim');

console.log(`\narea    : ${cfg.area_geojson}`);
const ha = (await avalia(area.area({ maxError: 1 }))) / 10000;
console.log(`tamanho : ${ha.toFixed(1)} ha  (~${Math.round(ha * 100)} pixels de 10 m)`);

const base = ee.ImageCollection(cfg.colecao).filterBounds(area).filterDate(inicio, fim);
const n = await avalia(base.size());
console.log(`periodo : ${inicio} a ${fim}  ->  ${n} imagens brutas`);
if (n === 0) {
  console.log('\nNenhuma imagem. Verifique o poligono e as datas.');
  process.exit(1);
}

const tiles = [...new Set(await avalia(base.aggregate_array('MGRS_TILE')))].sort();
const orbitas = [...new Set(await avalia(base.aggregate_array('SENSING_ORBIT_NUMBER')))].sort((a, b) => a - b);

console.log('\n--- cobertura ---');
console.log(`quadriculas MGRS : ${tiles.join(', ')}`);
console.log(`orbitas          : ${orbitas.join(', ')}`);
if (tiles.length > 1) console.log(`\n  ${tiles.length} quadriculas: area na faixa de sobreposicao`);
if (orbitas.length > 1) console.log(`\n  ${orbitas.length} orbitas: geometria de visada variavel`);

const porAno = {};
for (const t of await avalia(base.aggregate_array('system:time_start'))) {
  const ano = new Date(t).getUTCFullYear();
  porAno[ano] = (porAno[ano] || 0) + 1;
}

const contagem = colecaoNdvi(cfg, area, inicio, fim).select('NDVI').reduce(ee.Reducer.count());
const stats = await avalia(contagem.reduceRegion({
  reducer: ee.Reducer.mean().combine({ reducer2: ee.Reducer.minMax(), sharedInputs: true }),
  geometry: area,
  scale: Number(cfg.escala),
  maxPixels: 1e9,
}));

console.log('\n--- densidade temporal ---');
console.log('imagens brutas por ano:');
for (const ano of Object.keys(porAno).sort()) console.log(`  ${ano}: ${String(porAno[ano]).padStart(4)}`);

const media = stats.NDVI_count_mean;
if (media != null) {
  const anos = (new Date(fim) - new Date(inicio)) / (365.25 * 86400000);
  console.log(`\nobservacoes validas por pixel (limiar ${cfg.limiar_nuvem}):`);
  console.log(`  media : ${media.toFixed(0)}   (${(media / anos).toFixed(0)} por ano)`);
  console.log(`  min   : ${stats.NDVI_count_min}`);
  console.log(`  max   : ${stats.NDVI_count_max}`);
  console.log(`  aproveitamento: ${((100 * media) / n).toFixed(0)}% das passagens`);
}

console.log('\n--- criterios ---');
console.log(`  quadricula unica            : ${tiles.length === 1 ? 'sim' : 'nao'}`);
console.log(`  >= 60 observacoes por pixel : ${(media || 0) >= 60 ? 'sim' : 'nao'}`);
console.log('  confirmar visualmente com inspecao/gee/inspeciona_area.js\n');
