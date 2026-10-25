"""Wave height on a lake from wind and fetch.

There are no public wave measurements for the Bavarian lakes, so waves are
estimated with the JONSWAP fetch-limited relation:

    Hs = 0.0016 * U10 * sqrt(F / g)

capped at the fully developed (Pierson-Moskowitz) height 0.2433 * U10^2 / g.

Fetch is the open-water distance upwind of the launch point, measured on the
lake outline (outer ring plus island holes) for the wind's "from" direction.
"""

from __future__ import annotations

import math
from typing import Sequence

G = 9.81
EARTH_RADIUS_M = 6_371_000.0
# A boathouse sits on the shore, so a launch point may geocode just onto land.
SHORE_TOLERANCE_M = 200.0

Ring = Sequence[tuple[float, float]]  # (lon, lat) pairs, GeoJSON order


def significant_wave_height(wind_speed_ms: float, fetch_m: float) -> float:
    """Significant wave height in metres for a 10 m wind speed and a fetch."""
    if wind_speed_ms <= 0 or fetch_m <= 0:
        return 0.0
    fetch_limited = 0.0016 * wind_speed_ms * math.sqrt(fetch_m / G)
    fully_developed = 0.2433 * wind_speed_ms**2 / G
    return min(fetch_limited, fully_developed)


def _to_local_m(lon: float, lat: float, origin_lon: float, origin_lat: float) -> tuple[float, float]:
    """Equirectangular projection around the origin; accurate to well under 1% on a lake."""
    x = math.radians(lon - origin_lon) * EARTH_RADIUS_M * math.cos(math.radians(origin_lat))
    y = math.radians(lat - origin_lat) * EARTH_RADIUS_M
    return x, y


def _ray_hits(dx: float, dy: float, rings_m: list[list[tuple[float, float]]]) -> list[float]:
    """Distances along the ray from (0, 0) in direction (dx, dy) where it crosses any ring edge."""
    hits = []
    for ring in rings_m:
        for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
            ex, ey = x2 - x1, y2 - y1
            denom = dx * ey - dy * ex
            if abs(denom) < 1e-12:
                continue
            t = (x1 * ey - y1 * ex) / denom  # distance along the ray
            u = (x1 * dy - y1 * dx) / denom  # position along the edge
            if t > 1e-6 and 0.0 <= u < 1.0:
                hits.append(t)
    return sorted(hits)


def fetch_m(
    lon: float,
    lat: float,
    wind_from_deg: float,
    rings: Sequence[Ring],
) -> float:
    """Open-water distance upwind of (lon, lat) for wind blowing from `wind_from_deg`.

    `rings` is the lake outline: the shoreline first, then any islands.
    Returns 0 when the wind blows off the land at the launch point.
    """
    rings_m = [[_to_local_m(x, y, lon, lat) for x, y in ring] for ring in rings]
    # Upwind is the direction the wind comes from; 0 deg = north, clockwise.
    theta = math.radians(wind_from_deg)
    dx, dy = math.sin(theta), math.cos(theta)
    hits = _ray_hits(dx, dy, rings_m)
    if not hits:
        return 0.0
    inside = len(hits) % 2 == 1
    if inside:
        return hits[0]
    # On land: only count water that starts within the shore tolerance.
    if hits[0] <= SHORE_TOLERANCE_M and len(hits) >= 2:
        return hits[1] - hits[0]
    return 0.0
