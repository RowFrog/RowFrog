#!/usr/bin/env python3
"""Research only: answers the river and water questions from downloaded
OpenStreetMap extracts instead of the busy public Overpass servers.

The workflow (river-section-survey.yml) downloads the Geofabrik extracts for
Germany, Austria and Switzerland and filters them with osmium into
  lines.osm.pbf        river and canal lines, weirs, dams, locks, waterfalls, river km signs
  water.geojsonseq     water areas (natural=water, landuse=reservoir, riverbank)
This module loads them and hands river_section_survey.survey() the same kind
of elements an Overpass query would. Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import json
import math
from collections import defaultdict

import osmium
from shapely.geometry import shape

CELL = 0.05  # degrees, for the grid index
BARRIERS = ("weir", "dam", "lock_gate", "waterfall")


def _cells(s, w, n, e):
    for i in range(int(math.floor(s / CELL)), int(math.floor(n / CELL)) + 1):
        for j in range(int(math.floor(w / CELL)), int(math.floor(e / CELL)) + 1):
            yield i, j


class _Lines(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways, self.nodes = {}, {}

    def node(self, n):
        t = dict(n.tags)
        if t.get("waterway") in BARRIERS + ("milestone",):
            self.nodes[n.id] = {"type": "node", "id": n.id, "lat": n.location.lat, "lon": n.location.lon, "tags": t}

    def way(self, w):
        t = dict(w.tags)
        if not (t.get("waterway") in ("river", "canal") + BARRIERS or t.get("lock") == "yes"):
            return
        try:
            geom = [{"lat": nd.location.lat, "lon": nd.location.lon} for nd in w.nodes]
        except osmium.InvalidLocationError:
            return
        self.ways[w.id] = {"type": "way", "id": w.id, "tags": t, "nodes": [nd.ref for nd in w.nodes], "geometry": geom}


class Extract:
    def __init__(self, lines_pbf: str, water_seq: str | None = None):
        h = _Lines()
        h.apply_file(lines_pbf, locations=True, idx="flex_mem")
        self.ways, self.nodes = h.ways, h.nodes
        self.way_grid, self.node_grid = defaultdict(set), defaultdict(set)
        self.ways_of_node = defaultdict(list)
        for w in self.ways.values():
            lats = [p["lat"] for p in w["geometry"]]
            lons = [p["lon"] for p in w["geometry"]]
            for c in _cells(min(lats), min(lons), max(lats), max(lons)):
                self.way_grid[c].add(w["id"])
            if w["tags"].get("waterway") in ("river", "canal"):
                for nid in w["nodes"]:
                    self.ways_of_node[nid].append(w["id"])
        for n in self.nodes.values():
            self.node_grid[next(_cells(n["lat"], n["lon"], n["lat"], n["lon"]))].add(n["id"])
        self.water = []  # (tags, geometry) of river/canal areas (widths) and harbours
        self.water_grid = defaultdict(list)
        if water_seq:
            for f in read_water(water_seq):
                t = f["properties"]
                if t.get("waterway") == "riverbank" or t.get("water") in ("river", "canal", "harbour", "basin") or t.get("landuse") == "harbour":
                    g = shape(f["geometry"])
                    k = len(self.water)
                    self.water.append((t, g))
                    w, s, e, n = g.bounds
                    for c in _cells(s, w, n, e):
                        self.water_grid[c].append(k)
        print(f"extract: {len(self.ways)} lines, {len(self.nodes)} barrier/km nodes, {len(self.water)} river areas", flush=True)

    def query(self, lat: float, lon: float, max_km: float) -> dict:
        """Like river_section_survey.query(): the waters near the point, the
        named river and the lines touching it, and weirs/locks in a box."""
        k = math.cos(math.radians(lat))
        near_d = 1.5 / 110.574
        near = {wid for c in _cells(lat - near_d, lon - near_d / k, lat + near_d, lon + near_d / k) for wid in self.way_grid[c]}

        def dist_km(p):
            return math.hypot((p["lat"] - lat) * 110.574, (p["lon"] - lon) * 111.32 * k)

        lines = [self.ways[w] for w in near if self.ways[w]["tags"].get("waterway") in ("river", "canal")]
        lines = [w for w in lines if min(dist_km(p) for p in w["geometry"]) <= 1.5]
        els = {("way", w["id"]): w for w in lines}
        dlat, dlon = (max_km + 2) / 110.574, (max_km + 2) / (111.32 * k)
        box = list(_cells(lat - dlat, lon - dlon, lat + dlat, lon + dlon))
        if lines:
            nearest = min(lines, key=lambda w: min(dist_km(p) for p in w["geometry"]))
            name = nearest["tags"].get("name", "")
            if name:
                for c in box:
                    for wid in self.way_grid[c]:
                        w = self.ways[wid]
                        if w["tags"].get("name") == name and w["tags"].get("waterway") in ("river", "canal"):
                            els[("way", wid)] = w
                named = [w for w in els.values() if w["tags"].get("name") == name]
                for w in named:
                    for nid in w["nodes"]:
                        for other in self.ways_of_node.get(nid, ()):
                            els.setdefault(("way", other), self.ways[other])
        for c in box:
            for wid in self.way_grid[c]:
                w = self.ways[wid]
                if w["tags"].get("waterway") in BARRIERS or w["tags"].get("lock") == "yes":
                    els[("way", wid)] = w
            for nid in self.node_grid[c]:
                n = self.nodes[nid]
                if n["tags"].get("waterway") in BARRIERS or dist_km(n) <= 2:
                    els[("node", nid)] = n
        # River areas near the point, as closed ways for the width.
        nd = 1.5 / 110.574
        for c in _cells(lat - nd, lon - nd / k, lat + nd, lon + nd / k):
            for i in self.water_grid[c]:
                t, g = self.water[i]
                if t.get("water") in ("harbour", "basin") or t.get("landuse") == "harbour":
                    continue
                for j, poly in enumerate(getattr(g, "geoms", [g])):
                    ring = [{"lat": y, "lon": x} for x, y in poly.exterior.coords]
                    els[("area", i, j)] = {"type": "way", "id": -i, "tags": t, "nodes": [], "geometry": ring}
        # Harbours along the whole reach, and how long each touching river is
        # (km of its named lines in the box), to tell big tributaries from brooks.
        for c in box:
            for i in self.water_grid[c]:
                t, g = self.water[i]
                if (t.get("water") in ("harbour", "basin") or t.get("landuse") == "harbour") and ("harbour", i) not in els:
                    for j, poly in enumerate(getattr(g, "geoms", [g])):
                        ring = [{"lat": y, "lon": x} for x, y in poly.exterior.coords]
                        els[("harbour", i, j)] = {"type": "area", "id": -i, "tags": t, "harbour": True, "geometry": ring}
                    els[("harbour", i)] = {"type": "marker", "tags": {}}
        names = {w["tags"].get("name") for w in els.values() if w["type"] == "way" and w["tags"].get("waterway") in ("river", "canal")}
        lengths = defaultdict(float)
        counted = set()
        for c in box:
            for wid in self.way_grid[c]:
                w = self.ways[wid]
                n = w["tags"].get("name")
                if n in names and wid not in counted and w["tags"].get("waterway") in ("river", "canal"):
                    counted.add(wid)
                    g = w["geometry"]
                    lengths[n] += sum(math.hypot((a["lat"] - b["lat"]) * 110.574, (a["lon"] - b["lon"]) * 111.32 * k) for a, b in zip(g, g[1:]))
        return {"elements": [e for e in els.values() if e["type"] != "marker"], "lengths": {n: round(v) for n, v in lengths.items()}}


def read_water(path: str):
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip().lstrip("\x1e")
            if line:
                yield json.loads(line)
