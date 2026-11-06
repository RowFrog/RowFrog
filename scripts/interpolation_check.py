"""Checks how well ways of filling a lake between its forecast points match a
known field, and whether they inflate or deflate the values (thread "Lake
view tile", 6 Nov 2026; the owner picked natural neighbour).

  python3 scripts/interpolation_check.py sample [lakes...]
      Made-up fields with a known answer at every square.
  python3 scripts/interpolation_check.py icon-d2 [lakes...]
      The latest ICON-D2 run from DWD open data: the model's own 2.2 km field
      at every square is the answer; the lake's forecast points get the model
      value at their spot, as Open-Meteo gives them. Needs eccodes and
      network, so it runs as the "Interpolation check" workflow.

Methods: nearest point (today), inverse distance, triangles (linear) and
natural neighbour. Per method and value: bias (mean of blended minus true;
above 0 inflates, below 0 deflates), mean and 95th percentile error, bias on
the strongest tenth of squares, squares outside the range of the points, and
squares whose light differs from the true light.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from rowfrog import interpolate, lake_view, outlines

LAKES = ["starnberger-see", "ammersee", "waginger-see", "forggensee", "simssee", "bodensee", "zuerichsee",
         "thunersee", "hallwilersee", "wolfgangsee", "woerthersee", "grosser-wannsee", "maschsee", "baldeneysee",
         "aussenalster"]
METHODS = ["nearest", "idw", "triangles", "natural"]


def local(lon: float, lat: float, lon0: float, lat0: float) -> tuple[float, float]:
    r = 6_371_000.0
    return math.radians(lon - lon0) * r * math.cos(math.radians(lat0)), math.radians(lat - lat0) * r


# ---- the methods, as weights per square ------------------------------------------------------

def delaunay(pts: list[tuple[float, float]]) -> list[tuple[int, int, int]]:
    n = len(pts)
    cx = sum(p[0] for p in pts) / n
    cy = sum(p[1] for p in pts) / n
    big = 1e7
    allp = pts + [(cx - big, cy - big), (cx + big, cy - big), (cx, cy + big)]
    tris = [(n, n + 1, n + 2)]

    def circ(t):
        (ax, ay), (bx, by), (qx, qy) = (allp[i] for i in t)
        d = 2 * (ax * (by - qy) + bx * (qy - ay) + qx * (ay - by))
        ux = ((ax * ax + ay * ay) * (by - qy) + (bx * bx + by * by) * (qy - ay) + (qx * qx + qy * qy) * (ay - by)) / d
        uy = ((ax * ax + ay * ay) * (qx - bx) + (bx * bx + by * by) * (ax - qx) + (qx * qx + qy * qy) * (bx - ax)) / d
        return ux, uy, (ax - ux) ** 2 + (ay - uy) ** 2

    for k in range(n):
        px, py = allp[k]
        bad, keep = [], []
        for t in tris:
            ux, uy, r2 = circ(t)
            (bad if (px - ux) ** 2 + (py - uy) ** 2 < r2 else keep).append(t)
        edges: dict[tuple[int, int], int] = {}
        for t in bad:
            for e in range(3):
                a, b = t[e], t[(e + 1) % 3]
                key = (min(a, b), max(a, b))
                edges[key] = edges.get(key, 0) + 1
        tris = keep + [(a, b, k) for (a, b), c in edges.items() if c == 1]
    return [t for t in tris if max(t) < n]


class Triangles:
    def __init__(self, pts):
        self.pts = pts
        self.tris = delaunay(pts) if len(pts) >= 3 else []
        count: dict[tuple[int, int], int] = {}
        for t in self.tris:
            for e in range(3):
                a, b = t[e], t[(e + 1) % 3]
                key = (min(a, b), max(a, b))
                count[key] = count.get(key, 0) + 1
        self.hull = [k for k, c in count.items() if c == 1]

    def weights(self, x, y):
        p = self.pts
        for a, b, c in self.tris:
            (ax, ay), (bx, by), (cx, cy) = p[a], p[b], p[c]
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(det) < 1e-9:
                continue
            l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / det
            l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / det
            l3 = 1 - l1 - l2
            if min(l1, l2, l3) >= -1e-9:
                return {a: l1, b: l2, c: l3}
        if not self.hull:
            return nearest(p, x, y)
        best = None
        for a, b in self.hull:
            (ax, ay), (bx, by) = p[a], p[b]
            dx, dy = bx - ax, by - ay
            t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
            d = (ax + t * dx - x) ** 2 + (ay + t * dy - y) ** 2
            if best is None or d < best[0]:
                best = (d, a, b, t)
        _, a, b, t = best
        return {a: 1 - t, b: t} if a != b else {a: 1.0}


def nearest(pts, x, y):
    return {min(range(len(pts)), key=lambda i: (pts[i][0] - x) ** 2 + (pts[i][1] - y) ** 2): 1.0}


def idw(pts, x, y):
    w = {}
    for i, (px, py) in enumerate(pts):
        d2 = (px - x) ** 2 + (py - y) ** 2
        if d2 < 1e-6:
            return {i: 1.0}
        w[i] = 1 / d2
    s = sum(w.values())
    return {i: v / s for i, v in w.items()}


def all_weights(pts, squares):
    xs, ys = [p[0] for p in pts] + [s[0] for s in squares], [p[1] for p in pts] + [s[1] for s in squares]
    pad = 2 * lake_view.SAMPLE_SPACING_M
    nn = interpolate.NaturalNeighbours(pts, (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad))
    tri = Triangles(pts)
    return {
        "nearest": [nearest(pts, *s) for s in squares],
        "idw": [idw(pts, *s) for s in squares],
        "triangles": [tri.weights(*s) for s in squares],
        "natural": [nn.weights(s) for s in squares],
    }


# ---- scoring ---------------------------------------------------------------------------------

def light(kind, v):
    if kind == "wind":
        return 2 if v >= 8 else 1 if v >= 5.5 else 0
    if kind == "gust":
        return 2 if v >= 10.3 else 1 if v >= 8 else 0
    return 2 if v < 500 else 1 if v <= 1000 else 0


def score(kind, truth, inputs, weights):
    blend = interpolate.blend_visibility if kind == "vis" else interpolate.blend
    est = [blend(w, inputs) for w in weights]
    lo, hi = min(inputs), max(inputs)
    if kind == "vis":  # errors on a log scale: 0.1 = about 10 %
        t, e = [math.log(max(v, 1)) for v in truth], [math.log(max(v, 1)) for v in est]
    else:
        t, e = truth, est
    err = [a - b for a, b in zip(e, t)]
    n = len(err)
    top = sorted(range(n), key=lambda i: -t[i] if kind != "vis" else t[i])[: max(1, n // 10)]
    return {
        "bias": sum(err) / n,
        "mae": sum(abs(x) for x in err) / n,
        "p95": sorted(abs(x) for x in err)[int(0.95 * (n - 1))],
        "bias_strongest": sum(err[i] for i in top) / len(top),
        "outside": sum(1 for v in est if v < lo - 1e-6 or v > hi + 1e-6) / n,
        "light_wrong": sum(1 for a, b in zip(truth, est) if light(kind, a) != light(kind, b)) / n,
        "max_est": max(est), "max_true": max(truth), "max_points": hi,
    }


def merge(rows):
    keys = rows[0].keys()
    return {k: sum(r[k] for r in rows) / len(rows) for k in keys}


def report(results, title):
    print(f"\n## {title}\n")
    for kind, label, unit in (("wind", "Wind speed", "m/s"), ("gust", "Gusts", "m/s"), ("vis", "Visibility", "log")):
        if kind not in results:
            continue
        print(f"### {label} ({unit})\n")
        print("| Method | Bias | Mean error | 95 % error | Bias, strongest tenth | Outside points' range | Light wrong |")
        print("|---|---|---|---|---|---|---|")
        for m in METHODS:
            r = merge(results[kind][m])
            print(f"| {m} | {r['bias']:+.3f} | {r['mae']:.3f} | {r['p95']:.3f} | {r['bias_strongest']:+.3f} "
                  f"| {100 * r['outside']:.1f} % | {100 * r['light_wrong']:.1f} % |")
        print()


# ---- sample fields ---------------------------------------------------------------------------

def sample_fields(sq, lake_seed):
    """Made-up fields with a known value at every square, in local metres."""
    import random
    rnd = random.Random(lake_seed)
    out = []
    for k in range(12):
        ang = rnd.uniform(0, math.pi)
        wl = rnd.uniform(3000, 12000)
        ph = rnd.uniform(0, 2 * math.pi)
        base = rnd.uniform(3, 7)
        amp = rnd.uniform(1, 3)
        front = rnd.random() < 0.5
        cx, cy = rnd.choice(sq)
        fog_r = rnd.uniform(1000, 4000)

        def wind(x, y, ang=ang, wl=wl, ph=ph, base=base, amp=amp, front=front, cx=cx, cy=cy):
            s = x * math.cos(ang) + y * math.sin(ang)
            if front:  # a gust front: a sharp step about 1 km wide
                return base + amp * math.tanh((s - (cx * math.cos(ang) + cy * math.sin(ang))) / 500)
            return base + amp * math.sin(2 * math.pi * s / wl + ph)

        def vis(x, y, cx=cx, cy=cy, fog_r=fog_r):
            d = math.dist((x, y), (cx, cy))
            return math.exp(math.log(200) + (math.log(15000) - math.log(200)) * min(1, (d / fog_r) ** 2))

        out.append((wind, lambda x, y, w=wind: 1.45 * w(x, y), vis))
    return out


def lake_setup(lake_id):
    rings = outlines.load(lake_id)
    if not rings:
        return None
    grid = lake_view.build_grid(rings)
    lon0 = sum(p[0] for p in grid.points) / len(grid.points)
    lat0 = sum(p[1] for p in grid.points) / len(grid.points)
    sq = [local(lon, lat, lon0, lat0) for lon, lat in grid.points]
    pts = [local(lon, lat, lon0, lat0) for lon, lat in grid.samples]
    return grid, sq, pts


def run_sample(lakes):
    results = {k: {m: [] for m in METHODS} for k in ("wind", "gust", "vis")}
    for n, lake_id in enumerate(lakes):
        setup = lake_setup(lake_id)
        if not setup or len(setup[2]) < 3:
            continue
        _grid, sq, pts = setup
        weights = all_weights(pts, sq)
        print(f"{lake_id}: {len(sq)} squares, {len(pts)} forecast points", file=sys.stderr)
        for wind, gust, vis in sample_fields(sq, n):
            for kind, f in (("wind", wind), ("gust", gust), ("vis", vis)):
                truth = [f(*s) for s in sq]
                inputs = [f(*p) for p in pts]
                for m in METHODS:
                    results[kind][m].append(score(kind, truth, inputs, weights[m]))
    report(results, "Made-up fields")


# ---- ICON-D2 ---------------------------------------------------------------------------------

def run_icon_d2(lakes, steps=(3, 6, 9, 12, 15, 18, 21, 24, 30, 36, 42, 48)):
    import dataclasses
    from datetime import datetime, timezone

    import httpx
    import numpy as np
    from rowfrog.sources import icon_d2_maps as d2

    setups = {}
    for lake_id in lakes:
        s = lake_setup(lake_id)
        if s and len(s[2]) >= 3:
            setups[lake_id] = (s, all_weights(s[2], s[1]))
            print(f"{lake_id}: {len(s[1])} squares, {len(s[2])} forecast points", file=sys.stderr)

    def at(grid, lon, lat):  # bilinear on the model's regular grid
        g = grid
        fx = (lon - g.lon0) / g.dlon
        fy = (lat - g.lat0) / g.dlat
        i, j = math.floor(fx), math.floor(fy)
        tx, ty = fx - i, fy - j
        v = g.values
        return float((1 - tx) * (1 - ty) * v[j, i] + tx * (1 - ty) * v[j, i + 1] + (1 - tx) * ty * v[j + 1, i] + tx * ty * v[j + 1, i + 1])

    def nearest_node(grid, lon, lat):  # what a forecast point gets
        g = grid
        return float(g.values[round((lat - g.lat0) / g.dlat), round((lon - g.lon0) / g.dlon)])

    results = {k: {m: [] for m in METHODS} for k in ("wind", "gust", "vis")}
    with httpx.Client(timeout=60, follow_redirects=True) as client:
        run = d2.latest_run(client, datetime.now(timezone.utc))
        print(f"ICON-D2 run {run:%Y-%m-%d %H} UTC", file=sys.stderr)
        for step in steps:
            fields = {}
            for var in ("u_10m", "v_10m", "vmax_10m", "vis"):
                fields[var] = d2._decode(d2._fetch(client, d2._url(run, var, step)))
            wind_grid = dataclasses.replace(fields["u_10m"], values=np.hypot(fields["u_10m"].values, fields["v_10m"].values))
            for lake_id, ((grid, sq, pts), weights) in setups.items():
                for kind, g in (("wind", wind_grid), ("gust", fields["vmax_10m"]), ("vis", fields["vis"])):
                    truth = [at(g, lon, lat) for lon, lat in grid.points]
                    inputs = [nearest_node(g, lon, lat) for lon, lat in grid.samples]
                    if kind == "vis":
                        truth = [min(max(v, 1.0), 50000.0) for v in truth]
                        inputs = [min(max(v, 1.0), 50000.0) for v in inputs]
                    for m in METHODS:
                        results[kind][m].append(score(kind, truth, inputs, weights[m]))
            print(f"step {step} done", file=sys.stderr)
    report(results, f"ICON-D2 run {run:%Y-%m-%d %H} UTC, {len(steps)} hours, {len(setups)} lakes")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "sample"
    lakes = sys.argv[2:] or LAKES
    if mode == "sample":
        run_sample(lakes)
    elif mode == "icon-d2":
        run_icon_d2(lakes)
    else:
        sys.exit(json.dumps({"error": f"unknown mode {mode}"}))
