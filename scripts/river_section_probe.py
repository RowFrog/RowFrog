#!/usr/bin/env python3
"""Research only: work out a rowing section of the river around a few river clubs.

From the club's launch point, walks along the OpenStreetMap river and canal
centre lines upstream and downstream until it reaches a weir, dam, lock or
waterfall, or MAX_KM. The water area (riverbank polygons) along the walked lines
is the section outline a river version of the lake view would cover.

Prints one summary line per club and the section as compact GeoJSON between
SECTION-BEGIN/SECTION-END lines, so it can be drawn from the job log.
Nothing is stored. Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import heapq
import json
import math
import sys
import time
from pathlib import Path

from shapely.geometry import LineString, MultiLineString, Point, Polygon, mapping
from shapely.ops import linemerge, polygonize, transform, unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_lake_outline import overpass  # noqa: E402

MAX_KM = 10.0
RADIUS_M = 13000
CORRIDOR_M = 500.0  # water this far either side of the walked centre line counts
CELL_M = (40.0, 1000.0)
TARGET_CELLS = 1000
SAMPLE_SPACING_M = 2200.0
BARRIERS = ("weir", "dam", "lock_gate", "waterfall")

CLUBS = [
    ("frankfurter-rudergesellschaft-germania-1869", "Main", 50.10397, 8.67416),
    ("wuerzburger-ruderverein-bayern-von-18751905", "Main", 49.76963, 9.93629),
    ("heidelberger-ruderklub-1872", "Neckar", 49.41358, 8.69465),
    ("giessener-rudergesellschaft-1877", "Lahn", 50.58984, 8.66961),
    ("koelner-ruderverein-von-1877", "Rhein", 50.89356, 6.99558),
    ("askoe-ruderverein-donau-linz", "Donau", 48.31969, 14.29452),
    ("akademischer-ruder-club-zu-muenster", "Dortmund-Ems-Kanal", 51.95037, 7.64921),
    ("ruderclub-narva-oberspree", "Spree", 52.45489, 13.54546),
    ("universitaetssportverein-tu-dresden-ev-abt-rudern", "Elbe", 51.04721, 13.81316),
    ("ruderclub-baden", "Limmat", 47.45653, 8.3253),
    ("passauer-ruderverein-von-1874", "Inn", 48.54957, 13.43622),
    ("tuebinger-ruderverein-fidelia-18771911", "Neckar", 48.5229, 9.08143),
]


def projector(lat0: float, lon0: float):
    k = math.cos(math.radians(lat0))
    to_m = lambda lon, lat: ((lon - lon0) * 111_320 * k, (lat - lat0) * 110_574)  # noqa: E731
    to_deg = lambda x, y: (lon0 + x / (111_320 * k), lat0 + y / 110_574)  # noqa: E731
    return to_m, to_deg


def query(lat: float, lon: float) -> dict:
    a = f"(around:{RADIUS_M},{lat},{lon})"
    return overpass(
        f"""
        [out:json][timeout:180];
        (
          way["waterway"~"^(river|canal)$"]{a};
          way["waterway"~"^({'|'.join(BARRIERS)})$"]{a};
          node["waterway"~"^({'|'.join(BARRIERS)})$"]{a};
          way["lock"="yes"]{a};
          way["natural"="water"]["water"~"^(river|canal|lock|oxbow|harbour)$"]{a};
          way["waterway"="riverbank"]{a};
          relation["natural"="water"]["water"~"^(river|canal|lock|oxbow|harbour)$"]{a};
          relation["waterway"="riverbank"]{a};
        );
        out body geom;
        """,
        timeout=240,
    )


def water_area(elements: list[dict], to_m) -> Polygon:
    polys = []
    for e in elements:
        tags = e.get("tags", {})
        if tags.get("natural") != "water" and tags.get("waterway") != "riverbank":
            continue
        if e["type"] == "way" and e.get("geometry"):
            pts = [to_m(p["lon"], p["lat"]) for p in e["geometry"]]
            if len(pts) >= 4 and pts[0] == pts[-1]:
                polys.append(Polygon(pts).buffer(0))
        elif e["type"] == "relation":
            outer, inner = [], []
            for m in e.get("members", []):
                if m.get("type") == "way" and m.get("geometry"):
                    line = LineString([to_m(p["lon"], p["lat"]) for p in m["geometry"]])
                    (inner if m.get("role") == "inner" else outer).append(line)
            shape = unary_union(list(polygonize(linemerge(outer)))) if outer else None
            if shape is not None and not shape.is_empty:
                if inner:
                    shape = shape.difference(unary_union(list(polygonize(linemerge(inner)))))
                polys.append(shape.buffer(0))
    return unary_union(polys) if polys else Polygon()


def section(name: str, lat: float, lon: float, data: dict) -> dict:
    to_m, to_deg = projector(lat, lon)
    els = data["elements"]
    coords: dict[int, tuple[float, float]] = {}
    # node -> [(next node, metres, downstream?, way)]
    graph: dict[int, list] = {}
    barrier_nodes: dict[int, str] = {}
    barrier_shapes = []
    lock_ways = set()
    for e in els:
        tags = e.get("tags", {})
        kind = tags.get("waterway")
        label = f"{kind or 'lock'} {tags.get('name', '')}".strip()
        if e["type"] == "node" and kind in BARRIERS:
            barrier_nodes[e["id"]] = label
            barrier_shapes.append((Point(to_m(e["lon"], e["lat"])), label))
        elif e["type"] == "way" and kind in BARRIERS and e.get("geometry"):
            barrier_shapes.append((LineString([to_m(p["lon"], p["lat"]) for p in e["geometry"]]), label))
        if e["type"] == "way" and tags.get("lock") == "yes":
            lock_ways.add(e["id"])
    for e in els:
        tags = e.get("tags", {})
        if e["type"] != "way" or tags.get("waterway") not in ("river", "canal") or not e.get("geometry"):
            continue
        if tags.get("tunnel") or tags.get("boat") == "no":
            continue
        ids, geom = e["nodes"], e["geometry"]
        for nid, p in zip(ids, geom):
            coords[nid] = to_m(p["lon"], p["lat"])
        for a, b in zip(ids, ids[1:]):
            d = math.dist(coords[a], coords[b])
            info = (e["id"], tags.get("name", ""), e["id"] in lock_ways)
            graph.setdefault(a, []).append((b, d, True, info))
            graph.setdefault(b, []).append((a, d, False, info))
    for e in els:  # barrier nodes that sit on the centre lines
        if e["type"] == "way" and e.get("tags", {}).get("waterway") in BARRIERS:
            for nid in e.get("nodes", []):
                if nid in coords:
                    barrier_nodes.setdefault(nid, f"{e['tags']['waterway']} {e['tags'].get('name', '')}".strip())

    # Snap the launch point to the nearest centre-line node of a way with the river's name, else any.
    named = [n for n, edges in graph.items() if any(name.lower() in i[1].lower() for _, _, _, i in edges)]
    pool = named or list(graph)
    if not pool:
        return {"error": "no river centre line found"}
    start = min(pool, key=lambda n: math.hypot(*coords[n]))
    snap_m = math.hypot(*coords[start])

    def crosses_barrier(a: int, b: int) -> str | None:
        if b in barrier_nodes:
            return barrier_nodes[b]
        seg = LineString([coords[a], coords[b]])
        for shape, label in barrier_shapes:
            if shape.geom_type == "Point" and seg.distance(shape) < 25:
                return label
            if shape.geom_type == "LineString" and seg.intersects(shape):
                return label
        return None

    result = {}
    lines = []
    for downstream in (True, False):
        dist = {start: 0.0}
        heap = [(0.0, start)]
        ends = []
        while heap:
            d, n = heapq.heappop(heap)
            if d > dist.get(n, math.inf):
                continue
            moved = False
            for m, w, down, info in graph.get(n, []):
                if down != downstream:
                    continue
                if info[2]:
                    ends.append((d, f"lock {info[1]}".strip()))
                    continue
                stop = crosses_barrier(n, m)
                if stop:
                    ends.append((d + w / 2, stop))
                    lines.append(LineString([coords[n], _towards(coords[n], coords[m], w / 2)]))
                    continue
                nd = d + w
                if nd > MAX_KM * 1000:
                    left = MAX_KM * 1000 - d
                    lines.append(LineString([coords[n], _towards(coords[n], coords[m], left)]))
                    ends.append((MAX_KM * 1000, f"{MAX_KM:g} km limit"))
                    continue
                if nd < dist.get(m, math.inf):
                    dist[m] = nd
                    lines.append(LineString([coords[n], coords[m]]))
                    heapq.heappush(heap, (nd, m))
                    moved = True
            if not moved and not any(down == downstream for _, _, down, _ in graph.get(n, [])):
                ends.append((d, "centre line ends (edge of the search area or source)"))
        reach = max([d for d, _ in ends] + list(dist.values()))
        ends.sort()
        key = "down" if downstream else "up"
        result[key + "Km"] = round(reach / 1000, 1)
        result[key + "Ends"] = sorted({f"{r} at {d / 1000:.1f} km" for d, r in ends[:4]})

    walked = linemerge(unary_union(lines))
    corridor = walked.buffer(CORRIDOR_M, cap_style=2)
    water = water_area(els, to_m)
    outline = water.intersection(corridor)
    # Keep only water connected to the walked line.
    if outline.geom_type == "MultiPolygon":
        outline = unary_union([p for p in outline.geoms if p.distance(walked) < 30])
    if outline.is_empty:
        outline = walked.buffer(15)  # small river drawn as a line only
        result["outline"] = "no riverbank polygons; 30 m band around the centre line"
    area = outline.area
    length = walked.length
    cell = max(CELL_M[0], min(CELL_M[1], math.sqrt(area / TARGET_CELLS)))
    result.update(
        snapMetres=round(snap_m),
        lengthKm=round(length / 1000, 1),
        areaKm2=round(area / 1e6, 2),
        meanWidthM=round(area / length) if length else None,
        cellM=round(cell),
        cells=round(area / cell**2),
        samples=max(1, math.ceil(length / SAMPLE_SPACING_M)),
    )
    simple = transform(lambda x, y, z=None: to_deg(x, y), outline.simplify(8))
    line = transform(lambda x, y, z=None: to_deg(x, y), walked.simplify(8))
    barriers = [
        {"label": label, "at": [round(v, 5) for v in to_deg(*shape.centroid.coords[0])]}
        for shape, label in barrier_shapes
        if shape.distance(walked) < 300
    ]
    result["geo"] = {"outline": _round(mapping(simple)), "line": _round(mapping(line)), "barriers": barriers}
    return result


def _towards(a, b, metres):
    d = math.dist(a, b) or 1
    t = min(1.0, metres / d)
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def _round(obj):
    if isinstance(obj, float):
        return round(obj, 5)
    if isinstance(obj, (list, tuple)):
        return [_round(v) for v in obj]
    if isinstance(obj, dict):
        return {k: _round(v) for k, v in obj.items()}
    return obj


def main() -> None:
    for club, river, lat, lon in CLUBS:
        try:
            data = query(lat, lon)
            r = section(river, lat, lon, data)
        except Exception as e:  # research probe: report and go on
            print(f"{club}: {type(e).__name__}: {e}", flush=True)
            continue
        geo = r.pop("geo", None)
        print(f"{club} ({river}): {json.dumps(r, ensure_ascii=False)}", flush=True)
        if geo:
            print("SECTION-BEGIN " + json.dumps({"club": club, "river": river, "lat": lat, "lon": lon, **geo}, separators=(",", ":")))
            print("SECTION-END", flush=True)
        time.sleep(5)


if __name__ == "__main__":
    main()
