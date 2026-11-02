#!/usr/bin/env python3
"""Fetches the outline of every lake in the club catalogs that has none yet.

A lake without data/outlines/<lake-id>.geojson gets no waves and no lake view.
For each such lake (kind "lake", used by at least one club) this asks
OpenStreetMap (Overpass) for the named waters, bays and reservoirs within
SEARCH_M of its clubs' launch points. The ones whose name contains the lake's
name ("Untere Alte Donau" and "Obere Alte Donau" for "Alte Donau", "Murtensee /
Lac de Morat" for "Murtensee") are joined into one outline. When none has the
name, the biggest water whose shore is within FALLBACK_M of a launch point is
taken and the report says so, to be checked by hand. Existing outlines are
never changed. Runs as the "Missing lake outlines" workflow (Overpass is not
reachable from every machine).

    python3 scripts/fetch_missing_outlines.py [lake-id ...]

Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import json
import math
import os
import sys
import time
import unicodedata
from pathlib import Path

from discover_clubs import water_rings
from fetch_lake_outline import overpass
from live_check import nearest_shore

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ROOT / "data" / "catalogs"
OUTLINES = ROOT / "data" / "outlines"
SEARCH_M = 3000
FALLBACK_M = 300
# Launch points closer than this to one already asked about add nothing to the query.
POINT_SPACING_M = 700
# Busy Overpass servers answer within this or not at all; a lake that fails is
# simply tried again on the next run.
QUERY_TIMEOUT_S = 90
# Lakes left out until their water is settled by hand.
SKIP = {"altrheinhafen"}  # VW Mannheim: which basin it rows on is still open (2 Nov 2026)


def fold(s: str) -> str:
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c))


def missing() -> dict[str, dict]:
    """Lake id -> {"name", "points"} for used lakes with no outline file."""
    out: dict[str, dict] = {}
    for path in sorted(CATALOGS.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or "lakes" not in data:
            continue
        lakes = {l["id"]: l for l in data["lakes"] if l.get("kind", "lake") == "lake"}
        for club in data.get("clubs", []):
            lake = lakes.get(club.get("lakeId"))
            if not lake or lake["id"] in SKIP or (OUTLINES / f"{lake['id']}.geojson").exists():
                continue
            entry = out.setdefault(lake["id"], {"name": lake["name"], "points": []})
            p = club.get("launchPoint") or lake["center"]
            entry["points"].append((p["lat"], p["lon"]))
    return out


def area_km2(rings) -> float:
    """Area of the first ring, roughly, in km²."""
    ring = rings[0]
    lat0 = sum(y for _, y in ring) / len(ring)
    k = 111.32 * math.cos(math.radians(lat0))
    pts = [(x * k, y * 110.57) for x, y in ring]
    return abs(sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]))) / 2


def spaced(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    out: list[tuple[float, float]] = []
    for lat, lon in points:
        if all(math.hypot((lat - a) * 111_000, (lon - b) * 111_000 * math.cos(math.radians(lat))) > POINT_SPACING_M for a, b in out):
            out.append((lat, lon))
    return out


def candidates(points: list[tuple[float, float]]) -> list[dict]:
    near = "\n".join(f"way(around:{SEARCH_M},{lat},{lon});" for lat, lon in points)
    return overpass(
        f"""
        [out:json][timeout:{QUERY_TIMEOUT_S}];
        ({near})->.near;
        (
          way.near["natural"~"^(water|bay)$"]["name"];
          way.near["landuse"="reservoir"]["name"];
          rel(bw.near)["natural"~"^(water|bay)$"]["name"];
          rel(bw.near)["landuse"="reservoir"]["name"];
          way.near["natural"="water"][!"name"]["water"!~"^(river|canal|stream)$"];
        );
        out geom;
        """,
        timeout=QUERY_TIMEOUT_S + 15,
    )["elements"]


def pick(name: str, points: list[tuple[float, float]], elements: list[dict]) -> tuple[list, list[str], str]:
    """(polygons, OSM ids, how it was chosen)."""
    named, others = [], []
    for e in elements:
        tags = e.get("tags", {})
        if tags.get("water") in ("river", "canal", "stream") and not tags.get("natural") == "bay":
            continue
        try:
            rings = water_rings(e)
        except (ValueError, KeyError):
            continue
        if not rings or len(rings[0]) < 4:
            continue
        item = (rings, f"{e['type']}/{e['id']}", tags.get("name", ""))
        (named if fold(name) in fold(tags.get("name", "")) else others).append(item)
    if named:
        # A relation and its own member way can both match: keep the relations' ways out.
        rel_ids = {i for _, i, _ in named if i.startswith("relation/")}
        named.sort(key=lambda it: -area_km2(it[0]))
        if rel_ids:
            named = [it for it in named if it[1].startswith("relation/")] or named
        return [it[0] for it in named], [it[1] for it in named], "name: " + ", ".join(sorted({it[2] for it in named}))
    close = [it for it in others if min(nearest_shore(lon, lat, it[0])[0] for lat, lon in points) <= FALLBACK_M]
    if not close:
        return [], [], "nothing found"
    best = max(close, key=lambda it: area_km2(it[0]))
    return [best[0]], [best[1]], f"no water named {name!r}; biggest water near the launch point: {best[2] or 'unnamed'} ({area_km2(best[0]):.2f} km²) - CHECK BY HAND"


def main(only: list[str]) -> int:
    todo = missing()
    if only:
        todo = {k: v for k, v in todo.items() if k in only}
    # SHARD=i/n takes every n-th lake, so a workflow matrix can share the work.
    shard = os.environ.get("SHARD", "")
    if shard:
        i, n = (int(x) for x in shard.split("/"))
        todo = {k: v for j, (k, v) in enumerate(sorted(todo.items())) if j % n == i}
    print(f"{len(todo)} lakes without an outline")
    failed = 0
    for lake_id, entry in sorted(todo.items()):
        points = spaced(list(dict.fromkeys(entry["points"])))
        try:
            polygons, ids, how = pick(entry["name"], points, candidates(points))
        except OSError as e:
            print(f"{lake_id}: Overpass failed: {e}")
            failed += 1
            continue
        if not polygons:
            print(f"{lake_id} ({entry['name']}): {how}")
            failed += 1
            continue
        geometry = (
            {"type": "Polygon", "coordinates": [[list(p) for p in r] for r in polygons[0]]}
            if len(polygons) == 1
            else {"type": "MultiPolygon", "coordinates": [[[list(p) for p in r] for r in rings] for rings in polygons]}
        )
        feature = {
            "type": "Feature",
            "properties": {"id": lake_id, "name": entry["name"], "osm": ids, "source": "© OpenStreetMap contributors, ODbL"},
            "geometry": geometry,
        }
        (OUTLINES / f"{lake_id}.geojson").write_text(json.dumps(feature), encoding="utf-8")
        total = sum(area_km2(rings) for rings in polygons)
        print(f"{lake_id} ({entry['name']}): {len(polygons)} part(s), {total:.2f} km², {', '.join(ids)}; {how}")
        time.sleep(2)
    return 1 if failed == len(todo) and todo else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
