"""Diagnostico de uma area candidata antes de fixar a area de estudo.

Reporta quantas quadriculas MGRS cobrem a area (mais de uma = faixa de
sobreposicao, gera observacoes redundantes por passagem), quantas orbitas, a
densidade de imagens por ano e quantas observacoes sobrevivem a mascara de nuvem.

    python gee/checa_area.py
    python gee/checa_area.py --area area/candidata_02.geojson
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import pathlib
import sys

from comum import autentica, carrega_area, cfg_data, colecao_ndvi, le_config


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--area", help="GeoJSON alternativo, para comparar candidatas")
    args = ap.parse_args()

    import ee

    cfg = le_config()
    if args.area:
        cfg["area_geojson"] = args.area
    autentica()

    area = carrega_area(cfg)
    inicio, fim = cfg_data(cfg, "data_inicio"), cfg_data(cfg, "data_fim")

    print(f"\narea    : {cfg['area_geojson']}")
    ha = area.area(maxError=1).getInfo() / 10_000.0
    print(f"tamanho : {ha:.1f} ha  (~{int(ha * 100)} pixels de 10 m)")

    base = (ee.ImageCollection(cfg["colecao"])
            .filterBounds(area)
            .filterDate(str(inicio), str(fim)))

    n = base.size().getInfo()
    print(f"periodo : {inicio} a {fim}  ->  {n} imagens brutas")
    if n == 0:
        print("\nNenhuma imagem. Verifique o poligono e as datas.")
        return 1

    tiles = sorted(set(base.aggregate_array("MGRS_TILE").getInfo()))
    orbitas = sorted(set(base.aggregate_array("SENSING_ORBIT_NUMBER").getInfo()))

    print("\n--- cobertura ---")
    print(f"quadriculas MGRS : {', '.join(tiles)}")
    print(f"orbitas          : {', '.join(str(o) for o in orbitas)}")

    if len(tiles) > 1:
        print(f"\n  {len(tiles)} quadriculas: a area esta na faixa de sobreposicao")
        print("  e cada passagem entrega o mesmo pixel em dois produtos.")

    if len(orbitas) > 1:
        print(f"\n  {len(orbitas)} orbitas: mais revisita, geometria de visada variavel.")

    datas = base.aggregate_array("system:time_start").getInfo()
    por_ano = collections.Counter(
        dt.datetime.fromtimestamp(t / 1000, dt.timezone.utc).year for t in datas)

    col = colecao_ndvi(cfg, area, inicio, fim)
    stats = col.select("NDVI").reduce(ee.Reducer.count()).reduceRegion(
        reducer=ee.Reducer.mean().combine(ee.Reducer.minMax(), sharedInputs=True),
        geometry=area, scale=int(cfg["escala"]), maxPixels=1e9).getInfo()

    print("\n--- densidade temporal ---")
    print("imagens brutas por ano:")
    for ano in sorted(por_ano):
        print(f"  {ano}: {por_ano[ano]:>4}")

    media = stats.get("NDVI_count_mean")
    if media is not None:
        anos = (fim - inicio).days / 365.25
        print(f"\nobservacoes validas por pixel (limiar {cfg['limiar_nuvem']}):")
        print(f"  media : {media:.0f}   ({media / anos:.0f} por ano)")
        print(f"  min   : {stats.get('NDVI_count_min'):.0f}")
        print(f"  max   : {stats.get('NDVI_count_max'):.0f}")
        print(f"  aproveitamento: {100 * media / n:.0f}% das passagens")
        if media < 60:
            print("\n  poucas observacoes por pixel: historico curto compromete o")
            print("  ajuste sazonal.")

    print("\n--- criterios ---")
    print(f"  quadricula unica            : {'sim' if len(tiles) == 1 else 'nao'}")
    print(f"  >= 60 observacoes por pixel : {'sim' if (media or 0) >= 60 else 'nao'}")
    print("  confirmar visualmente com gee/inspeciona_area.js\n")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    raise SystemExit(main())
