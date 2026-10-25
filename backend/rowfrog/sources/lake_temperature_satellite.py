"""Lake surface temperature seen from space, for lakes without a GKD station.

Two free sources, both measuring the top millimetre of the water ("skin"):

- Copernicus Lake Surface Water Temperature (LSWT): Sentinel-3 SLSTR, 1 km,
  one file per ten days (1st-10th, 11th-20th, 21st-end of month), published
  about three days after the period ends. Only lakes in its lake list have
  values; in Bavaria those are Bodensee, Starnberger See, Ammersee, Chiemsee
  and Walchensee. Downloaded from the Copernicus Data Space Ecosystem (CDSE)
  with the project's account (CDSE_CLIENT_ID / CDSE_CLIENT_SECRET), like the
  satellite ice map (sources/lake_ice_satellite.py).
- Landsat 8/9 Collection 2 surface temperature: 100 m thermal band on a 30 m
  grid, one pass every 8 days with both satellites at about 10:00 UTC, so
  smaller lakes like Simssee or Wörthsee are seen too, but only on clear days.
  Read from Microsoft's Planetary Computer, which needs no account.

Each reading keeps only pixels away from the shore, so the land around the
lake does not warm or cool the value, and only good pixels: LSWT quality 4-5,
Landsat pixels flagged clear. A Landsat pass counts when it saw at least
LANDSAT_SEEN_SHARE of the lake. The newest readings are carried forward to
today by water_estimate.py.

Reading the files needs rasterio, which only the publishing job installs;
without it fetch() returns nothing.

Data: Copernicus Land Monitoring Service (free and open, credit
"Copernicus"); Landsat courtesy of the U.S. Geological Survey (public domain).
"""

from __future__ import annotations

import io
import logging
import math
import os
import statistics
import tempfile
import zipfile
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

import httpx

from . import lake_ice_satellite

CATALOGUE = lake_ice_satellite.CATALOGUE
DOWNLOAD = lake_ice_satellite.DOWNLOAD
STAC = "https://planetarycomputer.microsoft.com/api/stac/v1/search"
SAS_TOKEN = "https://planetarycomputer.microsoft.com/api/sas/v1/token/landsat-c2-l2"

LSWT = "copernicus-lswt"
LANDSAT = "landsat"
# LSWT quality levels 4 (acceptable) and 5 (best); 1-3 are bad to low.
LSWT_MIN_QUALITY = 4
LSWT_MIN_PIXELS = 3
LSWT_SHORE_M = 700
# Landsat: clear share of the lake and least clear pixels (30 m each) for a pass to count.
LANDSAT_SEEN_SHARE = 0.3
LANDSAT_MIN_PIXELS = 50
# Pixels nearer the shore than this many 30 m pixels are left out (one 100 m thermal pixel).
LANDSAT_SHORE_PIXELS = 4
# QA_PIXEL bits: fill, dilated cloud, cloud, cloud shadow; and water.
LANDSAT_BAD_BITS = 0b11011
LANDSAT_WATER_BIT = 1 << 7
LANDSAT_DAYS = 16
# Skin temperatures outside this range are clouds or errors.
PLAUSIBLE_C = (-2.0, 35.0)

log = logging.getLogger(__name__)
# Requests sent since the process started, for the usage report.
requests_made = 0


@dataclass(frozen=True)
class Reading:
    """One satellite look at a lake: the median skin temperature of its good pixels."""

    source: str  # LSWT or LANDSAT
    day: date  # pass day; for LSWT the middle of its ten days
    celsius: float
    pixels: int
    # LSWT: the ten days it averages; Landsat: the pass time and satellite ("landsat-9").
    first: date | None = None
    last: date | None = None
    time: datetime | None = None
    platform: str | None = None


# --- shapes ----------------------------------------------------------------------------------


def inside(x: float, y: float, ring: list[tuple[float, float]]) -> bool:
    return lake_ice_satellite.inside(x, y, ring)


def shore_distance_m(lon: float, lat: float, ring: list[tuple[float, float]]) -> float:
    """Distance to the nearest shore segment, on a flat local grid."""
    kx = 111_320 * math.cos(math.radians(lat))
    ky = 110_540
    best = math.inf
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        ax, ay = (x1 - lon) * kx, (y1 - lat) * ky
        bx, by = (x2 - lon) * kx, (y2 - lat) * ky
        dx, dy = bx - ax, by - ay
        t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(ax + t * dx, ay + t * dy))
    return best


def thin(ring: list[tuple[float, float]], points: int = 1500) -> list[tuple[float, float]]:
    """Long OpenStreetMap shores thinned for speed; a few metres off does not matter at 30 m to 1 km."""
    step = max(1, len(ring) // points)
    return ring[::step]


def plausible(c: float) -> bool:
    return PLAUSIBLE_C[0] <= c <= PLAUSIBLE_C[1]


# --- Copernicus LSWT ------------------------------------------------------------------------------


def configured() -> bool:
    return lake_ice_satellite.configured()


def lswt_period(first: date) -> tuple[date, date]:
    """The ten days a file starting on `first` averages (the third runs to the month's end)."""
    if first.day < 21:
        return first, first + timedelta(days=9)
    next_month = (first.replace(day=28) + timedelta(days=4)).replace(day=1)
    return first, next_month - timedelta(days=1)


def lswt_products(client: httpx.Client, since: date) -> list[dict]:
    flt = f"contains(Name,'c_gls_LSWT_') and endswith(Name,'_cog') and ContentDate/Start ge {since.isoformat()}T00:00:00.000Z"
    resp = client.get(CATALOGUE, params={"$filter": flt, "$top": "60", "$orderby": "ContentDate/Start asc"}, timeout=60)
    resp.raise_for_status()
    return resp.json().get("value", [])


def read_lswt(temperature_path: str, quality_path: str, first: date, shores: dict[str, list[tuple[float, float]]]) -> dict[str, Reading]:
    """Readings per lake from one LSWT file pair (temperature and quality tiffs)."""
    import numpy as np
    import rasterio
    from rasterio.windows import from_bounds

    start, end = lswt_period(first)
    middle = start + (end - start) / 2
    found = {}
    with rasterio.open(temperature_path) as ds, rasterio.open(quality_path) as qs:
        for lake_id, ring in shores.items():
            xs, ys = zip(*ring)
            window = from_bounds(min(xs), min(ys), max(xs), max(ys), ds.transform).round_offsets().round_lengths()
            data = ds.read(1, window=window, boundless=True, masked=True)
            quality = qs.read(1, window=window, boundless=True, fill_value=0)
            missing = np.ma.getmaskarray(data)
            t = ds.window_transform(window)
            values = []
            for r in range(data.shape[0]):
                for c in range(data.shape[1]):
                    if missing[r, c] or quality[r, c] < LSWT_MIN_QUALITY:
                        continue
                    lon, lat = t * (c + 0.5, r + 0.5)
                    if inside(lon, lat, ring) and shore_distance_m(lon, lat, ring) >= LSWT_SHORE_M:
                        celsius = float(data.data[r, c]) * ds.scales[0] + ds.offsets[0] - 273.15
                        if plausible(celsius):
                            values.append(celsius)
            if len(values) >= LSWT_MIN_PIXELS:
                found[lake_id] = Reading(LSWT, middle, round(statistics.median(values), 1), len(values), start, end)
    return found


def _lswt_files(content: bytes, folder: str) -> tuple[str, str]:
    with zipfile.ZipFile(io.BytesIO(content)) as z:
        names = z.namelist()
        temperature = z.extract(next(n for n in names if "LSWT-LSWT_" in n), folder)
        quality = z.extract(next(n for n in names if "LSWT-QLEVEL_" in n), folder)
    return temperature, quality


def fetch_lswt(client: httpx.Client, token: str, product: dict, shores: dict[str, list[tuple[float, float]]]) -> dict[str, Reading]:
    """Download one LSWT file (about 26 MB) and read every lake in it."""
    global requests_made
    first = date.fromisoformat(product["ContentDate"]["Start"][:10])
    resp = client.get(DOWNLOAD.format(id=product["Id"]), headers={"Authorization": f"Bearer {token}"}, timeout=300, follow_redirects=True)
    requests_made += 1
    resp.raise_for_status()
    with tempfile.TemporaryDirectory() as folder:
        return read_lswt(*_lswt_files(resp.content, folder), first, shores)


# --- Landsat ------------------------------------------------------------------------------


class _Sas:
    """A read token for the Landsat files on the Planetary Computer, renewed before it runs out."""

    def __init__(self) -> None:
        self.token = ""
        self.until = datetime.min.replace(tzinfo=timezone.utc)

    def get(self, client: httpx.Client) -> str:
        global requests_made
        now = datetime.now(timezone.utc)
        if now >= self.until:
            resp = client.get(SAS_TOKEN, timeout=30)
            requests_made += 1
            resp.raise_for_status()
            self.token = resp.json()["token"]
            self.until = now + timedelta(minutes=30)
        return self.token


_sas = _Sas()


def landsat_scenes(client: httpx.Client, bbox: list[float], start: date, end: date) -> list[dict]:
    """Landsat 8/9 Level-2 scenes touching `bbox` (lon/lat), oldest first."""
    global requests_made
    body = {"collections": ["landsat-c2-l2"], "bbox": bbox, "datetime": f"{start}T00:00:00Z/{end}T23:59:59Z", "limit": 250}
    resp = client.post(STAC, json=body, timeout=90)
    requests_made += 1
    resp.raise_for_status()
    return sorted(resp.json()["features"], key=lambda f: f["properties"]["datetime"])


def read_landsat(client: httpx.Client, scene: dict, shores: dict[str, list[tuple[float, float]]]) -> dict[str, tuple[Reading | None, float]]:
    """Per lake in the scene: the reading (None when too cloudy) and the clear share of the lake."""
    import rasterio
    from rasterio.features import rasterize
    from rasterio.warp import transform as warp
    from rasterio.windows import from_bounds

    os.environ.setdefault("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
    props = scene["properties"]
    when = datetime.fromisoformat(props["datetime"].replace("Z", "+00:00"))
    token = _sas.get(client)
    found: dict[str, tuple[Reading | None, float]] = {}
    with rasterio.open(scene["assets"]["lwir11"]["href"] + "?" + token) as st, rasterio.open(
        scene["assets"]["qa_pixel"]["href"] + "?" + token
    ) as qa:
        b = st.bounds
        for lake_id, ring in shores.items():
            xs, ys = warp("EPSG:4326", st.crs, [p[0] for p in ring], [p[1] for p in ring])
            left, right, bottom, top = min(xs), max(xs), min(ys), max(ys)
            if left < b.left or right > b.right or bottom < b.bottom or top > b.top:
                continue  # only partly in this scene; the neighbouring scene of the same pass has it whole
            window = from_bounds(left, bottom, right, top, st.transform).round_offsets().round_lengths()
            temp = st.read(1, window=window, boundless=True, fill_value=0)
            bits = qa.read(1, window=window, boundless=True, fill_value=1)
            lake = rasterize([{"type": "Polygon", "coordinates": [list(zip(xs, ys))]}], out_shape=temp.shape, transform=st.window_transform(window)).astype(bool)
            for _ in range(LANDSAT_SHORE_PIXELS):
                lake[1:, :] &= lake[:-1, :].copy()
                lake[:-1, :] &= lake[1:, :].copy()
                lake[:, 1:] &= lake[:, :-1].copy()
                lake[:, :-1] &= lake[:, 1:].copy()
            total = int(lake.sum())
            if not total:
                continue
            good = lake & ((bits & LANDSAT_BAD_BITS) == 0) & ((bits & LANDSAT_WATER_BIT) != 0) & (temp != 0)
            values = [c for c in (temp[good] * 0.00341802 + 149.0 - 273.15).tolist() if plausible(c)]
            share = len(values) / total
            reading = None
            if share >= LANDSAT_SEEN_SHARE and len(values) >= LANDSAT_MIN_PIXELS:
                reading = Reading(LANDSAT, when.date(), round(statistics.median(values), 1), len(values), time=when, platform=props.get("platform"))
            found[lake_id] = (reading, share)
    return found


def fetch_landsat(client: httpx.Client, shores: dict[str, list[tuple[float, float]]], today: date, days: int = LANDSAT_DAYS) -> dict[str, list[Reading]]:
    """Clear Landsat readings of the last `days` per lake, oldest first."""
    global requests_made
    if not shores:
        return {}
    xs = [x for ring in shores.values() for x, _ in ring]
    ys = [y for ring in shores.values() for _, y in ring]
    readings: dict[str, list[Reading]] = {}
    for scene in landsat_scenes(client, [min(xs), min(ys), max(xs), max(ys)], today - timedelta(days=days), today):
        # Only lakes this scene's footprint can hold are read.
        lon0, lat0, lon1, lat1 = scene.get("bbox", [min(xs), min(ys), max(xs), max(ys)])
        here = {k: r for k, r in shores.items() if lon0 <= min(x for x, _ in r) and max(x for x, _ in r) <= lon1 and lat0 <= min(y for _, y in r) and max(y for _, y in r) <= lat1}
        if not here:
            continue
        try:
            requests_made += 2
            for lake_id, (reading, _) in read_landsat(client, scene, here).items():
                if reading:
                    readings.setdefault(lake_id, []).append(reading)
        except Exception as e:  # noqa: BLE001 - one bad scene must not stop the rest
            log.warning("Landsat scene %s unreadable: %r", scene.get("id"), e)
    return readings


# --- both ------------------------------------------------------------------------------------


def fetch(
    shores: dict[str, list[tuple[float, float]]],
    today: date,
    lswt_cache: dict[str, dict[str, Reading]] | None = None,
) -> dict[str, list[Reading]]:
    """The newest readings per lake (oldest first) from both sources.

    `lswt_cache` maps LSWT file names already read to their readings, so each
    ten-day file is downloaded once; new files are added to it.
    """
    try:
        import rasterio  # noqa: F401
    except ImportError:
        return {}
    shores = {k: thin(r) for k, r in shores.items()}
    readings: dict[str, list[Reading]] = {}
    with httpx.Client() as client:
        if configured():
            cache = lswt_cache if lswt_cache is not None else {}
            try:
                products = lswt_products(client, today - timedelta(days=40))
                new = [p for p in products if p["Name"] not in cache]
                if new:
                    token = lake_ice_satellite._token(client)
                    for product in new[-2:]:
                        cache[product["Name"]] = fetch_lswt(client, token, product, shores)
                for name in sorted(cache)[-2:]:
                    for lake_id, reading in cache[name].items():
                        readings.setdefault(lake_id, []).append(reading)
            except (httpx.HTTPError, KeyError, StopIteration, zipfile.BadZipFile) as e:
                log.warning("Copernicus lake temperature unavailable: %r", e)
        try:
            for lake_id, found in fetch_landsat(client, shores, today).items():
                readings.setdefault(lake_id, []).extend(found)
        except httpx.HTTPError as e:
            log.warning("Landsat lake temperature unavailable: %r", e)
    for found in readings.values():
        found.sort(key=lambda r: r.time or datetime.combine(r.day, datetime.min.time(), tzinfo=timezone.utc))
    return readings
