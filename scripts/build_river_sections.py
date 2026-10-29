#!/usr/bin/env python3
"""Builds the river sections of the river and canal clubs (data/river-sections.json
and an outline per section in data/outlines/<section-id>.geojson).

A section is the stretch of river a club rows on. Clubs on the same water
within CLUSTER_KM of each other share one. The rule (owner's choices of
2026-10-27 and 2026-10-28, proposal page "River sections", round 3):
  1. Rivers with weirs or locks: to the next weir or lock each way, up to
     REACH_KM (25 km) each way.
  2. Open sides (no weir or lock within REACH_KM) end at the first of these
     between MIN_KM and OPEN_KM away: the river's mouth, a big river joining
     or branching off (BIG_KM of named line around the club, about 80 km
     long in all), a big harbour (BIG_HARBOUR_KM2).
  3. Otherwise CAP_UP_KM upstream and CAP_DOWN_KM downstream (CAP_CANAL_KM
     each way on canals), moved to a river km sign within KM_SIGN_M.
data/river-section-overrides.json adds the owner's hand checks: extra waters
that belong to a stretch ("include") and the side a club rows on where a weir
or lock sits right at its boathouse ("direction").

The outline is the river's water area (OpenStreetMap riverbanks, river and
canal areas, and the lakes a river flows through) along the walked stretch,
cut square at its ends; where the map has no water area, a band of the
river's width around its line. The section's own harbour is added for clubs
that row out of one. The second feature of each outline is the river line,
pointing downstream, for the current in the route planner.

Runs in the "River sections" workflow on the Geofabrik extracts of Germany,
Austria and Switzerland (scripts/osm_extract.py):
    build_river_sections.py lines.osm.pbf water.geojsonseq [--only ID,ID]
Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import argparse
import heapq
import json
import math
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

import shapely
from shapely import STRtree, line_merge
from shapely.geometry import LineString, MultiLineString, Point, Polygon, mapping
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
from osm_extract import Extract  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "river-sections.json"
OUTLINES = ROOT / "data" / "outlines"
OVERRIDES = ROOT / "data" / "river-section-overrides.json"
CATALOGS = ("locations.json", "catalogs/de-drv.json", "catalogs/de-osm.json", "catalogs/at-oerv.json",
            "catalogs/at-osm.json", "catalogs/ch-swissrowing.json", "catalogs/ch-osm.json")

CLUSTER_KM = 3.0
REACH_KM = 25.0
MIN_KM, OPEN_KM = 3.0, 15.0
BIG_KM, BIG_HARBOUR_KM2 = 40, 0.1
CAP_UP_KM, CAP_DOWN_KM, CAP_CANAL_KM = 12.0, 8.0, 10.0
KM_SIGN_M = 1000.0
# A weir, mouth or line end on a side arm: the walk goes on past it this far along another arm of the same name.
BYPASS_M = 1000.0
WATERWAY_KINDS = ("river", "canal", "stream", "ditch", "drain", "weir", "dam", "lock_gate")
VERBOSE = False
# A side shorter than this that ends where the river joins another named water walks on into that water.
JOIN_ON_KM = 1.0
# Search box for the big rivers joining (their length is counted in it).
QUERY_KM = 80.0
GAP_M = 40.0  # line ends this close to another line of the same river are joined
BARRIERS = ("weir", "dam", "lock_gate", "waterfall")
# Widest water kept around the river line, and the band where the map has no water area.
MAX_HALF_WIDTH_M = 800.0
BAND_M = {"river": 20.0, "canal": 30.0}
OWN_HARBOUR_M = 300.0  # a harbour this close to a club's launch point belongs to its section
INCLUDE_NEAR_KM = 3.0
SIMPLIFY_M = 3.0
PICTURE_HALF_KM = 5.0  # satellite pictures of a river: about 10 km around the club
COMPASS = {"north": 0, "northeast": 45, "east": 90, "southeast": 135, "south": 180, "southwest": 225, "west": 270, "northwest": 315}


def km(a, b) -> float:
    return math.hypot((a[0] - b[0]) * 110.574, (a[1] - b[1]) * 111.32 * math.cos(math.radians(a[0])))


def slug(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.replace("ß", "ss")).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def same_water(osm_name: str, water: str) -> bool:
    """"Elbeseitenkanal" is the Elbe-Seitenkanal, "Vieux Rhin / Rhein" the Rhein."""
    key = slug(water).replace("-", "")
    return any(slug(part).replace("-", "") == key for part in [osm_name, *osm_name.split("/")] if part.strip())


def town(address: str) -> str:
    last = address.split(",")[-1].strip()
    return " ".join(w for w in last.split() if not w.isdigit()) or last


def groups() -> list[dict]:
    """River and canal clubs, in groups on the same water within CLUSTER_KM."""
    seen, clubs = set(), []
    for name in CATALOGS:
        path = ROOT / "data" / name
        if not path.exists():
            continue
        d = json.loads(path.read_text(encoding="utf-8"))
        lakes = {l["id"]: l for l in d.get("lakes", [])}
        for c in d["clubs"]:
            lake = lakes.get(c["lakeId"], {})
            if c["id"] in seen or not (lake.get("kind") == "river" or c["lakeId"].startswith("river-")):
                continue
            seen.add(c["id"])
            lp = c["launchPoint"]
            clubs.append({"id": c["id"], "lakeId": c["lakeId"], "water": lake.get("name", c["lakeId"]),
                          "country": c.get("country") or lake.get("country") or name.split("/")[-1][:2],
                          "town": town(c.get("address", "")), "at": (lp["lat"], lp["lon"])})
    out = []
    for c in clubs:
        for g in out:
            if g["lakeId"] == c["lakeId"] and any(km(p, c["at"]) < CLUSTER_KM for p in g["points"]):
                g["clubs"].append(c["id"])
                g["points"].append(c["at"])
                g["towns"].append(c["town"])
                break
        else:
            out.append({"lakeId": c["lakeId"], "water": c["water"], "country": c["country"], "clubs": [c["id"]],
                        "points": [c["at"]], "towns": [c["town"]]})
    for g in out:
        g["at"] = (sum(p[0] for p in g["points"]) / len(g["points"]), sum(p[1] for p in g["points"]) / len(g["points"]))
    return out


class Frame:
    """Metres east and north of a point, and back."""

    def __init__(self, lat: float, lon: float):
        self.lat0, self.lon0, self.k = lat, lon, math.cos(math.radians(lat))

    def m(self, lon: float, lat: float) -> tuple[float, float]:
        return ((lon - self.lon0) * 111_320 * self.k, (lat - self.lat0) * 110_574)

    def deg(self, x: float, y: float) -> tuple[float, float]:
        return (self.lon0 + x / (111_320 * self.k), self.lat0 + y / 110_574)

    def to_m(self, geom):
        return shapely.transform(geom, lambda a: (a - (self.lon0, self.lat0)) * (111_320 * self.k, 110_574))

    def to_deg(self, geom):
        return shapely.transform(geom, lambda a: a / (111_320 * self.k, 110_574) + (self.lon0, self.lat0))


class River:
    """The walkable graph of one named river or canal near a club."""

    def __init__(self, frame: Frame, ways: list[dict], name: str, els: list[dict], continues: set[int] = frozenset()):
        self.frame, self.name = frame, name
        self.coords, self.graph, way_of = {}, {}, {}
        self.kind = Counter()
        # Lock chambers, with the lock's name where the map has one ("lock Kleinmachnow").
        lock_ways = {e["id"]: f"lock {re.sub(r'^(Schleuse|Écluse de|Écluse du|Écluse)\s+', '', e['tags'].get('lock_name', ''))}".strip()
                     for e in els if e["type"] == "way" and e.get("tags", {}).get("lock") == "yes"}
        # The named lines, and the unnamed pieces of the same fairway between them (osm_extract).
        river = [w for w in ways if w["tags"].get("name", "") == name or w["id"] in continues]
        for w in river:
            self.kind[w["tags"]["waterway"]] += len(w["nodes"])
            for nid, p in zip(w["nodes"], w["geometry"]):
                self.coords[nid] = frame.m(p["lon"], p["lat"])
                way_of.setdefault(nid, set()).add(w["id"])
            for a, b in zip(w["nodes"], w["nodes"][1:]):
                d = math.dist(self.coords[a], self.coords[b])
                lock = lock_ways.get(w["id"], "")
                self.graph.setdefault(a, []).append((b, d, True, lock))
                self.graph.setdefault(b, []).append((a, d, False, lock))
        # Join gaps: a line end close to another node of the same river.
        cells: dict[tuple[int, int], list[int]] = {}
        for n in self.graph:
            cells.setdefault((int(self.coords[n][0] // GAP_M), int(self.coords[n][1] // GAP_M)), []).append(n)
        for n in [n for n, e in self.graph.items() if len(e) == 1]:
            x, y = self.coords[n]
            near = [m for i in (-1, 0, 1) for j in (-1, 0, 1) for m in cells.get((int(x // GAP_M) + i, int(y // GAP_M) + j), [])]
            best = min(((m, math.dist(self.coords[n], self.coords[m])) for m in near if not (way_of[m] & way_of[n])),
                       key=lambda t: t[1], default=None)
            if best and best[1] < GAP_M:
                m, d = best
                down = self.graph[n][0][2] is False
                self.graph[n].append((m, d, down, False))
                self.graph[m].append((n, d, not down, False))
        # Where other lines meet it, and which rivers join or branch off there.
        self.other_nodes, self.side_rivers = {}, {}
        for w in ways:
            if w in river:
                continue
            for nid in w["nodes"]:
                self.other_nodes[nid] = w["tags"].get("name", "") or w["tags"]["waterway"]
            if w["tags"].get("name") and w["tags"]["name"] != name:
                for nid, how in ((w["nodes"][-1], "joins"), (w["nodes"][0], "branches off")):
                    if nid in self.coords:
                        self.side_rivers.setdefault(nid, []).append((w["tags"]["name"], how))
        # Weirs, dams, locks and waterfalls.
        self.barrier_nodes, shapes = {}, []
        for e in els:
            tags = e.get("tags", {})
            kind = tags.get("waterway")
            if kind not in BARRIERS:
                continue
            label = f"{kind} {tags.get('name', '')}".strip()
            if e["type"] == "node":
                pt = Point(frame.m(e["lon"], e["lat"]))
                self.barrier_nodes[e["id"]] = label
                shapes.append((label, pt))
            elif e.get("geometry"):
                shapes.append((label, LineString([frame.m(p["lon"], p["lat"]) for p in e["geometry"]])))
                for nid in e.get("nodes", []):
                    self.barrier_nodes.setdefault(nid, label)
        self.shapes = shapes
        self.tree = STRtree([s for _, s in shapes]) if shapes else None

    @property
    def is_canal(self) -> bool:
        return self.kind["canal"] > self.kind["river"]

    def nearest(self, x: float, y: float) -> int | None:
        return min(self.coords, key=lambda n: math.dist(self.coords[n], (x, y)), default=None)

    def crosses(self, a: int, b: int) -> str | None:
        if b in self.barrier_nodes:
            return self.barrier_nodes[b]
        if self.tree is None:
            return None
        seg = LineString([self.coords[a], self.coords[b]])
        for i in self.tree.query(seg, predicate="dwithin", distance=25):
            label, shape = self.shapes[i]
            if shape.geom_type == "Point" or seg.intersects(shape):
                return label
        return None

    def walk(self, start: int, downstream: bool, ignore_barriers_m: float = 0.0) -> dict:
        """Dijkstra along the river one way, up to REACH_KM: distances, the tree
        of edges taken, where it stops (weir, lock, mouth, line end) and what it passes."""
        dist, prev, heap, stops, events, seen = {start: 0.0}, {}, [(0.0, start)], [], [], set()
        while heap:
            d, n = heapq.heappop(heap)
            if d > dist.get(n, math.inf):
                continue
            for other, how in self.side_rivers.get(n, ()):
                if (other, how) not in seen:
                    seen.add((other, how))
                    events.append((d, "river", f"{other} {how}", other))
            moves = [x for x in self.graph.get(n, []) if x[2] == downstream]
            if not moves:
                stops.append((d, "mouth" if n in self.other_nodes else "line end", self.other_nodes.get(n, "")))
            for m, w, _, lock in moves:
                label = lock or self.crosses(n, m)
                if label and d >= ignore_barriers_m:
                    stops.append((d + w / 2, "barrier", label))
                    continue
                nd = d + w
                if nd > REACH_KM * 1000:
                    continue
                if nd < dist.get(m, math.inf):
                    dist[m] = nd
                    prev[m] = n
                    heapq.heappush(heap, (nd, m))
        stops.sort()
        return {"dist": dist, "prev": prev, "stops": stops, "events": events, "downstream": downstream}

    def bearing(self, walk: dict, along_m: float = 1000.0) -> float | None:
        """Compass bearing from the start to the walk's point about along_m away."""
        if len(walk["dist"]) < 2:
            return None
        start = next(n for n, d in walk["dist"].items() if d == 0)
        n = min(walk["dist"], key=lambda k: abs(walk["dist"][k] - along_m))
        (x0, y0), (x1, y1) = self.coords[start], self.coords[n]
        return math.degrees(math.atan2(x1 - x0, y1 - y0)) % 360

    def lines(self, walk: dict, limit_m: float) -> list[LineString]:
        """The walked edges up to limit_m, each pointing downstream."""
        out = []
        for m, n in walk["prev"].items():
            d0, d1 = walk["dist"][n], walk["dist"][m]
            if d0 >= limit_m:
                continue
            a, b = self.coords[n], self.coords[m]
            if d1 > limit_m:
                t = (limit_m - d0) / max(d1 - d0, 1e-9)
                b = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            if a != b:
                out.append(LineString([a, b] if walk["downstream"] else [b, a]))
        return out


def side_limit(river: River, walk: dict, lengths: dict, harbours: list, cap_km: float, km_signs: list) -> tuple[float, str, str]:
    """Where one side of the section ends: (km, kind, what)."""
    reach = max(walk["dist"].values()) / 1000
    # Stops on side arms do not end the side while the main arm goes on.
    stops = [st for st in walk["stops"] if st[0] + BYPASS_M >= reach * 1000]
    barrier = next(((d, label) for d, kind, label in stops if kind == "barrier"), None)
    if barrier and " " not in barrier[1]:
        # A bare "lock_gate" or "weir" (e.g. on the lock canal beside a weir): the named weir or lock of the same step instead.
        barrier = next(((d, label) for d, kind, label in stops if kind == "barrier" and " " in label and d <= barrier[0] + 500), barrier)
    if barrier and barrier[0] <= REACH_KM * 1000:
        return round(barrier[0] / 1000, 2), "weir/lock", barrier[1]
    hard = []
    for d, kind, label, other in walk["events"]:
        if MIN_KM * 1000 <= d <= OPEN_KM * 1000 and (lengths.get(other) or 0) >= BIG_KM:
            hard.append((d / 1000, "river", label))
    for d, label, area in harbours:
        if MIN_KM * 1000 <= d <= OPEN_KM * 1000 and area >= BIG_HARBOUR_KM2:
            hard.append((d / 1000, "harbour", label))
    for d, kind, label in stops:
        if kind == "mouth" and MIN_KM * 1000 <= d <= OPEN_KM * 1000:
            hard.append((d / 1000, "mouth", f"joins {label}"))
    if hard:
        d, kind, label = min(hard)
        return round(d, 2), kind, label
    end = next(((d, kind, label) for d, kind, label in stops if kind in ("mouth", "line end")), None)
    if end and end[0] / 1000 < cap_km:
        return round(end[0] / 1000, 2), end[1], end[2]
    cap = min(cap_km, reach)
    # Round to a river km sign near the cap.
    signs = []
    if km_signs:
        nodes = list(walk["dist"])
        tree = STRtree([Point(river.coords[n]) for n in nodes])
        for label, xy in km_signs:
            i = tree.query_nearest(Point(xy), max_distance=150)
            if len(i):
                d = walk["dist"][nodes[i[0]]]
                if abs(d - cap * 1000) <= KM_SIGN_M:
                    signs.append((abs(d - cap * 1000), d, label))
    if signs:
        _, d, label = min(signs)
        return round(d / 1000, 2), "km sign", f"river km {label}"
    return round(cap, 2), "cap", ""


def harbours_along(river: River, walk: dict, harbour_polys: list) -> list[tuple[float, str, float]]:
    """(distance, name, km²) of the harbours within 150 m of the walked river."""
    out = []
    if not harbour_polys:
        return out
    nodes = list(walk["dist"])
    tree = STRtree([Point(river.coords[n]) for n in nodes])
    for name, poly in harbour_polys:
        near = tree.query(poly, predicate="dwithin", distance=150)
        if len(near):
            out.append((min(walk["dist"][nodes[i]] for i in near), f"harbour {name}", round(poly.area / 1e6, 3)))
    return out


def outline(frame: Frame, center_lines: list[LineString], areas: list[tuple[dict, object]], clubs_m: list[tuple[float, float]],
            canal: bool, include_areas: list[str]):
    """The section's water: map areas along the river line, cut square at its
    ends, plus a band where the map has none, plus the club's own harbour."""
    merged = line_merge(MultiLineString(center_lines), directed=True) if len(center_lines) > 1 else center_lines[0]
    corridor = merged.buffer(MAX_HALF_WIDTH_M, cap_style="flat", join_style="round")
    touch = merged.buffer(5)
    w, s, e, n = frame.to_deg(corridor).bounds
    keep, own = [], []
    for tags, geom in areas:
        gw, gs, ge, gn = geom.bounds
        if gw > e or ge < w or gs > n or gn < s:
            continue
        g = frame.to_m(geom).buffer(0)
        harbour = tags.get("water") in ("harbour", "basin") or tags.get("landuse") == "harbour"
        river_area = tags.get("water") in ("river", "canal") or tags.get("waterway") == "riverbank"
        named = tags.get("name") in include_areas and not river_area
        if harbour or named:
            near_club = any(g.distance(Point(p)) <= OWN_HARBOUR_M for p in clubs_m)
            if near_club or (named and g.intersects(corridor)):
                own.append(g)
            continue
        if g.intersects(touch):
            keep.append(g)
    water = unary_union(keep).intersection(corridor) if keep else Polygon()
    # Only the pieces the river line runs through (no side arms cut off by the corridor).
    pieces = [p for p in getattr(water, "geoms", [water]) if not p.is_empty and p.intersects(touch)]
    band = merged.buffer(BAND_M["canal" if canal else "river"] / 2, cap_style="flat")
    shape = unary_union(pieces + [band] + own).buffer(0)
    return shape.simplify(SIMPLIFY_M, preserve_topology=True), merged


def build(ex: Extract, g: dict, override: dict) -> dict:
    lat, lon = g["at"]
    frame = Frame(lat, lon)
    data = ex.query(lat, lon, QUERY_KM, g["water"])
    els = data["elements"]
    ways = [e for e in els if e["type"] == "way" and e.get("tags", {}).get("waterway") in ("river", "canal") and e.get("geometry")]
    if not ways:
        return {"error": "no river line found"}
    clubs_m = [frame.m(p[1], p[0]) for p in g["points"]]

    def way_dist(w):
        pts = [frame.m(p["lon"], p["lat"]) for p in w["geometry"]]
        return LineString(pts).distance(Point(0, 0)) if len(pts) > 1 else 1e9

    include = override.get("include") or []
    own = [w for w in ways if same_water(w["tags"].get("name", ""), g["water"]) and way_dist(w) < 1500]
    extra = [w for w in ways if w["tags"].get("name") in include and way_dist(w) < 1500]
    named = [w for w in ways if w["tags"].get("name") and way_dist(w) < 1500]
    if not (own or extra or named):
        # The launch point is off its water: say where the water is, for a hand fix.
        far = [w for w in ways if same_water(w["tags"].get("name", ""), g["water"])]
        if far:
            w = min(far, key=way_dist)
            line = LineString([frame.m(p["lon"], p["lat"]) for p in w["geometry"]])
            at = line.interpolate(line.project(Point(0, 0)))
            lon_, lat_ = frame.deg(at.x, at.y)
            return {"error": f"launch point {way_dist(w) / 1000:.1f} km from the {g['water']}; nearest point of it {lat_:.5f}, {lon_:.5f}"}
    nearest = min(own or extra or named or ways, key=way_dist)
    if VERBOSE:
        near = sorted({(round(way_dist(w)), w["tags"].get("name", ""), w["tags"]["waterway"]) for w in ways if way_dist(w) < 1000})[:8]
        print(f"  {g['water']}: lines within 1 km {near}", flush=True)
    name = nearest["tags"].get("name", "")
    if not name:
        return {"error": "the nearest river line has no name"}
    lengths = data.get("lengths", {})
    km_signs = [(e["tags"].get("distance", ""), frame.m(e["lon"], e["lat"])) for e in els if e["type"] == "node" and e.get("tags", {}).get("waterway") == "milestone"]
    harbour_polys = []
    for e in els:
        if e.get("harbour") and len(e.get("geometry", [])) >= 4:
            t = e.get("tags", {})
            harbour_polys.append((t.get("name") or t.get("water") or t.get("landuse"), Polygon([frame.m(p["lon"], p["lat"]) for p in e["geometry"]]).buffer(0)))

    allowed = [COMPASS[w] for w in re.split(r"\s+and\s+|,\s*", override.get("direction", "")) if w in COMPASS]
    rivers = [name] + [n for n in include if n != name]
    lines, sides, canal = [], {}, False
    carry = {}  # joined water -> the side it carries on
    carry_at, carry_km = {}, {}  # where the side ran into it, and how far from the club that is
    for i, river_name in enumerate(rivers):
        river_ways = ways if i == 0 else ex.lines_named(river_name, lat, lon, REACH_KM + 2)
        if not any(w["tags"].get("name") == river_name for w in river_ways):
            continue
        river = River(frame, river_ways, river_name, els, data.get("continues", set()) if i == 0 else set())
        starts = [river.nearest(*p) for p in clubs_m]
        starts = [s for s in starts if s is not None and math.hypot(*river.coords[s]) <= INCLUDE_NEAR_KM * 1000]
        if river_name in carry_at:
            # A water the side ran into: walk on from where it did.
            starts = [river.nearest(*carry_at[river_name])]
        if not starts:
            continue
        start = min(starts, key=lambda s: math.hypot(*river.coords[s]))
        canal = canal or (i == 0 and river.is_canal)
        for downstream in (True, False):
            # Where a weir or lock sits right at the boathouse, the owner named the side the club rows on.
            walk = river.walk(start, downstream, ignore_barriers_m=500 if allowed else 0.0)
            bearing = river.bearing(walk)
            behind = None
            if allowed and bearing is not None and not any(abs((bearing - a + 180) % 360 - 180) <= 67.5 for a in allowed):
                # The other side counts only for the water right in front of the boathouse, where the owner asked for it.
                behind = override.get("behindKm")
                if not behind:
                    continue
            key = "down" if downstream else "up"
            cap = CAP_CANAL_KM if river.is_canal else (CAP_DOWN_KM if downstream else CAP_UP_KM)
            limit = side_limit(river, walk, lengths, harbours_along(river, walk, harbour_polys), cap, km_signs)
            if behind and limit[0] > behind:
                limit = (behind, "in front", "in front of the boathouse")
            if VERBOSE:
                print(f"  {river_name} {key}: reach {max(walk['dist'].values()) / 1000:.2f} km, stops "
                      + "; ".join(f"{d / 1000:.2f} {kind} {label}".strip() for d, kind, label in walk["stops"][:12]), flush=True)
            offset = carry_km.get(river_name, 0.0) if carry.get(river_name) == key else 0.0
            end_xy = river.coords[min(walk["dist"], key=lambda n: abs(walk["dist"][n] - limit[0] * 1000))]
            # Ends right where it runs into another named water (an arm with its own name): walk on in that one.
            joined = limit[2] if limit[1] == "mouth" else ""
            if (limit[0] < JOIN_ON_KM and joined and joined not in rivers and joined not in WATERWAY_KINDS
                    and len(rivers) < len(include) + 3):
                rivers.append(joined)
            elif limit[1] in ("mouth", "line end") and (i == 0 or carry.get(river_name) == key):
                # Or into a water the overrides include for this club, however far from it.
                joined = next((n for n in rivers[i + 1:] if n not in carry and any(
                    math.dist(frame.m(p["lon"], p["lat"]), end_xy) < 60
                    for w in ex.lines_named(n, lat, lon, REACH_KM + 2) for p in w["geometry"])), "")
            else:
                joined = ""
            if joined in rivers[i + 1:] and joined not in carry:
                carry[joined], carry_at[joined], carry_km[joined] = key, end_xy, offset + limit[0]
            lines += river.lines(walk, limit[0] * 1000)
            if i == 0 or carry.get(river_name) == key:
                end = next((n for n in walk["dist"] if abs(walk["dist"][n] - limit[0] * 1000) < 1), None)
                end = end or min(walk["dist"], key=lambda n: abs(walk["dist"][n] - limit[0] * 1000))
                sides[key] = {"km": round(offset + limit[0], 2), "end": limit[1], "what": limit[2],
                              "at": [round(v, 5) for v in frame.deg(*river.coords[end])[::-1]]}
    if not lines:
        return {"error": f"no walkable line of {name} near the club"}
    k = math.cos(math.radians(lat))
    reach_deg = (REACH_KM + 2) / 110.574
    areas = ex.areas(lat - reach_deg, lon - reach_deg / k, lat + reach_deg, lon + reach_deg / k)
    shape, flow = outline(frame, lines, areas, clubs_m, canal, include)
    return {"river": name, "kind": "canal" if canal else "river", "shape": frame.to_deg(shape), "flow": frame.to_deg(flow.simplify(10)),
            "lengthKm": round(sum(l.length for l in lines) / 1000, 1), **sides}


def geojson(section_id: str, name: str, shape, flow) -> dict:
    def rounded(geom):
        return json.loads(json.dumps(mapping(geom)), parse_float=lambda v: round(float(v), 5))

    return {"type": "FeatureCollection", "features": [
        {"type": "Feature", "properties": {"id": section_id, "name": name, "source": "© OpenStreetMap contributors, ODbL"}, "geometry": rounded(shape)},
        {"type": "Feature", "properties": {"role": "flow", "note": "river line, pointing downstream"}, "geometry": rounded(flow)},
    ]}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("lines")
    ap.add_argument("water")
    ap.add_argument("--only", default="", help="comma-separated club ids: rebuild only their sections")
    ap.add_argument("--verbose", action="store_true", help="print each side's walk")
    args = ap.parse_args()
    global VERBOSE
    VERBOSE = args.verbose
    overrides = {cid: o for country in json.loads(OVERRIDES.read_text(encoding="utf-8")).values() if isinstance(country, dict) for cid, o in country.items()}
    ex = Extract(args.lines, args.water, lakes=True)
    ex.all_milestones = True
    old = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {"sections": []}
    only = set(filter(None, args.only.split(",")))
    sections, used_ids, problems = [], set(), []
    kept = {c: s for s in old["sections"] for c in s["clubs"]}
    for g in groups():
        if only and not (only & set(g["clubs"])):
            if g["clubs"][0] in kept and kept[g["clubs"][0]]["id"] not in used_ids:
                sections.append(kept[g["clubs"][0]])
                used_ids.add(kept[g["clubs"][0]]["id"])
            continue
        override = {}
        for c in g["clubs"]:
            for key, value in overrides.get(c, {}).items():
                override.setdefault(key, value)
        place = Counter(g["towns"]).most_common(1)[0][0]
        section_id = base = f"{g['lakeId']}-{slug(place)}"
        n = 2
        while section_id in used_ids:
            section_id, n = f"{base}-{n}", n + 1
        try:
            r = build(ex, g, override)
        except Exception as e:  # one broken river must not stop the others
            r = {"error": f"{type(e).__name__}: {str(e)[:200]}"}
        if "error" in r:
            problems.append((g["clubs"], r["error"]))
            print(f"PROBLEM {g['lakeId']} {g['clubs']}: {r['error']}", flush=True)
            continue
        used_ids.add(section_id)
        lat, lon = g["at"]
        dlat, dlon = PICTURE_HALF_KM / 110.574, PICTURE_HALF_KM / (111.32 * math.cos(math.radians(lat)))
        w, s, e, nb = r["shape"].bounds
        box = [round(max(w, lon - dlon), 5), round(max(s, lat - dlat), 5), round(min(e, lon + dlon), 5), round(min(nb, lat + dlat), 5)]
        section = {"id": section_id, "water": g["lakeId"], "name": g["water"], "river": r["river"], "waterway": r["kind"],
                   "country": g["country"], "place": place, "center": {"lat": round(lat, 5), "lon": round(lon, 5)},
                   "clubs": g["clubs"], "lengthKm": r["lengthKm"], "up": r.get("up"), "down": r.get("down"), "pictureBox": box}
        sections.append(section)
        (OUTLINES / f"{section_id}.geojson").write_text(
            json.dumps(geojson(section_id, g["water"], r["shape"], r["flow"]), ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        ends = " / ".join(f"{k} {v['km']} km {v['end']} {v['what']}".strip() for k, v in (("up", r.get("up")), ("down", r.get("down"))) if v)
        print(f"SECTION {section_id} ({len(g['clubs'])} clubs, {r['lengthKm']} km): {ends}", flush=True)
    for s in old["sections"]:
        if s["id"] not in used_ids and not only:
            (OUTLINES / f"{s['id']}.geojson").unlink(missing_ok=True)
    sections.sort(key=lambda s: s["id"])
    OUT.write_text(json.dumps({
        "comment": "River sections of the river and canal clubs, built by scripts/build_river_sections.py from OpenStreetMap "
                   "(© OpenStreetMap contributors, ODbL); outlines in data/outlines/<id>.geojson. up/down: where the stretch "
                   "ends each way (km from the club, what ends it: weir/lock, river, harbour, mouth, line end, km sign, cap).",
        "sections": sections}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    lengths = sorted(s["lengthKm"] for s in sections)
    print(f"{len(sections)} sections for {sum(len(s['clubs']) for s in sections)} clubs; length median "
          f"{lengths[len(lengths) // 2] if lengths else 0} km, max {lengths[-1] if lengths else 0} km; {len(problems)} problems")


if __name__ == "__main__":
    main()
