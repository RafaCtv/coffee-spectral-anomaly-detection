// Passo 7: baixa do Earth Engine as bandas usadas no NDVI, EVI e NDMI dos pixels das 18 areas amostrais
// Mesmo periodo, grade e mascara de nuvens do passo 1
// Rodar dentro desta pasta: node 7_extrai_bandas.mjs
// Chave do Earth Engine: variavel EE_SERVICE_ACCOUNT_FILE ou ../local/service_account.json
// Saida: dados/bandas_gee.csv

import fs from 'node:fs';
import ee from '@google/earthengine';

const INICIO = '2019-09-01';
const FIM = '2026-08-31';
const LIMIAR_NUVEM = 0.6;   // Cloud Score+ (cs_cdf): 1 = limpo
const CRS = 'EPSG:32723';   // UTM 23S, grade de 10 m do Sentinel-2
const BANDAS = ['B2', 'B4', 'B8', 'B11'];
const SAIDA = 'dados/bandas_gee.csv';

function somaDias(data, dias) {
  const d = new Date(`${data}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

function avalia(objeto) {
  return new Promise((ok, falha) => objeto.evaluate((v, erro) => (erro ? falha(new Error(erro)) : ok(v))));
}

// autenticacao
const chave = JSON.parse(fs.readFileSync(process.env.EE_SERVICE_ACCOUNT_FILE || '../local/service_account.json', 'utf8'));
await new Promise((ok, falha) => ee.data.authenticateViaPrivateKey(chave, ok, falha));
await new Promise((ok, falha) => ee.initialize(null, null, ok, falha, null, chave.project_id));

// area: uniao das areas amostrais
const buffers = JSON.parse(fs.readFileSync('../area/buffers_amostrais.geojson', 'utf8'));
const area = ee.FeatureCollection(buffers.features.map((f) => ee.Feature(ee.Geometry(f.geometry)))).geometry();

// bandas com os pixels de nuvem mascarados
function bandasSemNuvem(inicio, fim) {
  return ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
    .filterBounds(area)
    .filterDate(inicio, fim)
    .linkCollection(ee.ImageCollection('GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED'), ['cs_cdf'])
    .map((img) => img.select(BANDAS)
      .updateMask(img.select('cs_cdf').gte(LIMIAR_NUVEM))
      .set('system:time_start', img.get('system:time_start')));
}

fs.mkdirSync('dados', { recursive: true });
fs.writeFileSync(SAIDA, `longitude,latitude,date,datetime,img_id,${BANDAS.join(',')}\n`);

// baixa de 60 em 60 dias (limite de tamanho do pedido no GEE)
let inicio = INICIO;
while (inicio <= FIM) {
  let fim = somaDias(inicio, 60);
  if (fim > somaDias(FIM, 1)) fim = somaDias(FIM, 1);

  const tabela = await avalia(bandasSemNuvem(inicio, fim).getRegion(area, 10, CRS));
  const cab = tabela[0];
  const linhas = [];
  for (const r of tabela.slice(1)) {
    const valores = BANDAS.map((b) => r[cab.indexOf(b)]);
    if (valores.some((v) => v === null)) continue;   // pixel com nuvem
    const dataHora = new Date(r[cab.indexOf('time')]).toISOString();
    const dia = dataHora.slice(0, 10);
    linhas.push([r[cab.indexOf('longitude')], r[cab.indexOf('latitude')], dia,
      `${dia} ${dataHora.slice(11, 19)}`, r[cab.indexOf('id')], ...valores].join(','));
  }
  if (linhas.length > 0) fs.appendFileSync(SAIDA, linhas.join('\n') + '\n');
  console.log(`${inicio} a ${fim}: ${linhas.length} linhas`);
  inicio = fim;
}
