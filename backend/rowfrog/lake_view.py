"""Conditions across a whole lake, for the app's lake view.

The lake is covered with a regular grid of square cells (about 1,000 water
cells, so small lakes get small cells). Every hour, each cell gets its own
waves from the wind of the nearest forecast point and the open water upwind of
the cell, and its own light from the same rules as the club light (score.py).

Conditions that hold for the whole lake (DWD lake and weather warnings, dark,
cold water) are reported once per hour as "lake wide" instead of colouring
every cell, so the map still shows where the water is calmer.

Fetch is precomputed per cell for DIRECTIONS wind directions and interpolated,
on an outline simplified to a fraction of the cell size, so a grid is built in
a few seconds once per lake and then cached.
"""

from __future__ import annotations

import hashlib
import json
import logging
import math
import pickle
import sys
from bisect import bisect_right
from dataclasses import dataclass, field, replace
from datetime import timedelta
from functools import lru_cache
from pathlib import Path
from typing import Sequence

try:  # only the publishing job has numpy (satellite extra); without it the plain loops are used
    import numpy as np
except ImportError:  # pragma: no cover
    np = None

from . import interpolate
from .forecast import CAPE_AMBER_JKG, CAPE_RED_JKG, CONVECTIVE_RAIN_MM, _daylight, _lake_warning, _thunderstorm, _weather_warning, weather_warning_topic
from .outlines import Rings
from .score import HAIL_CODES, HourConditions, Light, Thresholds, assess
from .sources.dwd_warnings import Warning
from .sources.open_meteo import ForecastHour
from .sun import sun_days
from .waves import EARTH_RADIUS_M, G, _ray_hits, significant_wave_height

TARGET_CELLS = 1000
MIN_CELL_M = 40.0
# River sections: cells down to this size, until at least NARROW_MIN_SHARE of
# the target number of cell centres lie on the water.
MIN_RIVER_CELL_M = 8.0
NARROW_MIN_SHARE = 0.5
MAX_CELL_M = 1000.0
DIRECTIONS = 36  # every 10 degrees
# ICON-D2, the model behind the first two forecast days, has a 2.2 km grid.
SAMPLE_SPACING_M = 2200.0
# Forecast points per lake. Each costs one Open-Meteo call per refresh, so
# lakes that people look at get a few more (USED_SAMPLES) than the rest.
MAX_SAMPLES = 12
USED_SAMPLES = 15

# River sections: one forecast point per RIVER_KM_PER_SAMPLE km of river,
# RIVER_SAMPLES apart from that (about 850 points for all sections, budget of 2026-10-28).
RIVER_KM_PER_SAMPLE = 5.0
RIVER_SAMPLES = (2, 6)


def river_samples(length_km: float) -> int:
    low, high = RIVER_SAMPLES
    return max(low, min(high, round(length_km / RIVER_KM_PER_SAMPLE)))


# Lakes at least this much longer than wide are split into three parts.
ELONGATED = 1.6
COMPASS = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]


@dataclass(frozen=True)
class Grid:
    south: float  # latitude of the centre of the bottom row
    west: float  # longitude of the centre of the left column
    d_lat: float
    d_lon: float
    cols: int
    rows: int
    cell_m: float
    cells: list[int]  # row * cols + col of every water cell; row 0 is the south
    points: list[tuple[float, float]]  # (lon, lat) of every water cell
    fetch: list[list[float]]  # per water cell, fetch in metres for each of DIRECTIONS
    samples: list[tuple[float, float]]  # (lon, lat) of the forecast points
    nearest: list[int]  # forecast point index per water cell
    zones: list[str]  # names of the parts of the lake, e.g. north, middle, south
    zone_of: list[int]  # zone index per water cell
    outline: Rings  # simplified, for drawing
    # Per water cell, the natural neighbour weights of the forecast points (interpolate.py):
    # wind, gusts, rain and visibility are blended from them (owner's pick, 6 Nov 2026).
    weights: list[dict[int, float]] = field(default_factory=list)


@dataclass(frozen=True)
class LakeHour:
    time: object
    lake_wide: list[tuple[str, Light]]
    lights: list[Light]  # per water cell, from the conditions at the cell only
    waves_m: list[float]
    wind: list[ForecastHour]  # per forecast point
    zone_lights: list[Light] = field(default_factory=list)
    zone_max_wave_m: list[float] = field(default_factory=list)
    # Per forecast point: the light from fog, thunderstorms, heavy rain and hail alone, so the app
    # can work out the cells again with a rower's own wind and wave limits.
    point_other: list[Light] = field(default_factory=list)
    # What the weather warning behind a lake-wide "weather_warning" reason is about.
    warning_topic: str | None = None

    @property
    def lake_wide_light(self) -> Light:
        return max((light for _, light in self.lake_wide), default=Light.GREEN)


def _local(lon: float, lat: float, lon0: float, lat0: float) -> tuple[float, float]:
    return (
        math.radians(lon - lon0) * EARTH_RADIUS_M * math.cos(math.radians(lat0)),
        math.radians(lat - lat0) * EARTH_RADIUS_M,
    )


def _simplify(ring: list[tuple[float, float]], tolerance: float) -> list[tuple[float, float]]:
    """Ramer-Douglas-Peucker on a closed ring in metres; keeps at least a triangle."""
    if len(ring) < 4:
        return ring

    def rdp(pts: list[tuple[float, float]]) -> list[tuple[float, float]]:
        keep = [False] * len(pts)
        keep[0] = keep[-1] = True
        stack = [(0, len(pts) - 1)]
        while stack:
            a, b = stack.pop()
            (x1, y1), (x2, y2) = pts[a], pts[b]
            dx, dy = x2 - x1, y2 - y1
            length = math.hypot(dx, dy) or 1e-9
            worst, index = 0.0, -1
            for i in range(a + 1, b):
                x, y = pts[i]
                d = abs(dy * (x - x1) - dx * (y - y1)) / length
                if d > worst:
                    worst, index = d, i
            if worst > tolerance:
                keep[index] = True
                stack += [(a, index), (index, b)]
        return [p for p, k in zip(pts, keep) if k]

    # Split the ring at its farthest point from the start so both halves are open lines.
    far = max(range(len(ring)), key=lambda i: math.dist(ring[0], ring[i]))
    first = rdp(ring[: far + 1])
    second = rdp(ring[far:] + [ring[0]])
    out = first[:-1] + second[:-1]
    return out if len(out) >= 3 else ring


def _area_m2(ring: list[tuple[float, float]]) -> float:
    return abs(sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]))) / 2


def _water_area_m2(rings: list[list[tuple[float, float]]]) -> float:
    """Water area by the same even-odd rule as _inside: a ring inside an even
    number of others is a shore (water), inside an odd number an island."""
    total = 0.0
    for i, ring in enumerate(rings):
        depth = sum(_inside(*ring[0], [other]) for j, other in enumerate(rings) if j != i)
        total += _area_m2(ring) if depth % 2 == 0 else -_area_m2(ring)
    return max(total, 1.0)


def _inside(x: float, y: float, rings: list[list[tuple[float, float]]]) -> bool:
    inside = False
    for ring in rings:
        n = len(ring)
        for i in range(n):
            x1, y1 = ring[i]
            x2, y2 = ring[(i + 1) % n]
            if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                inside = not inside
    return inside


def _fetch_from(x: float, y: float, rings: list[list[tuple[float, float]]]) -> list[float]:
    shifted = [[(px - x, py - y) for px, py in ring] for ring in rings]
    out = []
    for k in range(DIRECTIONS):
        theta = math.radians(k * 360 / DIRECTIONS)
        hits = _ray_hits(math.sin(theta), math.cos(theta), shifted)
        out.append(hits[0] if hits else 0.0)
    return out


def _zones(points_m: list[tuple[float, float]]) -> tuple[list[str], list[int]]:
    """Thirds of the lake along its long axis, named by compass direction."""
    n = len(points_m)
    if n < 9:
        return ["whole"], [0] * n
    mx = sum(p[0] for p in points_m) / n
    my = sum(p[1] for p in points_m) / n
    sxx = sum((p[0] - mx) ** 2 for p in points_m)
    syy = sum((p[1] - my) ** 2 for p in points_m)
    sxy = sum((p[0] - mx) * (p[1] - my) for p in points_m)
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)  # long axis, from east, counter-clockwise
    ax, ay = math.cos(angle), math.sin(angle)
    proj = [(p[0] - mx) * ax + (p[1] - my) * ay for p in points_m]
    lo, hi = min(proj), max(proj)
    # A roundish lake has no clear ends: compare the spread along both axes.
    trace, det = sxx + syy, sxx * syy - sxy * sxy
    root = math.sqrt(max(trace * trace / 4 - det, 0.0))
    if trace / 2 + root < ELONGATED**2 * (trace / 2 - root):
        return ["whole"], [0] * n
    bearing = math.degrees(math.atan2(ax, ay)) % 360  # compass bearing of the "hi" end
    hi_name = COMPASS[round(bearing / 45) % 8]
    lo_name = COMPASS[(round(bearing / 45) + 4) % 8]
    third = (hi - lo) / 3
    zone_of = [2 if v > hi - third else 0 if v < lo + third else 1 for v in proj]
    if 90 < bearing <= 270:  # list the northern (or western) end first
        return [lo_name, "middle", hi_name], zone_of
    return [hi_name, "middle", lo_name], [2 - z for z in zone_of]


def _row_crossings(rings: list[list[tuple[float, float]]], ys: list[float]) -> list[list[float]]:
    """For each row height, the x where ring edges cross it, sorted (the same
    crossings _inside counts, found per edge instead of per point)."""
    out: list[list[float]] = [[] for _ in ys]
    if not ys:
        return out
    y0 = ys[0]
    step = ys[1] - ys[0] if len(ys) > 1 else 1.0
    for ring in rings:
        n = len(ring)
        for i in range(n):
            x1, y1 = ring[i]
            x2, y2 = ring[(i + 1) % n]
            if y1 == y2:
                continue
            lo, hi = min(y1, y2), max(y1, y2)
            # Rows with lo <= y < hi, as (y1 > y) != (y2 > y).
            first = max(0, math.ceil((lo - y0) / step) - 1)
            last = min(len(ys) - 1, math.floor((hi - y0) / step) + 1)
            for r in range(first, last + 1):
                y = ys[r]
                if (y1 > y) != (y2 > y):
                    out[r].append((x2 - x1) * (y - y1) / (y2 - y1) + x1)
    for xs in out:
        xs.sort()
    return out


class _Edges:
    """Ring edges in square buckets, so a ray only tests the edges along its way."""

    def __init__(self, rings: list[list[tuple[float, float]]], size: float):
        self.size = size
        self.buckets: dict[tuple[int, int], list[tuple[float, float, float, float]]] = {}
        for ring in rings:
            for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
                edge = (x1, y1, x2, y2)
                for i in range(math.floor(min(x1, x2) / size), math.floor(max(x1, x2) / size) + 1):
                    for j in range(math.floor(min(y1, y2) / size), math.floor(max(y1, y2) / size) + 1):
                        self.buckets.setdefault((i, j), []).append(edge)
        keys = self.buckets.keys()
        self.bounds = (min(k[0] for k in keys), min(k[1] for k in keys), max(k[0] for k in keys), max(k[1] for k in keys)) if keys else (0, 0, -1, -1)

    def first_hit(self, x: float, y: float, dx: float, dy: float) -> float:
        """Distance along the ray from (x, y) to the first edge it crosses, as _ray_hits()[0], else 0."""
        size = self.size
        i, j = math.floor(x / size), math.floor(y / size)
        step_i, step_j = (1 if dx > 0 else -1), (1 if dy > 0 else -1)
        t_max_i = ((i + (dx > 0)) * size - x) / dx if dx else math.inf
        t_max_j = ((j + (dy > 0)) * size - y) / dy if dy else math.inf
        t_di = size / abs(dx) if dx else math.inf
        t_dj = size / abs(dy) if dy else math.inf
        i0, j0, i1, j1 = self.bounds
        best = math.inf
        while i0 - 1 <= i <= i1 + 1 and j0 - 1 <= j <= j1 + 1:
            for x1, y1, x2, y2 in self.buckets.get((i, j), ()):
                ex, ey = x2 - x1, y2 - y1
                denom = dx * ey - dy * ex
                if abs(denom) < 1e-12:
                    continue
                rx, ry = x1 - x, y1 - y
                t = (rx * ey - ry * ex) / denom
                u = (rx * dy - ry * dx) / denom
                if 1e-6 < t < best and 0.0 <= u < 1.0:
                    best = t
            t_exit = min(t_max_i, t_max_j)
            if best <= t_exit:
                return best
            if t_max_i < t_max_j:
                i += step_i
                t_max_i += t_di
            else:
                j += step_j
                t_max_j += t_dj
        return 0.0 if best == math.inf else best


def _fetch_table(edges: _Edges, x: float, y: float) -> list[float]:
    out = []
    for k in range(DIRECTIONS):
        theta = math.radians(k * 360 / DIRECTIONS)
        out.append(edges.first_hit(x, y, math.sin(theta), math.cos(theta)))
    return out


def build_grid(rings: Rings, target_cells: int = TARGET_CELLS, max_samples: int = MAX_SAMPLES, narrow: bool = False) -> Grid:
    """`narrow` is for river sections: long and thin, so the cells get smaller
    (down to MIN_RIVER_CELL_M) until enough of their centres lie on the water."""
    # Every ring counts: a lake in several parts (a MultiPolygon) has more than one shore.
    lons = [x for ring in rings for x, _ in ring]
    lats = [y for ring in rings for _, y in ring]
    lon0, lat0 = (min(lons) + max(lons)) / 2, (min(lats) + max(lats)) / 2
    rings_m = [[_local(x, y, lon0, lat0) for x, y in ring] for ring in rings]
    area = _water_area_m2(rings_m)
    cell = min(MAX_CELL_M, max(MIN_RIVER_CELL_M if narrow else MIN_CELL_M, math.sqrt(area / target_cells)))
    while True:
        simple = [_simplify(r, cell / 6) for r in rings_m]
        d_lat = math.degrees(cell / EARTH_RADIUS_M)
        d_lon = d_lat / math.cos(math.radians(lat0))
        south, west = min(lats) + d_lat / 2, min(lons) + d_lon / 2
        rows = max(1, math.ceil((max(lats) - min(lats)) / d_lat))
        cols = max(1, math.ceil((max(lons) - min(lons)) / d_lon))
        ys = [_local(lon0, south + row * d_lat, lon0, lat0)[1] for row in range(rows)]
        xs = [_local(west + col * d_lon, lat0, lon0, lat0)[0] for col in range(cols)]
        crossings = _row_crossings(simple, ys)
        inside = [(row, col) for row in range(rows) for col in range(cols) if (len(crossings[row]) - bisect_right(crossings[row], xs[col])) % 2]
        if not narrow or len(inside) >= NARROW_MIN_SHARE * target_cells or cell <= MIN_RIVER_CELL_M:
            break
        cell = max(MIN_RIVER_CELL_M, cell / 1.4)

    edges = _Edges(simple, max(4 * cell, 100.0))
    cells, points, points_m, fetch = [], [], [], []
    for row, col in inside:
        x, y = xs[col], ys[row]
        cells.append(row * cols + col)
        points.append((west + col * d_lon, south + row * d_lat))
        points_m.append((x, y))
        fetch.append(_fetch_table(edges, x, y))

    samples_m = _spread(points_m, max_samples) if narrow else _samples(points_m, simple, max_samples)
    samples = [
        (lon0 + math.degrees(x / (EARTH_RADIUS_M * math.cos(math.radians(lat0)))), lat0 + math.degrees(y / EARTH_RADIUS_M))
        for x, y in samples_m
    ]
    nearest = [min(range(len(samples_m)), key=lambda i: math.dist(p, samples_m[i])) for p in points_m]
    zones, zone_of = _zones(points_m)

    def to_lonlat(x: float, y: float) -> tuple[float, float]:
        return (
            round(lon0 + math.degrees(x / (EARTH_RADIUS_M * math.cos(math.radians(lat0)))), 5),
            round(lat0 + math.degrees(y / EARTH_RADIUS_M), 5),
        )

    outline = [[to_lonlat(x, y) for x, y in _simplify(r, min(cell / 10, 25.0))] for r in rings_m]
    weights = interpolate.lake_weights(points, samples)
    return Grid(south, west, d_lat, d_lon, cols, rows, cell, cells, points, fetch, samples, nearest, zones, zone_of, outline, weights)


def _samples(
    points_m: list[tuple[float, float]], rings_m: list[list[tuple[float, float]]], max_samples: int = MAX_SAMPLES
) -> list[tuple[float, float]]:
    """Forecast points about one model grid cell apart, on the water, at most `max_samples`."""
    if not points_m:
        return [(0.0, 0.0)]
    spacing = SAMPLE_SPACING_M
    while True:
        xs = [p[0] for p in points_m]
        ys = [p[1] for p in points_m]
        found = []
        y = min(ys) + spacing / 2
        while y <= max(ys):
            x = min(xs) + spacing / 2
            while x <= max(xs):
                # The water cell nearest to the lattice point, if it lies within half a spacing.
                best = min(points_m, key=lambda p: (p[0] - x) ** 2 + (p[1] - y) ** 2)
                if math.dist(best, (x, y)) <= spacing / 2 and best not in found:
                    found.append(best)
                x += spacing
            y += spacing
        if len(found) <= max_samples:
            break
        spacing *= 1.3
    if not found:
        mx = sum(xs) / len(xs)
        my = sum(ys) / len(ys)
        found = [min(points_m, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)]
    return found


def _spread(points_m: list[tuple[float, float]], count: int) -> list[tuple[float, float]]:
    """`count` water cells spread along a river section: each next one the
    farthest from those already taken, starting at one end."""
    if not points_m:
        return [(0.0, 0.0)]
    mx = sum(p[0] for p in points_m) / len(points_m)
    my = sum(p[1] for p in points_m) / len(points_m)
    found = [max(points_m, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)]
    gap = [math.dist(p, found[0]) for p in points_m]
    while len(found) < min(count, len(points_m)):
        i = max(range(len(points_m)), key=gap.__getitem__)
        found.append(points_m[i])
        gap = [min(g, math.dist(p, points_m[i])) for g, p in zip(gap, points_m)]
    return found


# Where grids are kept between publish runs (the publisher sets it next to its
# state file); None keeps them in memory only, for this process.
GRID_CACHE_DIR: Path | None = None


def use_grid_cache(path: Path | None) -> None:
    """Sets GRID_CACHE_DIR; the publish job's worker processes start with it."""
    global GRID_CACHE_DIR
    GRID_CACHE_DIR = path
# The code a grid is built by: when any of these files changes, every kept grid is built again.
_GRID_CODE = ("lake_view.py", "interpolate.py", "waves.py")


@lru_cache(maxsize=1)
def _code_fingerprint() -> str:
    """The grid code's own fingerprint: its source files and the Python version (pickle format)."""
    h = hashlib.sha256(f"{sys.version_info.major}.{sys.version_info.minor}".encode())
    for name in _GRID_CODE:
        h.update(name.encode())
        h.update((Path(__file__).parent / name).read_bytes())
    return h.hexdigest()


def grid_fingerprint(rings: tuple, max_samples: int, narrow: bool) -> str:
    """Changes when the lake's outline, the grid's settings or the grid code change."""
    h = hashlib.sha256(_code_fingerprint().encode())
    h.update(json.dumps([rings, max_samples, narrow, TARGET_CELLS]).encode())
    return h.hexdigest()


def _kept_grid(lake_id: str, fingerprint: str) -> Grid | None:
    """The grid kept from an earlier run, if it was built from the same outline and code."""
    path = GRID_CACHE_DIR / f"{lake_id}.pickle"
    try:
        with path.open("rb") as f:
            kept = pickle.load(f)
    except FileNotFoundError:
        return None
    except Exception as e:  # a broken or old file: build the grid again
        logging.getLogger(__name__).warning("kept lake grid %s unreadable: %r", lake_id, e)
        return None
    return kept.get("grid") if isinstance(kept, dict) and kept.get("fingerprint") == fingerprint else None


def _keep_grid(lake_id: str, fingerprint: str, grid: Grid) -> None:
    try:
        GRID_CACHE_DIR.mkdir(parents=True, exist_ok=True)
        path = GRID_CACHE_DIR / f"{lake_id}.pickle"
        tmp = path.with_suffix(".tmp")
        with tmp.open("wb") as f:
            pickle.dump({"fingerprint": fingerprint, "grid": grid}, f, protocol=pickle.HIGHEST_PROTOCOL)
        tmp.replace(path)
    except OSError as e:  # a full disk must not stop the lake view
        logging.getLogger(__name__).warning("could not keep lake grid %s: %r", lake_id, e)


# Room for every lake with an outline (378 in Nov 2026), so a publish run builds each grid once.
@lru_cache(maxsize=512)
def _grid_cached(key: str, rings: tuple, max_samples: int, narrow: bool) -> Grid:
    """The lake's grid: from GRID_CACHE_DIR when it was built from this very outline, settings and
    code (about 3 min for all lakes on the Raspberry Pi, Nov 2026), else built and kept there."""
    if GRID_CACHE_DIR is None:
        return build_grid([list(r) for r in rings], max_samples=max_samples, narrow=narrow)
    fingerprint = grid_fingerprint(rings, max_samples, narrow)
    grid = _kept_grid(key, fingerprint)
    if grid is None:
        grid = build_grid([list(r) for r in rings], max_samples=max_samples, narrow=narrow)
        _keep_grid(key, fingerprint, grid)
    return grid


def grid_for(lake_id: str, rings: Rings, max_samples: int = MAX_SAMPLES, narrow: bool = False) -> Grid:
    return _grid_cached(lake_id, tuple(tuple(r) for r in rings), max_samples, narrow)


def _interpolated_fetch(table: list[float], wind_from_deg: float) -> float:
    step = 360 / DIRECTIONS
    pos = (wind_from_deg % 360) / step
    i = int(pos) % DIRECTIONS
    t = pos - int(pos)
    return table[i] * (1 - t) + table[(i + 1) % DIRECTIONS] * t


def cell_weather(grid: Grid, i: int, at_points: Sequence[ForecastHour]) -> ForecastHour:
    """The weather at a water cell, blended from the forecast points around it:
    wind, gusts and rain as they are, visibility on a log scale, the direction
    from the wind arrows. Thunderstorms and hail are yes or no, so they come
    from the nearest point."""
    near = at_points[grid.nearest[i]]
    weights = grid.weights[i] if i < len(grid.weights) else None
    if not weights or len(weights) == 1:
        return at_points[next(iter(weights))] if weights else near

    def blended(get, fn=interpolate.blend):
        values = [get(w) for w in at_points]
        if any(values[j] is None for j in weights):
            return get(near)
        return fn(weights, values)

    speeds = [w.wind_speed_ms or 0.0 for w in at_points]
    dirs = [w.wind_from_deg for w in at_points]
    direction = near.wind_from_deg if any(dirs[j] is None for j in weights) else interpolate.blend_direction(weights, speeds, dirs)
    return replace(
        near,
        wind_speed_ms=blended(lambda w: w.wind_speed_ms),
        wind_gust_ms=blended(lambda w: w.wind_gust_ms),
        wind_from_deg=direction,
        visibility_m=blended(lambda w: w.visibility_m, interpolate.blend_visibility),
        precipitation_mm=blended(lambda w: w.precipitation_mm),
    )


def _storm_light(cape_jkg: float | None, precipitation_mm: float | None) -> Light:
    """forecast._thunderstorm on the two values it reads, so a cell needs no ForecastHour of its own."""
    cape = cape_jkg or 0.0
    if cape >= CAPE_RED_JKG and (precipitation_mm or 0.0) >= CONVECTIVE_RAIN_MM:
        return Light.RED
    if cape >= CAPE_AMBER_JKG:
        return Light.AMBER
    return Light.GREEN


class _HourColumns:
    """One hour's forecast points as columns, read once per hour instead of
    once per water cell. Lake views took about 4 s each on the Raspberry Pi
    (Nov 2026), most of it in cell_weather; cell() gives the same numbers,
    sum for sum, in about half the time (tests/test_lake_view.py compares them)."""

    def __init__(self, at_points: Sequence[ForecastHour]):
        self.points = at_points
        self.speed = [w.wind_speed_ms for w in at_points]
        self.gust = [w.wind_gust_ms for w in at_points]
        self.dirs = [w.wind_from_deg for w in at_points]
        self.vis = [w.visibility_m for w in at_points]
        self.rain = [w.precipitation_mm for w in at_points]
        self.speed0 = [s or 0.0 for s in self.speed]
        self.sin = [math.sin(math.radians(d)) if d is not None else None for d in self.dirs]
        self.cos = [math.cos(math.radians(d)) if d is not None else None for d in self.dirs]
        self.log_vis = [math.log(max(v, 1.0)) if v is not None else None for v in self.vis]

    def cell(self, grid: Grid, i: int):
        """(speed, gust, direction, visibility, rain, cape, weather code) at water cell i, as cell_weather."""
        weights = grid.weights[i] if i < len(grid.weights) else None
        if not weights or len(weights) == 1:
            w = self.points[next(iter(weights))] if weights else self.points[grid.nearest[i]]
            return w.wind_speed_ms, w.wind_gust_ms, w.wind_from_deg, w.visibility_m, w.precipitation_mm, w.cape_jkg, w.weather_code
        near = self.points[grid.nearest[i]]
        items = weights.items()

        def mix(values, near_value):
            if any(values[j] is None for j in weights):
                return near_value
            return sum(w * values[j] for j, w in items)

        if any(self.dirs[j] is None for j in weights):
            direction = near.wind_from_deg
        else:  # interpolate.blend_direction
            u = sum(w * self.speed0[j] * self.sin[j] for j, w in items)
            v = sum(w * self.speed0[j] * self.cos[j] for j, w in items)
            if abs(u) < 1e-9 and abs(v) < 1e-9:
                direction = self.dirs[max(weights, key=weights.get)]
            else:
                direction = math.degrees(math.atan2(u, v)) % 360
        if any(self.vis[j] is None for j in weights):
            visibility = near.visibility_m
        else:  # interpolate.blend_visibility
            visibility = math.exp(sum(w * self.log_vis[j] for j, w in items))
        return (
            mix(self.speed, near.wind_speed_ms),
            mix(self.gust, near.wind_gust_ms),
            direction,
            visibility,
            mix(self.rain, near.precipitation_mm),
            near.cape_jkg,
            near.weather_code,
        )


def lake_hours(
    grid: Grid,
    weather: Sequence[Sequence[ForecastHour]],
    warnings: Sequence[Warning] = (),
    water_temp_c: float | None = None,
    thresholds: Thresholds = Thresholds(),
) -> list[LakeHour]:
    """One LakeHour per forecast hour; `weather` holds one hourly list per forecast point.

    The cells are worked out for all hours at once with numpy (_cells_numpy); without numpy,
    hour by hour and cell by cell (_lake_hours_loop). Both give the very same numbers:
    tests/test_lake_view.py compares them."""
    return _lake_hours(grid, weather, warnings, water_temp_c, thresholds, _cells_loop if np is None else _cells_numpy)


def _lake_hours_loop(
    grid: Grid,
    weather: Sequence[Sequence[ForecastHour]],
    warnings: Sequence[Warning] = (),
    water_temp_c: float | None = None,
    thresholds: Thresholds = Thresholds(),
) -> list[LakeHour]:
    """lake_hours without numpy: hour by hour, cell by cell."""
    return _lake_hours(grid, weather, warnings, water_temp_c, thresholds, _cells_loop)


def _lake_hours(grid, weather, warnings, water_temp_c, thresholds, cells) -> list[LakeHour]:
    if not weather or not weather[0]:
        return []
    centre_lon = sum(p[0] for p in grid.samples) / len(grid.samples)
    centre_lat = sum(p[1] for p in grid.samples) / len(grid.samples)
    first, last = weather[0][0].time, weather[0][-1].time
    days = sun_days(first, last, centre_lat, centre_lon)
    # Cold water lowers the wind limits for the cells too.
    lights, waves, zone_lights, zone_waves = cells(grid, weather, thresholds.for_water(water_temp_c))
    hours = []
    for h in range(len(weather[0])):
        at_points = [w[h] for w in weather]
        when = at_points[0].time
        end = when + timedelta(hours=1)
        daylight_name, daylight, _ = _daylight(at_points[0], days)
        wide = assess(
            HourConditions(
                wind_speed_ms=0.0,
                wind_gust_ms=0.0,
                water_temp_c=water_temp_c,
                daylight=daylight,
                daylight_name=daylight_name,
                lake_warning=_lake_warning(list(warnings), when, end),
                weather_warning=_weather_warning(list(warnings), when, end),
            ),
            thresholds,
        )
        point_other = [
            assess(
                HourConditions(
                    wind_speed_ms=0.0,
                    wind_gust_ms=0.0,
                    visibility_m=w.visibility_m,
                    thunderstorm=_thunderstorm(w),
                    precipitation_mm=w.precipitation_mm,
                    weather_code=w.weather_code,
                ),
                thresholds,
            ).light
            for w in at_points
        ]
        hours.append(
            LakeHour(
                when, wide.reasons, lights[h], waves[h], at_points, zone_lights[h], zone_waves[h], point_other,
                weather_warning_topic(list(warnings), when, end),
            )
        )
    return hours


def _cells_loop(grid: Grid, weather: Sequence[Sequence[ForecastHour]], t: Thresholds):
    """Per hour the cells' lights and waves and each zone's worst of them, one cell at a time."""
    out = [], [], [], []
    for h in range(len(weather[0])):
        lights, waves = [], []
        zone_lights = [Light.GREEN] * len(grid.zones)
        zone_waves = [0.0] * len(grid.zones)
        columns = _HourColumns([w[h] for w in weather])
        for i, table in enumerate(grid.fetch):
            speed, gust, direction, visibility, rain, cape, code = columns.cell(grid, i)
            speed = speed or 0.0
            wave = 0.0
            if direction is not None:
                wave = significant_wave_height(speed, _interpolated_fetch(table, direction))
            light = assess(
                HourConditions(
                    wind_speed_ms=speed,
                    wind_gust_ms=gust or 0.0,
                    wave_height_m=wave,
                    visibility_m=visibility,
                    thunderstorm=_storm_light(cape, rain),
                    precipitation_mm=rain,
                    weather_code=code,
                ),
                t,
            ).light
            lights.append(light)
            waves.append(wave)
            z = grid.zone_of[i]
            zone_lights[z] = max(zone_lights[z], light)
            zone_waves[z] = max(zone_waves[z], wave)
        for part, value in zip(out, (lights, waves, zone_lights, zone_waves)):
            part.append(value)
    return out


_LIGHTS = (Light.GREEN, Light.AMBER, Light.RED)
# A blended visibility this far above the fog limit (on the log scale) is clear of it whatever
# exp() rounds to, so math.exp is only needed near the limit.
_LOG_MARGIN = 1e-6
# Waves: where the fully developed height is not clearly above the fetch-limited one, the cell
# takes significant_wave_height itself (Python's `**` may round apart from numpy's `x * x`).
_WAVE_MARGIN = 1e-9


def _cells_numpy(grid: Grid, weather: Sequence[Sequence[ForecastHour]], t: Thresholds):
    """_cells_loop for every hour at once, with numpy. The same numbers as the loop: sums in the
    same order with Python's rounding (_python_sum); atan2, exp and the wave formula with math."""
    hours = len(weather[0])
    nan = math.nan

    def table(get) -> "np.ndarray":  # points × hours, None as NaN
        return np.array([[nan if (v := get(w[h])) is None else v for h in range(hours)] for w in weather], dtype=float)

    rows = [[w[h] for h in range(hours)] for w in weather]
    speed = table(lambda p: p.wind_speed_ms)
    gust = table(lambda p: p.wind_gust_ms)
    dirs = table(lambda p: p.wind_from_deg)
    vis = table(lambda p: p.visibility_m)
    rain = table(lambda p: p.precipitation_mm)
    cape = table(lambda p: p.cape_jkg)
    hail = np.array([[p.weather_code in HAIL_CODES for p in r] for r in rows], dtype=bool)
    sin = np.array([[math.sin(math.radians(p.wind_from_deg)) if p.wind_from_deg is not None else nan for p in r] for r in rows])
    cos = np.array([[math.cos(math.radians(p.wind_from_deg)) if p.wind_from_deg is not None else nan for p in r] for r in rows])
    speed0 = np.nan_to_num(speed, nan=0.0)
    log_vis = np.array([[math.log(max(p.visibility_m, 1.0)) if p.visibility_m is not None else nan for p in r] for r in rows])

    n = len(grid.fetch)
    c_speed = np.empty((n, hours))
    c_gust = np.empty((n, hours))
    c_rain = np.empty((n, hours))
    c_cape = np.empty((n, hours))
    c_hail = np.empty((n, hours), dtype=bool)
    c_vis = np.full((n, hours), np.inf)  # inf: no fog check (no value, or clearly above the limit)
    c_dir = np.full((n, hours), nan)  # NaN: no direction, so no waves
    fog_limit = math.log(max(t.visibility_amber_m, 1.0)) + _LOG_MARGIN

    # Cells taking one point as it is (no weights, or one), then cells grouped by how many they blend.
    single: list[tuple[int, int]] = []
    groups: dict[int, list[tuple[int, list[tuple[int, float]]]]] = {}
    for i in range(n):
        weights = grid.weights[i] if i < len(grid.weights) else None
        if not weights or len(weights) == 1:
            single.append((i, next(iter(weights)) if weights else grid.nearest[i]))
        else:
            groups.setdefault(len(weights), []).append((i, list(weights.items())))
    if single:
        cells = np.array([i for i, _ in single])
        src = np.array([j for _, j in single])
        c_speed[cells], c_gust[cells], c_rain[cells], c_cape[cells] = speed[src], gust[src], rain[src], cape[src]
        c_hail[cells], c_dir[cells] = hail[src], dirs[src]
        c_vis[cells] = np.where(np.isnan(vis[src]), np.inf, vis[src])
    for k, group in groups.items():
        cells = np.array([i for i, _ in group])
        idx = np.array([[j for j, _ in w] for _, w in group])  # cells × k
        wts = np.array([[x for _, x in w] for _, w in group])
        near = np.array([grid.nearest[i] for i, _ in group])

        def missing(values):  # cells × hours: a point of the cell has no value
            return np.isnan(values[idx]).any(axis=1)

        def mix(values):  # as _HourColumns.cell's mix(): the nearest point's value where one is missing
            picked = values[idx]  # cells × k × hours
            mixed = _python_sum([wts[:, m, None] * picked[:, m] for m in range(k)])
            return np.where(np.isnan(picked).any(axis=1), values[near], mixed)

        c_speed[cells], c_gust[cells], c_rain[cells] = mix(speed), mix(gust), mix(rain)
        c_cape[cells], c_hail[cells] = cape[near], hail[near]
        # Direction (interpolate.blend_direction) and visibility (blend_visibility) as in _HourColumns.cell.
        no_dir = missing(dirs)
        u = _python_sum([(wts[:, m, None] * speed0[idx[:, m]]) * sin[idx[:, m]] for m in range(k)])
        v = _python_sum([(wts[:, m, None] * speed0[idx[:, m]]) * cos[idx[:, m]] for m in range(k)])
        top = idx[np.arange(len(group)), np.argmax(wts, axis=1)]  # max(weights, key=weights.get): the first largest
        calm = (np.abs(u) < 1e-9) & (np.abs(v) < 1e-9)
        out = np.where(no_dir, dirs[near], np.where(calm, dirs[top], nan))
        arrows = ~(calm | no_dir)
        out[arrows] = [math.degrees(math.atan2(a, b)) % 360 for a, b in zip(u[arrows].tolist(), v[arrows].tolist())]
        c_dir[cells] = out
        no_vis = missing(vis)
        lv = _python_sum([wts[:, m, None] * log_vis[idx[:, m]] for m in range(k)])
        blended = np.full(lv.shape, np.inf)
        for r, h in zip(*np.nonzero(~no_vis & (lv <= fog_limit))):
            blended[r, h] = math.exp(lv[r, h])
        c_vis[cells] = np.where(no_vis, np.where(np.isnan(vis[near]), np.inf, vis[near]), blended)

    s = np.nan_to_num(c_speed, nan=0.0)  # `speed or 0.0`
    g = np.nan_to_num(c_gust, nan=0.0)
    # Waves: significant_wave_height(speed, _interpolated_fetch(table, direction)).
    fetch = np.array(grid.fetch, dtype=float).reshape(n, DIRECTIONS)
    has_dir = ~np.isnan(c_dir)
    pos = np.where(has_dir, c_dir, 0.0) % 360 / (360 / DIRECTIONS)
    lo = pos.astype(np.int64)
    frac = pos - lo
    rows_i = np.arange(n)[:, None]
    f = fetch[rows_i, lo % DIRECTIONS] * (1 - frac) + fetch[rows_i, (lo + 1) % DIRECTIONS] * frac
    with np.errstate(invalid="ignore"):
        limited = 0.0016 * s * np.sqrt(f / G)
    developed = 0.2433 * (s * s) / G
    calm = ~has_dir | (s <= 0) | (f <= 0)
    wave = np.where(calm, 0.0, limited)
    for r, h in zip(*np.nonzero(~calm & (developed <= limited * (1 + _WAVE_MARGIN)))):
        wave[r, h] = significant_wave_height(float(s[r, h]), float(f[r, h]))

    def rising(value, amber, red):
        return np.where(value > red, 2, np.where(value >= amber, 1, 0))

    storm = np.where(np.nan_to_num(c_cape, nan=0.0) >= CAPE_AMBER_JKG, 1, 0)
    storm = np.where((np.nan_to_num(c_cape, nan=0.0) >= CAPE_RED_JKG) & (np.nan_to_num(c_rain, nan=0.0) >= CONVECTIVE_RAIN_MM), 2, storm)
    fog = np.where(c_vis < t.visibility_red_m, 2, np.where(c_vis <= t.visibility_amber_m, 1, 0))
    with np.errstate(invalid="ignore"):
        rain_light = np.where(c_hail, 2, np.where(c_rain >= t.rain_amber_mm, 1, 0))
    light = np.maximum.reduce([
        rising(s, t.wind_amber_ms, t.wind_red_ms), rising(g, t.gust_amber_ms, t.gust_red_ms),
        rising(wave, t.wave_amber_m, t.wave_red_m), storm, fog, rain_light,
    ])
    zone_of = np.array(grid.zone_of)
    zones = [zone_of == z for z in range(len(grid.zones))]
    zone_light = [[_LIGHTS[v] for v in row] for row in np.array([light[m].max(axis=0, initial=0) for m in zones]).T.tolist()]
    zone_wave = np.array([wave[m].max(axis=0, initial=0.0) for m in zones]).T.tolist()
    lights = [[_LIGHTS[v] for v in row] for row in light.T.tolist()]
    return lights, wave.T.tolist(), zone_light, zone_wave


# The Steg light also counts the water this close to the launch point (owner's option C, 6 Nov 2026).
NEARBY_M = 1000.0
# What a nearby cause's worst value is, by reason name.
_NEARBY_VALUE = {"wind": "wind_ms", "gusts": "gust_ms", "waves": "wave_m", "fog": "vis_m", "heavy_rain": "rain_mm"}


@dataclass(frozen=True)
class Nearby:
    """The worst conditions on the water within NEARBY_M of a launch point in one hour."""

    light: Light  # with the app's own limits
    cause: str | None  # the reason that sets `light`: wind, gusts, waves, fog, thunderstorm, hail or heavy_rain
    value: float | None  # its worst value (m/s, m, metres of visibility, mm); None for thunderstorm and hail
    wind_ms: float
    gust_ms: float
    wave_m: float
    vis_m: float | None
    rain_mm: float | None
    # The light from fog, thunderstorms, heavy rain and hail alone, and which of them sets it,
    # so the app can work the light out again with a boat's own wind and wave limits.
    other: Light
    other_cause: str | None


def nearby_cells(grid: Grid, lat: float, lon: float, radius_m: float = NEARBY_M) -> list[int]:
    """Water cells within `radius_m` of a point; on a river these lie up and down the stretch."""
    return [i for i, (plon, plat) in enumerate(grid.points) if math.dist((0.0, 0.0), _local(plon, plat, lon, lat)) <= radius_m]


def _python_sum(terms: list) -> "np.ndarray":
    """sum() of these arrays, element by element, exactly as Python 3.12 and later add floats from 0:
    the first added as it is, then with Neumaier's compensation (so the result is bit-identical)."""
    f = 0.0 + terms[0]
    c = np.zeros_like(f)
    for t in terms[1:]:
        s = f + t
        c = c + np.where(np.abs(f) >= np.abs(t), (f - s) + t, (t - s) + f)
        f = s
    return np.where((c != 0) & np.isfinite(c), f + c, f)


def nearby_water(
    grid: Grid,
    weather: Sequence[Sequence[ForecastHour]],
    lat: float,
    lon: float,
    water_temp_c: float | None = None,
    thresholds: Thresholds = Thresholds(),
    radius_m: float = NEARBY_M,
) -> dict:
    """Per forecast time, the worst of the water within `radius_m` (blended as on the lake map).

    The same values as _nearby_water_loop (kept for the test), worked out for all hours at
    once per cell with numpy instead of hour by hour; None is NaN inside."""
    if np is None:
        return _nearby_water_loop(grid, weather, lat, lon, water_temp_c, thresholds, radius_m)
    cells = nearby_cells(grid, lat, lon, radius_m)
    if not cells or not weather or not weather[0]:
        return {}
    t = thresholds.for_water(water_temp_c)
    hours = len(weather[0])
    nan = math.nan

    def table(values) -> np.ndarray:
        return np.array([[nan if v is None else v for v in row] for row in values], dtype=float)

    rows = [list(w[:hours]) for w in weather]
    speed_at = [[p.wind_speed_ms for p in r] for r in rows]
    dir_at = [[p.wind_from_deg for p in r] for r in rows]
    speed = table(speed_at)
    gust = table([[p.wind_gust_ms for p in r] for r in rows])
    u_at = table([[(s or 0.0) * math.sin(math.radians(d)) if d is not None else None for s, d in zip(sr, dr)]
                  for sr, dr in zip(speed_at, dir_at)])
    v_at = table([[(s or 0.0) * math.cos(math.radians(d)) if d is not None else None for s, d in zip(sr, dr)]
                  for sr, dr in zip(speed_at, dir_at)])
    log_vis = table([[math.log(max(p.visibility_m, 1.0)) if p.visibility_m is not None else None for p in r] for r in rows])
    rain_at = table([[p.precipitation_mm for p in r] for r in rows])
    storm_at = [[_thunderstorm(p) for p in r] for r in rows]
    hail_at = [[p.weather_code in HAIL_CODES for p in r] for r in rows]

    # Cells grouped by how many points they blend, so each group is one array operation.
    plans: dict[int, list] = {}
    for i in cells:
        weights = list((grid.weights[i] if i < len(grid.weights) and grid.weights[i] else {grid.nearest[i]: 1.0}).items())
        plans.setdefault(len(weights), []).append((weights, grid.nearest[i], grid.fetch[i]))
    wind = np.zeros(hours)
    gusts = np.zeros(hours)
    waves = [0.0] * hours
    low_vis = np.full(hours, np.inf)
    rain = np.full(hours, -np.inf)
    nears = set()
    for k, group in plans.items():
        idx = np.array([[j for j, _ in w] for w, _, _ in group])  # cells × k
        wts = np.array([[x for _, x in w] for w, _, _ in group])
        near = np.array([n for _, n, _ in group])
        nears.update(near.tolist())

        def mix(values: np.ndarray) -> np.ndarray:  # cells × hours; as mix() in _nearby_water_loop
            picked = values[idx]  # cells × k × hours
            mixed = _python_sum([wts[:, m, None] * picked[:, m] for m in range(k)])
            return np.where(np.isnan(picked).any(axis=1), values[near], mixed)

        cell_speed = np.nan_to_num(mix(speed), nan=0.0)  # `or 0.0`: no value counts as calm
        wind = np.maximum(wind, cell_speed.max(axis=0))
        gusts = np.maximum(gusts, np.nan_to_num(mix(gust), nan=0.0).max(axis=0))
        low_vis = np.fmin(low_vis, np.fmin.reduce(mix(log_vis), axis=0))
        rain = np.fmax(rain, np.fmax.reduce(mix(rain_at), axis=0))
        us, vs = mix(u_at).tolist(), mix(v_at).tolist()
        for (_, n, fetch), sp, ur, vr in zip(group, cell_speed.tolist(), us, vs):
            dirs = dir_at[n]
            for h, (s, u, v) in enumerate(zip(sp, ur, vr)):
                if u != u or v != v:  # NaN: no wind direction here
                    continue
                direction = math.degrees(math.atan2(u, v)) % 360 if abs(u) > 1e-9 or abs(v) > 1e-9 else dirs[h]
                if direction is not None:
                    wave = significant_wave_height(s, _interpolated_fetch(fetch, direction))
                    if wave > waves[h]:
                        waves[h] = wave
    out = {}
    for h in range(hours):
        vis = math.exp(low_vis[h]) if low_vis[h] != np.inf else None
        r = float(rain[h]) if rain[h] != -np.inf else None
        storm = max([Light.GREEN, *(storm_at[n][h] for n in nears)])
        hail = any(hail_at[n][h] for n in nears)
        code = HAIL_CODES[0] if hail else None
        w, g, wave = float(wind[h]), float(gusts[h]), waves[h]
        full = assess(HourConditions(wind_speed_ms=w, wind_gust_ms=g, wave_height_m=wave, visibility_m=vis,
                                     thunderstorm=storm, precipitation_mm=r, weather_code=code), t)
        other = assess(HourConditions(wind_speed_ms=0.0, wind_gust_ms=0.0, visibility_m=vis, thunderstorm=storm,
                                      precipitation_mm=r, weather_code=code), t)
        values = {"wind_ms": w, "gust_ms": g, "wave_m": wave, "vis_m": vis, "rain_mm": r}
        cause = full.reasons[0][0] if full.reasons else None
        out[rows[0][h].time] = Nearby(
            full.light, cause, values.get(_NEARBY_VALUE.get(cause or "", ""), None),
            w, g, wave, vis, r, other.light, other.reasons[0][0] if other.reasons else None,
        )
    return out


def _nearby_water_loop(
    grid: Grid,
    weather: Sequence[Sequence[ForecastHour]],
    lat: float,
    lon: float,
    water_temp_c: float | None = None,
    thresholds: Thresholds = Thresholds(),
    radius_m: float = NEARBY_M,
) -> dict:
    """Per forecast time, the worst of the water within `radius_m` (blended as on the lake map)."""
    cells = nearby_cells(grid, lat, lon, radius_m)
    if not cells or not weather or not weather[0]:
        return {}
    t = thresholds.for_water(water_temp_c)
    # Each cell's weights and fetch table, worked out once; per hour only sums.
    plan = []
    for i in cells:
        weights = grid.weights[i] if i < len(grid.weights) and grid.weights[i] else {grid.nearest[i]: 1.0}
        plan.append((list(weights.items()), grid.nearest[i], grid.fetch[i]))
    out = {}
    for h in range(len(weather[0])):
        at_points = [w[h] for w in weather]
        speed_at = [p.wind_speed_ms for p in at_points]
        gust_at = [p.wind_gust_ms for p in at_points]
        dir_at = [p.wind_from_deg for p in at_points]
        vis_at = [p.visibility_m for p in at_points]
        rain_at = [p.precipitation_mm for p in at_points]
        u_at = [(s or 0.0) * math.sin(math.radians(d)) if d is not None else None for s, d in zip(speed_at, dir_at)]
        v_at = [(s or 0.0) * math.cos(math.radians(d)) if d is not None else None for s, d in zip(speed_at, dir_at)]
        log_vis = [math.log(max(v, 1.0)) if v is not None else None for v in vis_at]
        storm_at = [_thunderstorm(p) for p in at_points]
        hail_at = [p.weather_code in HAIL_CODES for p in at_points]

        def mix(values, weights, near):
            if any(values[j] is None for j, _ in weights):
                return values[near]
            return sum(w * values[j] for j, w in weights)

        wind = gust = wave = 0.0
        vis = rain = None
        storm, hail = Light.GREEN, False
        for weights, near, fetch in plan:
            speed = mix(speed_at, weights, near) or 0.0
            wind = max(wind, speed)
            gust = max(gust, mix(gust_at, weights, near) or 0.0)
            u, v = mix(u_at, weights, near), mix(v_at, weights, near)
            if u is not None and v is not None:
                direction = math.degrees(math.atan2(u, v)) % 360 if abs(u) > 1e-9 or abs(v) > 1e-9 else dir_at[near]
                if direction is not None:
                    wave = max(wave, significant_wave_height(speed, _interpolated_fetch(fetch, direction)))
            lv = mix(log_vis, weights, near)
            if lv is not None:
                cell_vis = math.exp(lv)
                vis = cell_vis if vis is None else min(vis, cell_vis)
            r = mix(rain_at, weights, near)
            if r is not None:
                rain = r if rain is None else max(rain, r)
            storm = max(storm, storm_at[near])
            hail = hail or hail_at[near]
        code = HAIL_CODES[0] if hail else None
        full = assess(HourConditions(wind_speed_ms=wind, wind_gust_ms=gust, wave_height_m=wave, visibility_m=vis,
                                     thunderstorm=storm, precipitation_mm=rain, weather_code=code), t)
        other = assess(HourConditions(wind_speed_ms=0.0, wind_gust_ms=0.0, visibility_m=vis, thunderstorm=storm,
                                      precipitation_mm=rain, weather_code=code), t)
        values = {"wind_ms": wind, "gust_ms": gust, "wave_m": wave, "vis_m": vis, "rain_mm": rain}
        cause = full.reasons[0][0] if full.reasons else None
        out[at_points[0].time] = Nearby(
            full.light, cause, values.get(_NEARBY_VALUE.get(cause or "", ""), None),
            wind, gust, wave, vis, rain, other.light, other.reasons[0][0] if other.reasons else None,
        )
    return out
