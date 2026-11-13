// Passo 5: para cada quebra aceita, baixa o NDVI dos seis talhoes na ultima imagem limpa
// antes e na primeira imagem limpa depois da quebra (ate 90 dias)
// Rodar dentro desta pasta: node 5_extrai_imagens_quebras.mjs
// Chave do Earth Engine: variavel EE_SERVICE_ACCOUNT_FILE ou ../local/service_account.json
// Saida: dados/ndvi_quebras.csv

import fs from 'node:fs';
import ee from '@google/earthengine';

const LIMIAR_NUVEM = 0.6;    // Cloud Score+ (cs_cdf): 1 = limpo
const FRACAO_LIMPA = 0.95;   // fracao minima de pixels limpos nos talhoes
const JANELA_DIAS = 90;
const CRS = 'EPSG:32723';

function somaDias(data, dias) {
  const d = new Date(`${data}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

function avalia(objeto) {
  return new Promise((ok, falha) => objeto.evaluate((v, erro) => (erro ? falha(new Error(erro)) : ok(v))));
}

// quebras aceitas
const linhasCsv = fs.readFileSync('resultados/eventos_buffer.csv', 'utf8').trim().split(/\r?\n/);
const cab = linhasCsv[0].split(',').map((c) => c.replace(/"/g, ''));
const quebras = linhasCsv.slice(1)
  .map((l) => Object.fromEntries(l.split(',').map((v, i) => [cab[i], v.replace(/"/g, '')])))
  .filter((q) => q.aceito === 'TRUE');

// autenticacao
const chave = JSON.parse(fs.readFileSync(process.env.EE_SERVICE_ACCOUNT_FILE || '../local/service_account.json', 'utf8'));
await new Promise((ok, falha) => ee.data.authenticateViaPrivateKey(chave, ok, falha));
await new Promise((ok, falha) => ee.initialize(null, null, ok, falha, null, chave.project_id));

// talhoes e areas amostrais
const talhoes = JSON.parse(fs.readFileSync('../area/fazenda_car.geojson', 'utf8'));
const area = ee.FeatureCollection(talhoes.features.map((f) => ee.Feature(ee.Geometry(f.geometry)))).geometry();
const buffers = JSON.parse(fs.readFileSync('../area/buffers_amostrais.geojson', 'utf8')).features;
const geometriaBuffer = (id) => ee.Geometry(buffers.find((f) => String(f.properties.id) === String(id)).geometry);

// NDVI mascarado e fracao de pixels limpos nos talhoes e na area amostral
function imagens(inicio, fim, buffer) {
  return ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
    .filterBounds(area)
    .filterDate(inicio, fim)
    .linkCollection(ee.ImageCollection('GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED'), ['cs_cdf'])
    .map((img) => {
      const limpo = img.select('cs_cdf').gte(LIMIAR_NUVEM).unmask(0);
      const fracao = (geom) => limpo.reduceRegion({ reducer: ee.Reducer.mean(), geometry: geom, scale: 10, crs: CRS }).get('cs_cdf');
      return img.normalizedDifference(['B8', 'B4']).rename('NDVI')
        .updateMask(limpo)
        .set('system:time_start', img.get('system:time_start'))
        .set('dia', img.date().format('YYYY-MM-dd'))
        .set('fracao_limpa', fracao(area))
        .set('fracao_buffer', fracao(buffer));
    });
}

// imagens da janela com 95% dos talhoes e toda a area amostral limpos: [dia, id]
async function candidatas(inicio, fim, buffer) {
  const col = imagens(inicio, fim, buffer)
    .filter(ee.Filter.gte('fracao_limpa', FRACAO_LIMPA))
    .filter(ee.Filter.eq('fracao_buffer', 1));
  const lista = await avalia(col.reduceColumns(ee.Reducer.toList(2), ['dia', 'system:index']).get('list'));
  return lista.sort((a, b) => (a[0] < b[0] ? -1 : 1));
}

// NDVI de todos os pixels dos talhoes numa imagem
async function ndviDaImagem(inicio, fim, buffer, id) {
  const img = imagens(inicio, fim, buffer).filter(ee.Filter.eq('system:index', id)).first();
  const tabela = await avalia(ee.ImageCollection([img]).getRegion(area, 10, CRS));
  const c = tabela[0];
  return tabela.slice(1).map((r) => [r[c.indexOf('longitude')], r[c.indexOf('latitude')], r[c.indexOf('NDVI')]]);
}

fs.writeFileSync('dados/ndvi_quebras.csv', 'buffer,evento,momento,date,longitude,latitude,NDVI\n');

for (const q of quebras) {
  const buffer = geometriaBuffer(q.buffer);
  // antes: ate o dia da quebra mais antiga do grupo; depois: a partir do dia seguinte a mais recente
  const janelaAntes = [somaDias(q.primeira, -JANELA_DIAS), somaDias(q.primeira, 1)];
  const janelaDepois = [somaDias(q.ultima, 1), somaDias(q.ultima, JANELA_DIAS + 1)];
  const antes = (await candidatas(...janelaAntes, buffer)).at(-1);
  const depois = (await candidatas(...janelaDepois, buffer))[0];

  console.log(`area ${q.buffer} quebra ${q.data}: antes ${antes ? antes[0] : '-'} | depois ${depois ? depois[0] : '-'}`);
  if (!antes || !depois) continue;

  const linhas = [];
  for (const [momento, escolha, janela] of [['antes', antes, janelaAntes], ['depois', depois, janelaDepois]]) {
    for (const [lon, lat, ndvi] of await ndviDaImagem(...janela, buffer, escolha[1])) {
      linhas.push([q.buffer, q.data, momento, escolha[0], lon, lat, ndvi === null ? '' : ndvi].join(','));
    }
  }
  fs.appendFileSync('dados/ndvi_quebras.csv', linhas.join('\n') + '\n');
}
