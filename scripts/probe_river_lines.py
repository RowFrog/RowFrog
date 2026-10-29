"""Temporary probe: the waterway lines and barriers near a few club points, with their tags and how they connect."""
import math
import sys
from collections import defaultdict

sys.path.insert(0, "scripts")
from osm_extract import Extract, _cells  # noqa: E402

POINTS = {
    "saarbruecken": (49.2249, 7.0088),
    "stahnsdorf": (52.39462, 13.20744),
    "leer": (53.2240, 7.4519),
    "breisach": (48.02195, 7.58432),
}
R_KM = 3.0
ex = Extract(sys.argv[1], None)
for name, (lat, lon) in POINTS.items():
    k = math.cos(math.radians(lat))

    def m(p):
        return ((p["lon"] - lon) * 111320 * k, (p["lat"] - lat) * 110574)

    dlat, dlon = R_KM / 110.574, R_KM / (111.32 * k)
    ids = {w for c in _cells(lat - dlat, lon - dlon, lat + dlat, lon + dlon) for w in ex.way_grid[c]}
    ways = [ex.ways[i] for i in ids]
    ends = defaultdict(set)
    for w in ways:
        for nid in w["nodes"]:
            ends[nid].add(w["id"])
    print(f"=== {name} {lat},{lon}: {len(ways)} ways")
    rows = []
    for w in ways:
        pts = [m(p) for p in w["geometry"]]
        d = min(math.hypot(*p) for p in pts)
        if d > R_KM * 1000:
            continue
        length = sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))
        t = w.get("tags", {})
        first, last = w["nodes"][0], w["nodes"][-1]
        rows.append((round(d), w["id"], t.get("waterway"), t.get("name", ""),
                     {kk: v for kk, v in t.items() if kk not in ("waterway", "name") and not kk.startswith(("name:", "wiki", "source", "ref:"))},
                     round(length), [round(v) for v in pts[0]], [round(v) for v in pts[-1]],
                     sorted(ends[first] - {w["id"]}), sorted(ends[last] - {w["id"]})))
    for r in sorted(rows):
        print("  way", r)
    nids = {n for c in _cells(lat - dlat, lon - dlon, lat + dlat, lon + dlon) for n in ex.node_grid[c]}
    for nid in nids:
        e = ex.nodes[nid]
        p = m(e)
        if math.hypot(*p) < R_KM * 1000 and e["tags"].get("waterway") != "milestone":
            print("  node", nid, e["tags"], [round(v) for v in p], sorted(ends.get(nid, ())))
