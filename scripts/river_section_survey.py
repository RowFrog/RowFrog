#!/usr/bin/env python3
"""Research only: how far every river club is from the next weir or lock.

Clubs on the same river within CLUSTER_KM share one stretch. For each stretch,
walks the club's river (the OpenStreetMap ways carrying the name of the river
line nearest the launch point) upstream and downstream up to MAX_KM and notes
the first weir, dam, lock or waterfall each way, where the line ends instead
(source, mouth into another water, or a gap in the map data), the nearest
river kilometre marker, and the river's width near the club.

Usage: river_section_survey.py SHARD SHARDS OUT.json   (shards run in parallel
jobs so each gets its own Overpass allowance). Nothing is stored in the repo.
Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import heapq
import json
import math
import sys
import time
from pathlib import Path

from shapely import STRtree
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_lake_outline import overpass  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MAX_KM = 25.0
CLUSTER_KM = 3.0
GAP_M = 40.0  # line ends this close to another line of the same river are joined
BARRIERS = ("weir", "dam", "lock_gate", "waterfall")


def km(a, b) -> float:
    return math.hypot((a[0] - b[0]) * 110.574, (a[1] - b[1]) * 111.32 * math.cos(math.radians(a[0])))


def clusters() -> list[dict]:
    seen, clubs = set(), []
    for f in sorted((ROOT / "data" / "catalogs").glob("*-*.json")):
        if f.name == "water-fixes.json":
            continue
        d = json.loads(f.read_text())
        names = {l["id"]: l["name"] for l in d["lakes"]}
        for c in d["clubs"]:
            if c["lakeId"].startswith("river-") and c["id"] not in seen:
                seen.add(c["id"])
                lp = c["launchPoint"]
                clubs.append({"id": c["id"], "water": names.get(c["lakeId"], c["lakeId"]), "lakeId": c["lakeId"], "country": c["country"], "at": (lp["lat"], lp["lon"])})
    out = []
    for c in clubs:
        for g in out:
            if g["lakeId"] == c["lakeId"] and km(g["at"], c["at"]) < CLUSTER_KM:
                g["clubs"].append(c["id"])
                break
        else:
            out.append({"lakeId": c["lakeId"], "water": c["water"], "country": c["country"], "at": c["at"], "clubs": [c["id"]]})
    return out


def query(lat: float, lon: float) -> dict:
    """Two light queries instead of one wide one: first the waters near the
    launch point (for the river's name, its width and river kilometres), then
    only that river's lines, the waterways they touch and the weirs and locks
    in a box MAX_KM around the club."""
    near = overpass(
        f"""
        [out:json][timeout:120];
        (
          way["waterway"~"^(river|canal)$"](around:1500,{lat},{lon});
          node["waterway"="milestone"](around:2000,{lat},{lon});
          way["natural"="water"]["water"~"^(river|canal)$"](around:1500,{lat},{lon});
          way["waterway"="riverbank"](around:1500,{lat},{lon});
        );
        out body geom;
        """,
        timeout=180,
    )
    lines = [e for e in near["elements"] if e["type"] == "way" and e.get("tags", {}).get("waterway") in ("river", "canal") and e.get("geometry")]
    if not lines:
        return near
    k = math.cos(math.radians(lat))
    d = lambda p: math.hypot((p["lat"] - lat) * 110.574, (p["lon"] - lon) * 111.32 * k)  # noqa: E731
    name = min(lines, key=lambda w: min(d(p) for p in w["geometry"]))["tags"].get("name", "")
    if not name:
        return near
    dlat, dlon = (MAX_KM + 2) / 110.574, (MAX_KM + 2) / (111.32 * k)
    box = f"{lat - dlat},{lon - dlon},{lat + dlat},{lon + dlon}"
    esc = name.replace("\\", "\\\\").replace('"', '\\"')
    far = overpass(
        f"""
        [out:json][timeout:240];
        way["waterway"~"^(river|canal)$"]["name"="{esc}"]({box})->.r;
        node(w.r)->.n;
        (
          .r;
          way(bn.n)["waterway"~"^(river|canal)$"];
          node["waterway"~"^({'|'.join(BARRIERS)})$"]({box});
          way["waterway"~"^({'|'.join(BARRIERS)})$"]({box});
          way["lock"="yes"]({box});
        );
        out body geom;
        """,
        timeout=300,
    )
    seen, els = set(), []
    for e in near["elements"] + far["elements"]:
        if (e["type"], e["id"]) not in seen:
            seen.add((e["type"], e["id"]))
            els.append(e)
    return {"elements": els}


def survey(g: dict, data: dict, max_km: float = MAX_KM) -> dict:
    """With max_km beyond MAX_KM (the ends survey) it also lists, per
    direction, the rivers joining or branching off and the harbours passed."""
    lat0, lon0 = g["at"]
    k = math.cos(math.radians(lat0))
    to_m = lambda lon, lat: ((lon - lon0) * 111_320 * k, (lat - lat0) * 110_574)  # noqa: E731
    els = data["elements"]
    ways = [e for e in els if e["type"] == "way" and e.get("tags", {}).get("waterway") in ("river", "canal") and e.get("geometry")]
    if not ways:
        return {"error": "no river line found"}
    # The river: the name of the line nearest the launch point (as in query()).
    def way_dist(w):
        pts = [to_m(p["lon"], p["lat"]) for p in w["geometry"]]
        return LineString(pts).distance(Point(0, 0)) if len(pts) > 1 else 1e9
    own = [w for w in ways if w["tags"].get("name") == g.get("water") and way_dist(w) < 1500]
    named = [w for w in ways if w["tags"].get("name") and way_dist(w) < 1500]
    nearest = min(own or named or ways, key=way_dist)
    name = nearest["tags"].get("name", "")
    river = [w for w in ways if name and w["tags"].get("name", "") == name] or [nearest]
    others = [w for w in ways if w not in river]

    coords, graph, way_of = {}, {}, {}
    lock_ways = {e["id"] for e in els if e["type"] == "way" and e.get("tags", {}).get("lock") == "yes"}
    for w in river:
        for nid, p in zip(w["nodes"], w["geometry"]):
            coords[nid] = to_m(p["lon"], p["lat"])
            way_of.setdefault(nid, set()).add(w["id"])
        for a, b in zip(w["nodes"], w["nodes"][1:]):
            d = math.dist(coords[a], coords[b])
            graph.setdefault(a, []).append((b, d, True, w["id"] in lock_ways))
            graph.setdefault(b, []).append((a, d, False, w["id"] in lock_ways))
    # Join gaps: a line end close to another node of the same river.
    ends = [n for n, e in graph.items() if len(e) == 1]
    cells: dict[tuple[int, int], list[int]] = {}
    for n in graph:
        cells.setdefault((int(coords[n][0] // GAP_M), int(coords[n][1] // GAP_M)), []).append(n)
    bridged = 0
    for n in ends:
        best = None
        x, y = coords[n]
        near = [m for i in (-1, 0, 1) for j in (-1, 0, 1) for m in cells.get((int(x // GAP_M) + i, int(y // GAP_M) + j), [])]
        for m in near:
            if not (way_of[m] & way_of[n]):
                d = math.dist(coords[n], coords[m])
                if d < GAP_M and (best is None or d < best[1]):
                    best = (m, d)
        if best:
            m, d = best
            down = graph[n][0][2] is False  # n is the end of a way that flows into it -> continue downstream
            graph[n].append((m, d, down, False))
            graph[m].append((n, d, not down, False))
            bridged += 1
    other_nodes, side_rivers = {}, {}
    for w in others:
        for nid, p in zip(w["nodes"], w["geometry"]):
            other_nodes[nid] = w["tags"].get("name", "") or w["tags"]["waterway"]
        if w["tags"].get("name") and w["tags"]["name"] != name:
            for nid, how in ((w["nodes"][-1], "joins"), (w["nodes"][0], "branches off")):
                if nid in coords:
                    side_rivers.setdefault(nid, []).append((w["tags"]["waterway"], w["tags"]["name"], how))
    lengths = data.get("lengths", {})
    harbours = []
    for e in els:
        t = e.get("tags", {})
        if e.get("harbour") and e.get("geometry"):
            pts = [to_m(p["lon"], p["lat"]) for p in e["geometry"]]
            if len(pts) >= 4:
                harbours.append((t.get("name") or t.get("water") or t.get("landuse"), Polygon(pts).buffer(0)))
    harbour_tree = STRtree([h for _, h in harbours])

    barrier_nodes, barrier_lines = {}, []
    for e in els:
        tags = e.get("tags", {})
        kind = tags.get("waterway")
        if kind not in BARRIERS:
            continue
        label = f"{kind} {tags.get('name', '')}".strip()
        if e["type"] == "node":
            barrier_nodes[e["id"]] = (label, Point(to_m(e["lon"], e["lat"])))
        elif e.get("geometry"):
            barrier_lines.append((label, LineString([to_m(p["lon"], p["lat"]) for p in e["geometry"]])))
            for nid in e.get("nodes", []):
                barrier_nodes.setdefault(nid, (label, None))

    shapes = [(label, pt) for label, pt in barrier_nodes.values() if pt is not None] + barrier_lines
    tree = STRtree([g for _, g in shapes])

    def crosses(a, b):
        if b in barrier_nodes:
            return barrier_nodes[b][0]
        seg = LineString([coords[a], coords[b]])
        for i in tree.query(seg, predicate="dwithin", distance=25):
            label, shape = shapes[i]
            if shape.geom_type == "Point" or seg.intersects(shape):
                return label
        return None

    start = min(coords, key=lambda n: math.hypot(*coords[n]))
    result = {"river": name, "snapM": round(math.hypot(*coords[start])), "bridged": bridged}
    for downstream in (True, False):
        dist, heap, stops, events, seen_ev = {start: 0.0}, [(0.0, start)], [], [], set()
        while heap:
            d, n = heapq.heappop(heap)
            if d > dist.get(n, math.inf):
                continue
            for kind, other, how in side_rivers.get(n, ()):
                if (other, how) not in seen_ev:
                    seen_ev.add((other, how))
                    events.append((d, f"{kind} {other} {how}", lengths.get(other)))
            if harbours:
                for i in harbour_tree.query(Point(coords[n]), predicate="dwithin", distance=150):
                    label = "harbour " + str(harbours[i][0])
                    if label not in seen_ev:
                        seen_ev.add(label)
                        events.append((d, label, round(harbours[i][1].area / 1e6, 3)))
            moves = [x for x in graph.get(n, []) if x[2] == downstream]
            if not moves:
                if n in other_nodes:
                    stops.append((d, "joins " + other_nodes[n]))
                elif d < max_km * 1000 - 3000:
                    stops.append((d, "line ends"))
                else:
                    stops.append((d, "search edge"))
            for m, w, _, lock in moves:
                if lock:
                    stops.append((d, "lock"))
                    continue
                label = crosses(n, m)
                if label:
                    stops.append((d + w / 2, label))
                    continue
                nd = d + w
                if nd > max_km * 1000:
                    stops.append((max_km * 1000, f"none within {max_km:g} km"))
                    continue
                if nd < dist.get(m, math.inf):
                    dist[m] = nd
                    heapq.heappush(heap, (nd, m))
        stops.sort()
        barrier = next(((d, r) for d, r in stops if r.split()[0] in BARRIERS + ("lock",)), None)
        key = "down" if downstream else "up"
        result[key + "Barrier"] = [round(barrier[0] / 1000, 1), barrier[1]] if barrier else None
        result[key + "Reach"] = round(max(dist.values()) / 1000, 1)
        result[key + "Stops"] = [[round(d / 1000, 1), r] for d, r in stops[:3]]
        if max_km > MAX_KM:
            events.sort(key=lambda e: e[0])
            result[key + "Events"] = [[round(d / 1000, 1), r, ln] for d, r, ln in events[:25]]

    ms = [e for e in els if e["type"] == "node" and e.get("tags", {}).get("waterway") == "milestone"]
    if ms:
        m = min(ms, key=lambda e: math.hypot(*to_m(e["lon"], e["lat"])))
        result["riverKm"] = [m["tags"].get("distance"), round(math.hypot(*to_m(m["lon"], m["lat"])))]
    polys = []
    for e in els:
        t = e.get("tags", {})
        if e["type"] == "way" and (t.get("natural") == "water" or t.get("waterway") == "riverbank") and e.get("geometry"):
            pts = [to_m(p["lon"], p["lat"]) for p in e["geometry"]]
            if len(pts) >= 4 and pts[0] == pts[-1]:
                polys.append(Polygon(pts).buffer(0))
    band = [LineString([coords[a], coords[b]]) for a in coords for b, *_ in graph.get(a, []) if math.hypot(*coords[a]) < 1000]
    if polys and band:
        line = unary_union(band)
        water = unary_union(polys).intersection(line.buffer(600, cap_style=2))
        if line.length:
            result["widthM"] = round(water.area / line.length)
    return result


def main() -> None:
    if sys.argv[1] == "--extract":
        # river_section_survey.py --extract lines.osm.pbf water.geojsonseq OUT.json
        from osm_extract import Extract

        ex = Extract(sys.argv[2], sys.argv[3])
        out, rows, groups = sys.argv[4], [], clusters()
        reach = float(sys.argv[5]) if len(sys.argv) > 5 else MAX_KM
        for g in groups:
            try:
                r = survey(g, ex.query(*g["at"], reach, g["water"]), reach)
            except Exception as e:  # research survey: note and go on
                r = {"error": f"{type(e).__name__}: {str(e)[:200]}"}
            rows.append({**g, **r})
            print(json.dumps(rows[-1], ensure_ascii=False), flush=True)
        Path(out).write_text(json.dumps(rows, ensure_ascii=False))
        return
    shard, shards, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    groups = clusters()
    mine = groups[shard::shards]
    print(f"{len(groups)} stretches for {sum(len(g['clubs']) for g in groups)} clubs; shard {shard} has {len(mine)}", flush=True)
    rows = []
    for g in mine:
        r = None
        for attempt in range(2):
            try:
                r = survey(g, query(*g["at"]))
                break
            except Exception as e:  # research survey: note and go on
                r = {"error": f"{type(e).__name__}: {str(e)[:200]}"}
                time.sleep(30)
        row = {**g, **r}
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        Path(out).write_text(json.dumps(rows, ensure_ascii=False))
        time.sleep(3)
    Path(out).write_text(json.dumps(rows, ensure_ascii=False))


if __name__ == "__main__":
    main()
