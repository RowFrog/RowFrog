#!/usr/bin/env python3
"""Download a lake outline from OpenStreetMap and save it as GeoJSON.

Usage:
    python3 scripts/fetch_lake_outline.py starnberger-see "Starnberger See"

Writes data/outlines/<lake-id>.geojson with the shore as the outer ring and
islands as holes. Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# The main Overpass server is often overloaded (502/504); fall back to mirrors.
OVERPASS_SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
OUT_DIR = Path(__file__).resolve().parents[1] / "data" / "outlines"


def overpass(q: str) -> dict:
    """Run an Overpass QL query, trying each server in turn."""
    data = urllib.parse.urlencode({"data": q}).encode()
    errors = []
    for attempt in range(2):
        for url in OVERPASS_SERVERS:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": "RowerWeather/0.1"})
            try:
                with urllib.request.urlopen(req, timeout=90) as resp:
                    return json.load(resp)
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
                errors.append(f"{url}: {e}")
        time.sleep(10)
    raise OSError("all Overpass servers failed: " + "; ".join(errors))


def query(name: str) -> dict:
    q = f"""
    [out:json][timeout:60];
    area["ISO3166-1"="DE"]->.de;
    relation["natural"="water"]["name"="{name}"](area.de);
    out geom;
    """
    return overpass(q)


def stitch(ways: list[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    """Join OSM way segments end to end into closed rings."""
    rings, pending = [], [list(w) for w in ways]
    while pending:
        ring = pending.pop(0)
        while ring[0] != ring[-1]:
            for i, w in enumerate(pending):
                if w[0] == ring[-1]:
                    ring += w[1:]
                elif w[-1] == ring[-1]:
                    ring += w[-2::-1]
                elif w[-1] == ring[0]:
                    ring = w[:-1] + ring
                elif w[0] == ring[0]:
                    ring = w[:0:-1] + ring
                else:
                    continue
                pending.pop(i)
                break
            else:
                raise ValueError("could not close a ring; the OSM relation may be incomplete")
        rings.append(ring)
    return rings


def main() -> None:
    lake_id, name = sys.argv[1], sys.argv[2]
    result = query(name)
    relations = [e for e in result["elements"] if e["type"] == "relation"]
    if not relations:
        sys.exit(f"no water relation named {name!r} found")
    members = relations[0]["members"]
    outer = [[(p["lon"], p["lat"]) for p in m["geometry"]] for m in members if m.get("role") == "outer"]
    inner = [[(p["lon"], p["lat"]) for p in m["geometry"]] for m in members if m.get("role") == "inner"]
    rings = stitch(outer) + (stitch(inner) if inner else [])
    geojson = {
        "type": "Feature",
        "properties": {"id": lake_id, "name": name, "source": "© OpenStreetMap contributors, ODbL"},
        "geometry": {"type": "Polygon", "coordinates": [[list(p) for p in r] for r in rings]},
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{lake_id}.geojson"
    out.write_text(json.dumps(geojson), encoding="utf-8")
    print(f"wrote {out} with {len(rings)} ring(s)")


if __name__ == "__main__":
    main()
