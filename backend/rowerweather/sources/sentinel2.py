"""Sentinel-2 pictures of a lake, for the app's satellite card.

Sentinel-2 (ESA, Copernicus) photographs every lake in Germany every two to
five days at 10 m. The backend asks the Copernicus Data Space Ecosystem's
Sentinel Hub with the project's free account (CDSE_CLIENT_ID /
CDSE_CLIENT_SECRET; app users need none):
1. one Statistical API request for the share of the lake under cloud on every
   day with a pass (scene classification band SCL), over the last SEARCH_DAYS,
2. a true-colour JPEG of the lake and its shore (Process API) for the newest
   pass, clouds or not ("latest"), the newest with at most
   MOSTLY_CLEAR_MAX_LAKE_CLOUD under cloud ("mostly clear") and the newest with at most
   CLEAR_MAX_LAKE_CLOUD of it under cloud ("clearest"), when they are new.
A lake that has never had a picture is searched once over FIRST_SEARCH_DAYS.

The free account allows about 10,000 requests a month; a look at a lake takes
one request plus one per new picture.

Data: "Contains modified Copernicus Sentinel data <year>".
"""

from __future__ import annotations

import logging
import math
import os
import time
from dataclasses import dataclass
from datetime import date, timedelta

import httpx

from . import lake_ice_satellite

SH = "https://sh.dataspace.copernicus.eu"
COLLECTION = "sentinel-2-l2a"
SEARCH_DAYS = 30
FIRST_SEARCH_DAYS = 365
# Days per Statistical API request on the long first search.
CHUNK_DAYS = 92
# A pass counts when it saw nearly the whole lake (the swath edge can cut a lake).
MIN_SEEN = 0.9
# The latest picture is shown whatever the cloud; the clearest is the newest with at most this much.
CLEAR_MAX_LAKE_CLOUD = 0.1
# In between: the newest pass that shows most of the lake, for cloudy weeks.
MOSTLY_CLEAR_MAX_LAKE_CLOUD = 0.3
MAX_PIXELS = 1280  # longer side of the picture
METRES_PER_PIXEL = 10.0
MARGIN = 0.08  # shore around the lake, as a share of its size

# The free account allows only a few requests a minute: pause between requests, and wait out a refusal.
PAUSE_SECONDS = 2.0
RATE_LIMIT_WAITS = (30, 65)

log = logging.getLogger(__name__)
# Requests sent since the process started, for the usage report.
requests_made = 0


def _post(client: httpx.Client, url: str, **kwargs) -> httpx.Response:
    global requests_made
    for wait in (*RATE_LIMIT_WAITS, None):
        time.sleep(PAUSE_SECONDS)
        requests_made += 1
        resp = client.post(url, **kwargs)
        if resp.status_code != 429 or wait is None:
            resp.raise_for_status()
            return resp
        time.sleep(wait)
    raise AssertionError("unreachable")

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
class Pass:
    day: date
    lake_cloud: float  # share of the lake under cloud, 0...1


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


def cloud_by_day(client: httpx.Client, ring, start: date, end: date) -> list[Pass]:
    """Passes from `start` to `end` (inclusive) that saw nearly the whole lake, oldest first."""
    seen: dict[date, tuple[int, float]] = {}
    day = start
    while day <= end:
        stop = min(end, day + timedelta(days=CHUNK_DAYS - 1))
        request = {
            "input": {
                "bounds": {"geometry": _polygon(ring), "properties": {"crs": "http://www.opengis.net/def/crs/EPSG/0/4326"}},
                "data": [{"type": COLLECTION, "dataFilter": {"mosaickingOrder": "leastCC"}}],
            },
            "aggregation": {
                # Each interval must span whole days, or the API leaves it out.
                "timeRange": {"from": f"{day}T00:00:00Z", "to": f"{stop + timedelta(days=1)}T00:00:00Z"},
                "aggregationInterval": {"of": "P1D"},
                "evalscript": CLOUD_SCRIPT,
                "resx": 0.0008,
                "resy": 0.0005,
            },
        }
        resp = _post(client, f"{SH}/api/v1/statistics", json=request, timeout=180)
        for entry in resp.json().get("data", []):
            stats = entry["outputs"]["cloud"]["bands"]["B0"]["stats"]
            valid = stats.get("sampleCount", 0) - stats.get("noDataCount", 0)
            if valid > 0 and stats.get("mean") is not None:
                seen[date.fromisoformat(entry["interval"]["from"][:10])] = (valid, float(stats["mean"]))
        day = stop + timedelta(days=1)
    if not seen:
        return []
    full = max(valid for valid, _ in seen.values())
    return [Pass(d, cloud) for d, (valid, cloud) in sorted(seen.items()) if valid >= MIN_SEEN * full]


def choose(passes: list[Pass]) -> tuple[Pass | None, Pass | None, Pass | None]:
    """The latest pass, the latest mostly clear one and the latest clear one."""
    latest = passes[-1] if passes else None
    mostly_clear = next((p for p in reversed(passes) if p.lake_cloud <= MOSTLY_CLEAR_MAX_LAKE_CLOUD), None)
    clearest = next((p for p in reversed(passes) if p.lake_cloud <= CLEAR_MAX_LAKE_CLOUD), None)
    return latest, mostly_clear, clearest


def jpeg(client: httpx.Client, bbox, width: int, height: int, day: date) -> bytes:
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
    resp = _post(client, f"{SH}/api/v1/process", json=request, headers={"Accept": "image/jpeg"}, timeout=120)
    return resp.content


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
