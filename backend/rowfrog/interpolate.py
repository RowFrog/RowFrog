"""Natural neighbour (Sibson) interpolation between a lake's forecast points.

A spot's weights are the shares of its own Voronoi cell that it would take
from each forecast point's cell if it were added as a point. The weights are
never negative and add up to 1, so a blended value always lies between the
lowest and highest of the points it uses: nothing is inflated or deflated
beyond what the forecast says. A spot on a point gets exactly that point's
value, and a value that changes evenly across the lake is reproduced exactly.

Cells are clipped to a box around the lake, so spots near the shore, outside
the ring of outer points, still get finite weights.

The weights depend only on where the points and the spot are, never on the
weather, so a lake grid works them out once (owner's pick, 6 Nov 2026).
"""

from __future__ import annotations

import math

Point = tuple[float, float]
Polygon = list[Point]


def _clip(poly: Polygon, a: float, b: float, c: float) -> Polygon:
    """The part of a convex polygon where a*x + b*y <= c."""
    out: Polygon = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        fp, fq = a * p[0] + b * p[1] - c, a * q[0] + b * q[1] - c
        if fp <= 0:
            out.append(p)
        if (fp < 0 < fq) or (fq < 0 < fp):
            t = fp / (fp - fq)
            out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
    return out


def _area(poly: Polygon) -> float:
    return abs(sum(poly[i][0] * poly[i - 1][1] - poly[i - 1][0] * poly[i][1] for i in range(len(poly)))) / 2


def _closer_to(p: Point, q: Point) -> tuple[float, float, float]:
    """Half-plane of the spots at least as close to p as to q."""
    return q[0] - p[0], q[1] - p[1], (q[0] ** 2 + q[1] ** 2 - p[0] ** 2 - p[1] ** 2) / 2


def _cell(site: Point, others: list[Point], box: Polygon) -> Polygon:
    poly = box
    for o in others:
        if o != site:
            poly = _clip(poly, *_closer_to(site, o))
            if not poly:
                break
    return poly


class NaturalNeighbours:
    """Weights for spots among fixed points, in metres (or any flat units)."""

    def __init__(self, points: list[Point], box: tuple[float, float, float, float]):
        west, south, east, north = box
        self.points = points
        self.box: Polygon = [(west, south), (east, south), (east, north), (west, north)]
        self.cells = [_cell(p, points, self.box) for p in points]
        # Each cell as half-planes, to cut a new spot's cell with it.
        self.planes = [[_closer_to(p, o) for o in points if o != p] for p in points]

    def weights(self, spot: Point) -> dict[int, float]:
        """Point index -> weight, only points with a share, adding up to 1."""
        for i, p in enumerate(self.points):
            if math.dist(p, spot) < 1e-6:
                return {i: 1.0}
        new = _cell(spot, self.points, self.box)
        total = _area(new)
        if total <= 0:
            return {min(range(len(self.points)), key=lambda i: math.dist(self.points[i], spot)): 1.0}
        xs, ys = [x for x, _ in new], [y for _, y in new]
        out: dict[int, float] = {}
        for i, cell in enumerate(self.cells):
            if not cell or max(x for x, _ in cell) < min(xs) or min(x for x, _ in cell) > max(xs) \
                    or max(y for _, y in cell) < min(ys) or min(y for _, y in cell) > max(ys):
                continue
            part = new
            for plane in self.planes[i]:
                part = _clip(part, *plane)
                if not part:
                    break
            share = _area(part) if len(part) >= 3 else 0.0
            if share > 1e-9 * total:
                out[i] = share
        s = sum(out.values())
        return {i: w / s for i, w in out.items()}


def blend(weights: dict[int, float], values: list[float]) -> float:
    return sum(w * values[i] for i, w in weights.items())


def blend_visibility(weights: dict[int, float], values_m: list[float]) -> float:
    """On a log scale, so a fog bank thins out over a few hundred metres, not kilometres."""
    return math.exp(sum(w * math.log(max(values_m[i], 1.0)) for i, w in weights.items()))


def blend_direction(weights: dict[int, float], speeds: list[float], from_deg: list[float]) -> float:
    """Wind direction from the blended wind arrows; 350° and 10° give 0°, not 180°."""
    u = sum(w * speeds[i] * math.sin(math.radians(from_deg[i])) for i, w in weights.items())
    v = sum(w * speeds[i] * math.cos(math.radians(from_deg[i])) for i, w in weights.items())
    if abs(u) < 1e-9 and abs(v) < 1e-9:
        return from_deg[max(weights, key=weights.get)]
    return math.degrees(math.atan2(u, v)) % 360


# Room around the cells and points for the Voronoi cells near the shore, in metres.
BOX_MARGIN_M = 4400.0
EARTH_RADIUS_M = 6_371_000.0


def lake_weights(cells: list[tuple[float, float]], points: list[tuple[float, float]]) -> list[dict[int, float]]:
    """Weights per water cell from (lon, lat) cell centres and forecast points.
    The app works them out the same way (LakeInterpolation.swift): flat metres
    around the middle latitude, a box 4.4 km around everything."""
    if not points:
        return [{} for _ in cells]
    if len(points) == 1:
        return [{0: 1.0} for _ in cells]
    lats = [lat for _, lat in cells + points]
    lons = [lon for lon, _ in cells + points]
    lat0, lon0 = (min(lats) + max(lats)) / 2, (min(lons) + max(lons)) / 2
    k = math.cos(math.radians(lat0))

    def flat(lon: float, lat: float) -> Point:
        return math.radians(lon - lon0) * EARTH_RADIUS_M * k, math.radians(lat - lat0) * EARTH_RADIUS_M

    pts = [flat(*p) for p in points]
    sq = [flat(*c) for c in cells]
    xs, ys = [x for x, _ in pts + sq], [y for _, y in pts + sq]
    nn = NaturalNeighbours(pts, (min(xs) - BOX_MARGIN_M, min(ys) - BOX_MARGIN_M, max(xs) + BOX_MARGIN_M, max(ys) + BOX_MARGIN_M))
    return [nn.weights(s) for s in sq]
