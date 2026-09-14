import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ee from '@google/earthengine';

export { ee };

export const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// config.yml plano: "chave: valor", sem aninhamento
export function leConfig(arquivo = path.join(RAIZ, 'config.yml')) {
  const cfg = {};
  for (let linha of fs.readFileSync(arquivo, 'utf8').split(/\r?\n/)) {
    linha = linha.trim();
    if (!linha || linha.startsWith('#') || !linha.includes(':')) continue;
    const i = linha.indexOf(':');
    const valor = linha.slice(i + 1).split(/\s+#/)[0].trim().replace(/^"|"$/g, '');
    cfg[linha.slice(0, i).trim()] = valor;
  }
  return cfg;
}

export function hoje() {
  return new Date().toISOString().slice(0, 10);
}

export function cfgData(cfg, chave) {
  const v = cfg[chave];
  if (v.toLowerCase() === 'hoje') return hoje();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new Error(`config '${chave}' nao e uma data: ${v}`);
  return v;
}

export function somaDias(data, dias) {
  const d = new Date(`${data}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

// local/ por padrao; no workflow DIR_SAIDA=.
export function dirSaida() {
  return path.resolve(RAIZ, process.env.DIR_SAIDA || 'local');
}

export function arquivoSerie(cfg, mascara = true) {
  return path.join(dirSaida(), cfg[mascara ? 'serie_com_mascara' : 'serie_sem_mascara']);
}

export function avalia(objeto) {
  return new Promise((ok, falha) => {
    objeto.evaluate((valor, erro) => (erro ? falha(new Error(erro)) : ok(valor)));
  });
}

function chaveServiceAccount() {
  if (process.env.EE_SERVICE_ACCOUNT_JSON) return JSON.parse(process.env.EE_SERVICE_ACCOUNT_JSON);
  const arquivo = process.env.EE_SERVICE_ACCOUNT_FILE || path.join(RAIZ, 'local', 'service_account.json');
  if (fs.existsSync(arquivo)) return JSON.parse(fs.readFileSync(arquivo, 'utf8'));
  return null;
}

// troca o refresh_token do `earthengine authenticate` por um access token
async function tokenUsuario(cred) {
  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    body: new URLSearchParams({
      client_id: cred.client_id,
      client_secret: cred.client_secret,
      refresh_token: cred.refresh_token,
      grant_type: 'refresh_token',
    }),
  });
  const corpo = await resp.json();
  if (!resp.ok) throw new Error(`falha ao renovar token: ${corpo.error_description || corpo.error}`);
  return corpo;
}

function credencialUsuario() {
  const arquivo = path.join(os.homedir(), '.config', 'earthengine', 'credentials');
  if (!fs.existsSync(arquivo)) return null;
  const cred = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
  cred.client_id ||= process.env.EE_CLIENT_ID;
  cred.client_secret ||= process.env.EE_CLIENT_SECRET;
  return cred.client_id && cred.client_secret ? cred : null;
}

// service account (env, arquivo ou local/service_account.json) ou credencial local
export async function autentica() {
  let projeto = process.env.EE_PROJECT;
  const chave = chaveServiceAccount();

  if (chave) {
    await new Promise((ok, falha) => ee.data.authenticateViaPrivateKey(chave, ok, falha));
    projeto ||= chave.project_id;
    console.log(`EE: service account ${chave.client_email}`);
  } else {
    const cred = credencialUsuario();
    if (!cred) {
      throw new Error('sem credencial: defina EE_SERVICE_ACCOUNT_FILE ou salve a chave em local/service_account.json');
    }
    const t = await tokenUsuario(cred);
    ee.data.setAuthTokenRefresher((args, callback) => {
      tokenUsuario(cred).then(callback, (e) => callback({ error: e.message }));
    });
    await new Promise((ok) => ee.data.setAuthToken(cred.client_id, 'Bearer', t.access_token, t.expires_in, [], ok, false));
    console.log('EE: credencial local');
  }

  await new Promise((ok, falha) => ee.initialize(null, null, ok, falha, null, projeto));
}

// GeoJSON da area: FeatureCollection de talhoes, Feature ou Geometry
export function carregaArea(cfg) {
  const arquivo = path.join(RAIZ, cfg.area_geojson);
  if (!fs.existsSync(arquivo)) throw new Error(`area nao encontrada: ${arquivo}`);
  const gj = JSON.parse(fs.readFileSync(arquivo, 'utf8'));

  if (gj.type === 'FeatureCollection') {
    if (!gj.features.length) throw new Error(`GeoJSON sem feicoes: ${arquivo}`);
    return ee.FeatureCollection(gj.features.map((f) => ee.Feature(ee.Geometry(f.geometry)))).geometry();
  }
  if (gj.type === 'Feature') return ee.Geometry(gj.geometry);
  return ee.Geometry(gj);
}

// Sentinel-2 L2A com banda NDVI; com mascara, so pixels com cs_cdf >= limiar
export function colecaoNdvi(cfg, area, inicio, fim, mascara = true) {
  let col = ee.ImageCollection(cfg.colecao).filterBounds(area).filterDate(inicio, fim);
  if (mascara) {
    const qa = cfg.banda_qa;
    const limiar = Number(cfg.limiar_nuvem);
    col = col
      .linkCollection(ee.ImageCollection(cfg.colecao_nuvem), [qa])
      .map((img) => img.updateMask(img.select(qa).gte(limiar)));
  }
  return col.map((img) => img.addBands(img.normalizedDifference([cfg.banda_nir, cfg.banda_vermelho]).rename('NDVI')));
}
