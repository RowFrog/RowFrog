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

import math
from bisect import bisect_right
from dataclasses import dataclass, field
from datetime import timedelta
from functools import lru_cache
from typing import Sequence

from .forecast import _daylight, _lake_warning, _thunderstorm, _weather_warning, weather_warning_topic
from .outlines import Rings
from .score import HourConditions, Light, Thresholds, assess
from .sources.dwd_warnings import Warning
from .sources.open_meteo import ForecastHour
from .sun import sun_days
from .waves import EARTH_RADIUS_M, _ray_hits, significant_wave_height

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


@dataclass(frozen=True)
class LakeHour:
    time: object
    lake_wide: list[tuple[str, Light]]
    lights: list[Light]  # per water cell, from the conditions at the cell only
    waves_m: list[float]
    wind: list[ForecastHour]  # per forecast point
    zone_lights: list[Light] = field(default_factory=list)
    zone_max_wave_m: list[float] = field(default_factory=list)
    # Per forecast point: the light from fog and thunderstorms alone, so the app
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
    return Grid(south, west, d_lat, d_lon, cols, rows, cell, cells, points, fetch, samples, nearest, zones, zone_of, outline)


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


@lru_cache(maxsize=256)
def _grid_cached(key: str, rings: tuple, max_samples: int, narrow: bool) -> Grid:
    return build_grid([list(r) for r in rings], max_samples=max_samples, narrow=narrow)


def grid_for(lake_id: str, rings: Rings, max_samples: int = MAX_SAMPLES, narrow: bool = False) -> Grid:
    return _grid_cached(lake_id, tuple(tuple(r) for r in rings), max_samples, narrow)


def _interpolated_fetch(table: list[float], wind_from_deg: float) -> float:
    step = 360 / DIRECTIONS
    pos = (wind_from_deg % 360) / step
    i = int(pos) % DIRECTIONS
    t = pos - int(pos)
    return table[i] * (1 - t) + table[(i + 1) % DIRECTIONS] * t


def lake_hours(
    grid: Grid,
    weather: Sequence[Sequence[ForecastHour]],
    warnings: Sequence[Warning] = (),
    water_temp_c: float | None = None,
    thresholds: Thresholds = Thresholds(),
) -> list[LakeHour]:
    """One LakeHour per forecast hour; `weather` holds one hourly list per forecast point."""
    if not weather or not weather[0]:
        return []
    centre_lon = sum(p[0] for p in grid.samples) / len(grid.samples)
    centre_lat = sum(p[1] for p in grid.samples) / len(grid.samples)
    first, last = weather[0][0].time, weather[0][-1].time
    days = sun_days(first, last, centre_lat, centre_lon)
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
                HourConditions(wind_speed_ms=0.0, wind_gust_ms=0.0, visibility_m=w.visibility_m, thunderstorm=_thunderstorm(w)),
                thresholds,
            ).light
            for w in at_points
        ]
        lights, waves = [], []
        n_zones = len(grid.zones)
        zone_lights = [Light.GREEN] * n_zones
        zone_waves = [0.0] * n_zones
        # Cold water lowers the wind limits for the cells too.
        cell_thresholds = thresholds.for_water(water_temp_c)
        for i, table in enumerate(grid.fetch):
            w = at_points[grid.nearest[i]]
            speed = w.wind_speed_ms or 0.0
            wave = 0.0
            if w.wind_from_deg is not None:
                wave = significant_wave_height(speed, _interpolated_fetch(table, w.wind_from_deg))
            light = assess(
                HourConditions(
                    wind_speed_ms=speed,
                    wind_gust_ms=w.wind_gust_ms or 0.0,
                    wave_height_m=wave,
                    visibility_m=w.visibility_m,
                    thunderstorm=_thunderstorm(w),
                ),
                cell_thresholds,
            ).light
            lights.append(light)
            waves.append(wave)
            z = grid.zone_of[i]
            zone_lights[z] = max(zone_lights[z], light)
            zone_waves[z] = max(zone_waves[z], wave)
        hours.append(
            LakeHour(
                when, wide.reasons, lights, waves, at_points, zone_lights, zone_waves, point_other,
                weather_warning_topic(list(warnings), when, end),
            )
        )
    return hours
