// Extracao incremental das series de NDVI com e sem mascara de nuvem.
//
//   node gee/extrai_serie.js
//   node gee/extrai_serie.js --mascara sem
//   node gee/extrai_serie.js --recomeca
//   node gee/extrai_serie.js --ate 2026-06-30

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { parseArgs } from 'node:util';
import { arquivoSerie, autentica, avalia, carregaArea, cfgData, colecaoNdvi, leConfig, somaDias } from './comum.js';

const COLUNAS = ['longitude', 'latitude', 'date', 'datetime', 'img_id', 'NDVI'];

// getRegion devolve todos os pixels de todas as imagens de uma vez;
// se aparecer "too many values", diminuir
const DIAS_POR_LOTE = 60;

async function ultimaData(arquivo) {
  if (!fs.existsSync(arquivo)) return null;
  const linhas = readline.createInterface({ input: fs.createReadStream(arquivo), crlfDelay: Infinity });
  let iData = -1;
  let ultima = null;
  for await (const linha of linhas) {
    const campos = linha.split(',');
    if (iData < 0) {
      iData = campos.indexOf('date');
      continue;
    }
    if (campos[iData] && (!ultima || campos[iData] > ultima)) ultima = campos[iData];
  }
  return ultima;
}

// getRegion falha em colecao vazia (lote sem passagem)
async function extraiLote(col, area, escala) {
  if ((await avalia(col.size())) === 0) return [];
  const bruto = await avalia(col.select('NDVI').getRegion(area, escala));
  if (!bruto || bruto.length < 2) return [];

  const cab = bruto[0];
  const [iId, iLon, iLat, iT, iNdvi] = ['id', 'longitude', 'latitude', 'time', 'NDVI'].map((c) => cab.indexOf(c));

  const linhas = [];
  for (const r of bruto.slice(1)) {
    if (r[iNdvi] === null) continue;
    const ts = new Date(r[iT]).toISOString();
    linhas.push([r[iLon], r[iLat], ts.slice(0, 10), `${ts.slice(0, 10)} ${ts.slice(11, 19)}`, r[iId], r[iNdvi]]);
  }
  return linhas;
}

async function extrai(cfg, area, mascara, recomeca, fim) {
  const saida = arquivoSerie(cfg, mascara);
  const rotulo = mascara ? 'com mascara' : 'sem mascara';
  const escala = Number(cfg.escala);

  let inicio;
  let modo;
  if (recomeca || !fs.existsSync(saida)) {
    inicio = cfgData(cfg, 'data_inicio');
    modo = 'completa';
    fs.rmSync(saida, { force: true });
  } else {
    const u = await ultimaData(saida);
    inicio = u ? somaDias(u, 1) : cfgData(cfg, 'data_inicio');
    modo = 'incremental';
    console.log(`ultima data em ${path.basename(saida)}: ${u}`);
  }

  console.log(`extracao ${modo}, ${rotulo}: ${inicio} a ${fim}`);
  if (inicio > fim) {
    console.log('nada novo a extrair.');
    return;
  }

  fs.mkdirSync(path.dirname(saida), { recursive: true });
  if (!fs.existsSync(saida)) fs.writeFileSync(saida, COLUNAS.join(',') + '\n');

  let total = 0;
  let cursor = inicio;
  const limite = somaDias(fim, 1);
  while (cursor <= fim) {
    const corte = [somaDias(cursor, DIAS_POR_LOTE), limite].sort()[0];
    let linhas;
    try {
      linhas = await extraiLote(colecaoNdvi(cfg, area, cursor, corte, mascara), area, escala);
    } catch (e) {
      throw new Error(`lote ${cursor} -> ${corte}: ${e.message} (DIAS_POR_LOTE = ${DIAS_POR_LOTE})`);
    }
    if (linhas.length) fs.appendFileSync(saida, linhas.map((l) => l.join(',')).join('\n') + '\n');
    total += linhas.length;
    console.log(`  ${cursor} -> ${corte}: ${linhas.length} observacoes`);
    cursor = corte;
  }
  console.log(`total extraido: ${total} observacoes -> ${saida}\n`);
}

const { values: args } = parseArgs({
  options: {
    mascara: { type: 'string', default: 'ambas' },
    recomeca: { type: 'boolean', default: false },
    ate: { type: 'string' },
  },
});
if (!['com', 'sem', 'ambas'].includes(args.mascara)) {
  throw new Error('--mascara aceita com, sem ou ambas');
}

const cfg = leConfig();
await autentica();
const area = carregaArea(cfg);
const fim = args.ate || cfgData(cfg, 'data_fim');

const versoes = { com: [true], sem: [false], ambas: [true, false] }[args.mascara];
for (const mascara of versoes) {
  await extrai(cfg, area, mascara, args.recomeca, fim);
}
