"""The latest cloud-free Sentinel-2 picture of a lake, for the app's satellite card.

Sentinel-2 (ESA, Copernicus) photographs every lake in Germany every two to
five days at 10 m. The backend asks the Copernicus Data Space Ecosystem's
Sentinel Hub with the project's free account (CDSE_CLIENT_ID /
CDSE_CLIENT_SECRET; app users need none):
1. the catalogue for passes over the lake in the last MAX_AGE_DAYS,
   newest first, whose image tile is not mostly cloud,
2. for up to CANDIDATES of them, the share of the lake itself under cloud
   (Statistical API on the scene classification band SCL),
3. the first pass with at most MAX_LAKE_CLOUD of the lake under cloud as a
   true-colour JPEG of the lake and its shore (Process API).

The free account allows about 10,000 requests a month, so the publishing job
looks for new pictures at most every REFRESH_HOURS per lake.

Data: "Contains modified Copernicus Sentinel data <year>".
"""

from __future__ import annotations

import logging
import math
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import httpx

from . import lake_ice_satellite

SH = "https://sh.dataspace.copernicus.eu"
COLLECTION = "sentinel-2-l2a"
MAX_AGE_DAYS = 30
TILE_MAX_CLOUD = 60  # per cent of the whole 100 km image tile
CANDIDATES = 3
MAX_LAKE_CLOUD = 0.2
MAX_PIXELS = 1280  # longer side of the picture
METRES_PER_PIXEL = 10.0
MARGIN = 0.08  # shore around the lake, as a share of its size

log = logging.getLogger(__name__)

CLOUD_SCRIPT = """//VERSION=3
function setup() {
  return {input: [{bands: ["SCL", "dataMask"]}],
          output: [{id: "cloud", bands: 1, sampleType: "FLOAT32"}, {id: "dataMask", bands: 1}]};
}
// Scene classes 3 cloud shadow, 8 and 9 cloud, 10 thin cirrus.
function evaluatePixel(s) {
  return {cloud: [[3, 8, 9, 10].indexOf(s.SCL) >= 0 ? 1 : 0], dataMask: [s.dataMask]};
}
"""

PICTURE_SCRIPT = """//VERSION=3
function setup() {
  return {input: ["B02", "B03", "B04"], output: {bands: 3}};
}
function evaluatePixel(s) {
  return [2.5 * s.B04, 2.5 * s.B03, 2.5 * s.B02];
}
"""


@dataclass(frozen=True)
class Picture:
    taken: datetime
    lake_cloud: float
    bbox: tuple[float, float, float, float]  # west, south, east, north
    width: int
    height: int
    jpeg: bytes


def frame(ring: list[tuple[float, float]]) -> tuple[tuple[float, float, float, float], int, int]:
    """The picture's box around the lake (lon/lat) and its size in pixels."""
    xs, ys = zip(*ring)
    west, east, south, north = min(xs), max(xs), min(ys), max(ys)
    dx, dy = (east - west) * MARGIN, (north - south) * MARGIN
    west, east, south, north = west - dx, east + dx, south - dy, north + dy
    mid_lat = math.radians((south + north) / 2)
    width_m = (east - west) * 111_320 * math.cos(mid_lat)
    height_m = (north - south) * 110_540
    scale = max(METRES_PER_PIXEL, max(width_m, height_m) / MAX_PIXELS)
    return (west, south, east, north), max(1, round(width_m / scale)), max(1, round(height_m / scale))


def _polygon(ring: list[tuple[float, float]], max_points: int = 300) -> dict:
    step = max(1, len(ring) // max_points)
    pts = [list(p) for p in ring[::step]]
    return {"type": "Polygon", "coordinates": [pts + [pts[0]]]}


def _passes(client: httpx.Client, bbox, now: datetime) -> list[datetime]:
    body = {
        "collections": [COLLECTION],
        "bbox": list(bbox),
        "datetime": f"{(now - timedelta(days=MAX_AGE_DAYS)).strftime('%Y-%m-%dT%H:%M:%SZ')}/{now.strftime('%Y-%m-%dT%H:%M:%SZ')}",
        "filter": f"eo:cloud_cover < {TILE_MAX_CLOUD}",
        "filter-lang": "cql2-text",
        "fields": {"include": ["properties.datetime", "properties.eo:cloud_cover"]},
        "limit": 50,
    }
    resp = client.post(f"{SH}/api/v1/catalog/1.0.0/search", json=body, timeout=60)
    resp.raise_for_status()
    taken = {
        datetime.fromisoformat(f["properties"]["datetime"].replace("Z", "+00:00"))
        for f in resp.json().get("features", [])
    }
    # Neighbouring tiles of one pass are minutes apart; keep one time per day.
    by_day: dict = {}
    for t in sorted(taken, reverse=True):
        by_day.setdefault(t.date(), t)
    return list(by_day.values())


def _lake_cloud(client: httpx.Client, ring, taken: datetime) -> float | None:
    day = taken.strftime("%Y-%m-%d")
    request = {
        "input": {
            "bounds": {"geometry": _polygon(ring), "properties": {"crs": "http://www.opengis.net/def/crs/EPSG/0/4326"}},
            "data": [{"type": COLLECTION, "dataFilter": {"mosaickingOrder": "leastCC"}}],
        },
        "aggregation": {
            "timeRange": {"from": f"{day}T00:00:00Z", "to": f"{day}T23:59:59Z"},
            "aggregationInterval": {"of": "P1D"},
            "evalscript": CLOUD_SCRIPT,
            "resx": 0.0008,
            "resy": 0.0005,
        },
    }
    resp = client.post(f"{SH}/api/v1/statistics", json=request, timeout=120)
    resp.raise_for_status()
    for entry in resp.json().get("data", []):
        stats = entry["outputs"]["cloud"]["bands"]["B0"]["stats"]
        if stats.get("sampleCount", 0) > stats.get("noDataCount", 0):
            return float(stats["mean"])
    return None


def _jpeg(client: httpx.Client, bbox, width: int, height: int, taken: datetime) -> bytes:
    day = taken.strftime("%Y-%m-%d")
    request = {
        "input": {
            "bounds": {"bbox": list(bbox), "properties": {"crs": "http://www.opengis.net/def/crs/EPSG/0/4326"}},
            "data": [
                {
                    "type": COLLECTION,
                    "dataFilter": {
                        "timeRange": {"from": f"{day}T00:00:00Z", "to": f"{day}T23:59:59Z"},
                        "mosaickingOrder": "leastCC",
                    },
                }
            ],
        },
        "output": {
            "width": width,
            "height": height,
            "responses": [{"identifier": "default", "format": {"type": "image/jpeg", "quality": 85}}],
        },
        "evalscript": PICTURE_SCRIPT,
    }
    resp = client.post(f"{SH}/api/v1/process", json=request, headers={"Accept": "image/jpeg"}, timeout=120)
    resp.raise_for_status()
    return resp.content


def latest(client: httpx.Client, ring: list[tuple[float, float]], now: datetime | None = None) -> Picture | None:
    """The newest picture with the lake mostly free of cloud, or None. `client` carries the token."""
    now = now or datetime.now(timezone.utc)
    bbox, width, height = frame(ring)
    for taken in _passes(client, bbox, now)[:CANDIDATES]:
        cloud = _lake_cloud(client, ring, taken)
        if cloud is None or cloud > MAX_LAKE_CLOUD:
            continue
        return Picture(taken, cloud, bbox, width, height, _jpeg(client, bbox, width, height, taken))
    return None


def client() -> httpx.Client | None:
    """A client signed in with the project's account, or None without one."""
    if not (os.environ.get("CDSE_CLIENT_ID") and os.environ.get("CDSE_CLIENT_SECRET")):
        return None
    c = httpx.Client()
    try:
        c.headers["Authorization"] = f"Bearer {lake_ice_satellite._token(c)}"
    except httpx.HTTPError as e:
        log.warning("Copernicus sign-in failed: %r", e)
        c.close()
        return None
    return c
