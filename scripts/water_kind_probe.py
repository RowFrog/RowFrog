#!/usr/bin/env python3
"""Research only: how OpenStreetMap tags each water our clubs are on.

For every water in data/catalogs and data/locations.json, finds the named
OpenStreetMap water near its centre and prints its tags (natural=water +
water=reservoir|lake|basin|river..., landuse=reservoir, waterway=*), so we can
see which "lake" clubs are on a reservoir and which "river" clubs are on an
impounded stretch or basin. One Overpass query per 40 waters. Nothing is stored.
Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import json
import sys
import time
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_lake_outline import overpass  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def waters() -> list[dict]:
    out, clubs = {}, Counter()
    files = sorted((ROOT / "data" / "catalogs").glob("*-*.json"))
    for f in files:
        if f.name == "water-fixes.json":
            continue
        d = json.loads(f.read_text())
        for c in d["clubs"]:
            clubs[c["lakeId"]] += 1
        for l in d["lakes"]:
            out.setdefault(l["id"], {"id": l["id"], "name": l["name"], "kind": l.get("kind", "lake"), "center": l["center"]})
    loc = json.loads((ROOT / "data" / "locations.json").read_text())
    for l in loc.get("lakes", []):
        out.setdefault(l["id"], {"id": l["id"], "name": l["name"], "kind": l.get("kind", "lake"), "center": l["center"]})
    for c in loc.get("clubs", []):
        clubs[c["lakeId"]] += 1
    rows = [dict(w, clubs=clubs[w["id"]]) for w in out.values() if clubs[w["id"]]]
    return rows


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def from_extract(path: str) -> None:
    """water_kind_probe.py --extract water.geojsonseq [lines-tags.json]: the same
    answer from a downloaded extract. Prints one line per water."""
    from shapely.geometry import Point, shape

    from osm_extract import read_water

    rows = waters()
    by_name: dict[str, list[dict]] = {}
    for w in rows:
        by_name.setdefault(w["name"], []).append(w)
    found: dict[str, Counter] = {w["id"]: Counter() for w in rows}
    for f in read_water(path):
        t = f["properties"]
        ws = by_name.get(t.get("name", ""))
        if not ws:
            continue
        g = shape(f["geometry"])
        for w in ws:
            c = w["center"]
            d = g.distance(Point(c["lon"], c["lat"])) * 111
            if d <= 4:
                key = ",".join(f"{k}={t[k]}" for k in ("natural", "water", "landuse", "waterway", "reservoir_type", "basin") if k in t)
                found[w["id"]][key] += 1
    for w in rows:
        print(json.dumps({"id": w["id"], "name": w["name"], "kind": w["kind"], "clubs": w["clubs"], "osm": dict(found[w["id"]])}, ensure_ascii=False), flush=True)


def main() -> None:
    if len(sys.argv) > 2 and sys.argv[1] == "--extract":
        from_extract(sys.argv[2])
        return
    rows = waters()
    print(f"{len(rows)} waters with clubs", flush=True)
    for i in range(0, len(rows), 40):
        part = rows[i : i + 40]
        q = "[out:json][timeout:240];(\n"
        for w in part:
            lat, lon = w["center"]["lat"], w["center"]["lon"]
            r = 4000 if w["kind"] == "lake" else 2500
            n = esc(w["name"])
            q += f'way["name"="{n}"]["natural"="water"](around:{r},{lat},{lon});rel["name"="{n}"]["natural"="water"](around:{r},{lat},{lon});'
            q += f'way["name"="{n}"]["landuse"="reservoir"](around:{r},{lat},{lon});rel["name"="{n}"]["landuse"="reservoir"](around:{r},{lat},{lon});'
            q += f'way["name"="{n}"]["waterway"](around:{r},{lat},{lon});\n'
        q += ");out tags;"
        for attempt in range(3):
            try:
                els = overpass(q, timeout=300)["elements"]
                break
            except OSError as e:
                print("retry", e, flush=True)
                time.sleep(60)
        else:
            els = []
        by_name: dict[str, Counter] = {}
        for e in els:
            t = e.get("tags", {})
            key = ",".join(f"{k}={t[k]}" for k in ("natural", "water", "landuse", "waterway", "reservoir_type", "basin") if k in t)
            by_name.setdefault(t.get("name", ""), Counter())[key] += 1
        for w in part:
            tags = dict(by_name.get(w["name"], {}))
            print(json.dumps({"id": w["id"], "name": w["name"], "kind": w["kind"], "clubs": w["clubs"], "osm": tags}, ensure_ascii=False), flush=True)
        time.sleep(10)


if __name__ == "__main__":
    main()
