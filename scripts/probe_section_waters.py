#!/usr/bin/env python3
"""Research only (not to merge): the water areas around launch points that
their river section's outline misses, with their tags, and why outline()
leaves them out."""
import json, math, sys
from pathlib import Path
import shapely
from shapely.geometry import Point, shape
sys.path.insert(0, str(Path(__file__).resolve().parent))
from osm_extract import read_water, RIVER_AREAS, LAKE_AREAS, MIN_LAKE_DEG2  # noqa
from rowfrog import locations

IDS = sys.argv[2].split(",")
loaded = locations.load()
pts = {}
for cid in IDS:
    c = loaded.clubs[cid]
    lat, lon = c.launch_point.lat, c.launch_point.lon
    pts[cid] = (lat, lon, c.lake_id)
    sec = Path("data/outlines") / f"{c.lake_id}.geojson"
    d = None
    if sec.exists():
        j = json.loads(sec.read_text())
        g = shape(j["features"][0]["geometry"] if "features" in j else j["geometry"])
        d = g.distance(Point(lon, lat)) * 111_000
    print(f"== {cid}: launch {lat:.5f},{lon:.5f} water {c.lake_id} outline distance ~{d and round(d)} m", flush=True)
found = {cid: [] for cid in IDS}
for f in read_water(sys.argv[1]):
    try:
        g = shape(f["geometry"])
    except Exception:
        continue
    w, s_, e, n = g.bounds
    for cid, (lat, lon, _) in pts.items():
        k = math.cos(math.radians(lat))
        if w > lon + 0.012 / k or e < lon - 0.012 / k or s_ > lat + 0.008 or n < lat - 0.008:
            continue
        d = g.distance(Point(lon, lat)) * 111_000
        if d < 800:
            t = f["properties"]
            river = t.get("waterway") == "riverbank" or t.get("water") in RIVER_AREAS or t.get("landuse") == "harbour"
            lake = (t.get("natural") == "water" or t.get("landuse") == "reservoir") and t.get("water") in LAKE_AREAS
            kept = "river/harbour" if river else ("lake" if lake and g.area >= MIN_LAKE_DEG2 else "DROPPED by extract")
            tags = {x: t[x] for x in ("name", "natural", "water", "landuse", "waterway", "leisure", "@type", "@id") if x in t}
            found[cid].append((round(d), round(g.area * 111_000**2 * k / 1e4, 2), kept, tags))
for cid, rows in found.items():
    print(f"\n## {cid} ({pts[cid][2]})")
    for r in sorted(rows, key=lambda r: r[0])[:15]:
        print(f"  {r[0]:>4} m  {r[1]:>8} ha  {r[2]:<18} {r[3]}")
