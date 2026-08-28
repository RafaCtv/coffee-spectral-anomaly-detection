"""Extracao incremental da serie de NDVI.

Le a ultima data presente em dados/serie_ndvi.csv e pede ao Earth Engine
apenas o que veio depois. Numa execucao diaria, quase sempre nao ha nada novo:
a revisita do Sentinel-2 e de ~5 dias e boa parte das passagens nao sobrevive a
mascara de nuvem.

    python gee/extrai_serie.py
    python gee/extrai_serie.py --recomeca
    python gee/extrai_serie.py --ate 2026-06-30
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import pathlib
import sys

from comum import RAIZ, autentica, carrega_area, cfg_data, colecao_ndvi, le_config

SAIDA = RAIZ / "dados" / "serie_ndvi.csv"
COLUNAS = ["longitude", "latitude", "date", "datetime", "img_id", "NDVI"]

# getRegion devolve todos os pixels de todas as imagens de uma vez; periodos
# longos estouram o limite do servidor. Reduzir se aparecer "too many values".
DIAS_POR_LOTE = 60


def ultima_data() -> dt.date | None:
    if not SAIDA.exists():
        return None
    ultima = None
    with SAIDA.open(newline="", encoding="utf-8") as f:
        for linha in csv.DictReader(f):
            d = dt.date.fromisoformat(linha["date"])
            if ultima is None or d > ultima:
                ultima = d
    return ultima


def extrai_lote(col, area, escala: int) -> list[list]:
    bruto = col.select("NDVI").getRegion(area, escala).getInfo()
    if not bruto or len(bruto) < 2:
        return []

    cab = bruto[0]
    i_id, i_lon = cab.index("id"), cab.index("longitude")
    i_lat, i_t = cab.index("latitude"), cab.index("time")
    i_ndvi = cab.index("NDVI")

    linhas = []
    for r in bruto[1:]:
        if r[i_ndvi] is None:  # pixel mascarado
            continue
        ts = dt.datetime.utcfromtimestamp(r[i_t] / 1000.0)
        linhas.append([
            r[i_lon], r[i_lat],
            ts.strftime("%Y-%m-%d"), ts.strftime("%Y-%m-%d %H:%M:%S"),
            r[i_id], r[i_ndvi],
        ])
    return linhas


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--recomeca", action="store_true",
                    help="ignora o CSV existente e reextrai desde data_inicio")
    ap.add_argument("--ate", help="data final (AAAA-MM-DD); padrao: config")
    args = ap.parse_args()

    cfg = le_config()
    autentica()

    area = carrega_area(cfg)
    escala = int(cfg["escala"])
    fim = dt.date.fromisoformat(args.ate) if args.ate else cfg_data(cfg, "data_fim")

    if args.recomeca or not SAIDA.exists():
        inicio = cfg_data(cfg, "data_inicio")
        modo = "completa"
        if SAIDA.exists():
            SAIDA.unlink()
    else:
        u = ultima_data()
        inicio = (u + dt.timedelta(days=1)) if u else cfg_data(cfg, "data_inicio")
        modo = "incremental"
        print(f"ultima data no CSV: {u}")

    print(f"extracao {modo}: {inicio} a {fim}")
    if inicio > fim:
        print("nada novo a extrair.")
        return 0

    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    novo = not SAIDA.exists()
    total = 0

    with SAIDA.open("a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if novo:
            w.writerow(COLUNAS)

        cursor = inicio
        while cursor <= fim:
            corte = min(cursor + dt.timedelta(days=DIAS_POR_LOTE),
                        fim + dt.timedelta(days=1))
            col = colecao_ndvi(cfg, area, cursor, corte)
            try:
                linhas = extrai_lote(col, area, escala)
            except Exception as e:  # noqa: BLE001
                print(f"  ERRO no lote {cursor} -> {corte}: {e}")
                print(f"  reduza DIAS_POR_LOTE (atual: {DIAS_POR_LOTE})")
                return 1
            w.writerows(linhas)
            total += len(linhas)
            print(f"  {cursor} -> {corte}: {len(linhas)} observacoes")
            cursor = corte

    print(f"\ntotal extraido: {total} observacoes -> {SAIDA}")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    raise SystemExit(main())
