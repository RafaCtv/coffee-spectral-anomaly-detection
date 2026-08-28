"""Funcoes compartilhadas pelos scripts do Earth Engine."""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib

RAIZ = pathlib.Path(__file__).resolve().parent.parent


def le_config(caminho: str | os.PathLike = None) -> dict:
    """Le o config.yml. Aceita apenas "chave: valor" (formato plano)."""
    caminho = pathlib.Path(caminho) if caminho else RAIZ / "config.yml"
    cfg: dict[str, str] = {}
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or ":" not in linha:
            continue
        chave, valor = linha.split(":", 1)
        valor = valor.split("  #")[0].strip().strip('"')
        cfg[chave.strip()] = valor
    return cfg


def cfg_data(cfg: dict, chave: str) -> dt.date:
    v = cfg[chave]
    if v.lower() == "hoje":
        return dt.date.today()
    return dt.date.fromisoformat(v)


def autentica():
    """Service account (EE_SERVICE_ACCOUNT_JSON ou _FILE) ou credencial local."""
    import ee

    projeto = os.environ.get("EE_PROJECT")
    bruto = os.environ.get("EE_SERVICE_ACCOUNT_JSON")
    arquivo = os.environ.get("EE_SERVICE_ACCOUNT_FILE")

    if bruto or arquivo:
        if bruto:
            info = json.loads(bruto)
            tmp = RAIZ / ".credenciais_tmp.json"
            tmp.write_text(bruto, encoding="utf-8")
            arquivo = str(tmp)
        else:
            info = json.loads(pathlib.Path(arquivo).read_text(encoding="utf-8"))
        cred = ee.ServiceAccountCredentials(info["client_email"], arquivo)
        ee.Initialize(cred, project=projeto or info.get("project_id"))
        print(f"EE: service account {info['client_email']}")
    else:
        ee.Initialize(project=projeto)
        print("EE: credencial local")


def carrega_area(cfg: dict):
    """GeoJSON da area -> ee.Geometry.

    Aceita FeatureCollection com varios talhoes (o caso de uma fazenda),
    Feature isolada ou Geometry pura.
    """
    import ee

    caminho = RAIZ / cfg["area_geojson"]
    if not caminho.exists():
        raise SystemExit(
            f"\nArea nao encontrada: {caminho}\n"
            "Ver docs/escolha_da_area.md\n"
        )
    gj = json.loads(caminho.read_text(encoding="utf-8"))

    if gj.get("type") == "FeatureCollection":
        feats = [ee.Feature(ee.Geometry(f["geometry"])) for f in gj["features"]]
        if not feats:
            raise SystemExit(f"GeoJSON sem feicoes: {caminho}")
        return ee.FeatureCollection(feats).geometry()
    if gj.get("type") == "Feature":
        return ee.Geometry(gj["geometry"])
    return ee.Geometry(gj)


def colecao_ndvi(cfg: dict, area, inicio: dt.date, fim: dt.date):
    """Sentinel-2 L2A mascarado pelo Cloud Score+, com a banda NDVI."""
    import ee

    cs = ee.ImageCollection(cfg["colecao_nuvem"])
    qa = cfg["banda_qa"]
    limiar = float(cfg["limiar_nuvem"])
    nir, red = cfg["banda_nir"], cfg["banda_vermelho"]

    return (
        ee.ImageCollection(cfg["colecao"])
        .filterBounds(area)
        .filterDate(str(inicio), str(fim))
        .linkCollection(cs, [qa])
        .map(lambda img: img.updateMask(img.select(qa).gte(limiar)))
        .map(lambda img: img.addBands(
            img.normalizedDifference([nir, red]).rename("NDVI")))
    )
