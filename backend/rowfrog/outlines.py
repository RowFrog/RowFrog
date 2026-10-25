"""Lake outlines used for the fetch calculation.

Outlines live in data/outlines/<lake-id>.geojson and are downloaded from
OpenStreetMap with scripts/fetch_lake_outline.py (ODbL, credit
"© OpenStreetMap contributors"). Without an outline, waves are not computed.
"""

from __future__ import annotations

import json
from pathlib import Path

DEFAULT_DIR = Path(__file__).resolve().parents[2] / "data" / "outlines"

Rings = list[list[tuple[float, float]]]


def rings_from_geojson(geojson: dict) -> Rings:
    """All rings (shore and islands) of the first Polygon or MultiPolygon found."""
    geom = geojson
    if geom.get("type") == "FeatureCollection":
        geom = geom["features"][0]["geometry"]
    elif geom.get("type") == "Feature":
        geom = geom["geometry"]
    if geom["type"] == "Polygon":
        polygons = [geom["coordinates"]]
    elif geom["type"] == "MultiPolygon":
        polygons = geom["coordinates"]
    else:
        raise ValueError(f"unsupported geometry {geom['type']}")
    rings: Rings = []
    for polygon in polygons:
        for ring in polygon:
            pts = [(float(x), float(y)) for x, y, *_ in ring]
            if pts and pts[0] == pts[-1]:
                pts = pts[:-1]
            rings.append(pts)
    return rings


def load(lake_id: str, directory: Path = DEFAULT_DIR) -> Rings | None:
    path = directory / f"{lake_id}.geojson"
    if not path.exists():
        return None
    return rings_from_geojson(json.loads(path.read_text(encoding="utf-8")))
