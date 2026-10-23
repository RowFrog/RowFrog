"""Lake ice seen from space: Copernicus Lake Ice Extent 250 m (LIE250).

A daily map for continental Europe from the VIIRS instrument (NOAA-20), made
by Syke and FMI for the Copernicus Land Monitoring Service. Each 250 m pixel on
a lake is (1) snow-covered ice, (2) clear or partly snow-covered ice or
(3) open water; under clouds it has no value. The files are in the Copernicus
Data Space Ecosystem (CDSE) catalogue and are downloaded with the project's
free CDSE account (CDSE_CLIENT_ID / CDSE_CLIENT_SECRET); app users need none.

The backend reads the last few days for every lake with an outline and keeps,
per lake and day, how much of the lake was seen and how much of that was ice.
At 250 m only larger lakes have enough pixels (Starnberger See ~1000,
Ammersee ~900, the Oberschleißheim regatta course none), and on most winter
days clouds hide them, so ice.with_satellite() uses a pass only as a check on
the model, never on its own.

Reading the files needs rasterio, which only the publishing job installs;
without it, or without the account, fetch() returns nothing.

Data: Copernicus Land Monitoring Service, free and open, credit "Copernicus".
"""

from __future__ import annotations

import io
import logging
import os
import struct
import tempfile
import zipfile
import zlib
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Iterable

import httpx

TOKEN_URL = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"
CATALOGUE = "https://catalogue.dataspace.copernicus.eu/odata/v1/Products"
DOWNLOAD = "https://download.dataspace.copernicus.eu/odata/v1/Products({id})/$value"

SNOW_ICE, CLEAR_ICE, OPEN_WATER = 1, 2, 3
# Lakes with fewer pixels inside their outline are too small for a 250 m map.
MIN_PIXELS = 40
# Days back that are read; the newest file is usually from yesterday.
DAYS = 4

log = logging.getLogger(__name__)
# Requests sent since the process started, for the usage report.
requests_made = 0


@dataclass(frozen=True)
class SatellitePass:
    day: date
    pixels: int  # inside the lake's outline
    ice: int
    water: int
    # The map around the lake for the app's ice overlay: one class per pixel, row by
    # row from the north, 0 outside the lake or under cloud; and its lon/lat box.
    classes: bytes = field(default=b"", compare=False, repr=False)
    width: int = field(default=0, compare=False)
    bbox: tuple[float, float, float, float] | None = field(default=None, compare=False)  # west, south, east, north

    @property
    def seen_share(self) -> float:
        return (self.ice + self.water) / self.pixels if self.pixels else 0.0

    @property
    def ice_share(self) -> float:
        """Ice as a share of the part of the lake that was seen."""
        seen = self.ice + self.water
        return self.ice / seen if seen else 0.0


def count(values: Iterable[int], day: date) -> SatellitePass:
    pixels = ice = water = 0
    for v in values:
        pixels += 1
        if v in (SNOW_ICE, CLEAR_ICE):
            ice += 1
        elif v == OPEN_WATER:
            water += 1
    return SatellitePass(day, pixels, ice, water)


def inside(x: float, y: float, ring: list[tuple[float, float]]) -> bool:
    hit, j = False, len(ring) - 1
    for i, (xi, yi) in enumerate(ring):
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def png(p: SatellitePass) -> bytes | None:
    """The pass as a small transparent PNG for the app: ice white, open water blue, the rest clear."""
    if not p.classes or not p.width:
        return None
    colours = {SNOW_ICE: (255, 255, 255, 230), CLEAR_ICE: (200, 235, 255, 230), OPEN_WATER: (0, 90, 200, 90)}
    rows = len(p.classes) // p.width
    raw = bytearray()
    for r in range(rows):
        raw.append(0)  # no filter
        for v in p.classes[r * p.width : (r + 1) * p.width]:
            raw += bytes(colours.get(v, (0, 0, 0, 0)))

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    header = struct.pack(">IIBBBBB", p.width, rows, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def configured() -> bool:
    if not (os.environ.get("CDSE_CLIENT_ID") and os.environ.get("CDSE_CLIENT_SECRET")):
        return False
    try:
        import rasterio  # noqa: F401
    except ImportError:
        return False
    return True


def _token(client: httpx.Client) -> str:
    resp = client.post(
        TOKEN_URL,
        data={
            "grant_type": "client_credentials",
            "client_id": os.environ["CDSE_CLIENT_ID"],
            "client_secret": os.environ["CDSE_CLIENT_SECRET"],
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def _products(client: httpx.Client, today: date) -> list[dict]:
    start = (today - timedelta(days=DAYS)).isoformat()
    flt = (
        "contains(Name,'LIE250') and contains(Name,'CEURO') and endswith(Name,'_cog') "
        f"and ContentDate/Start ge {start}T00:00:00.000Z"
    )
    resp = client.get(CATALOGUE, params={"$filter": flt, "$top": "20", "$orderby": "ContentDate/Start asc"}, timeout=60)
    resp.raise_for_status()
    return resp.json().get("value", [])


def _write_tif(content: bytes, path: str) -> None:
    if content[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(content)) as z:
            content = z.read(next(n for n in z.namelist() if n.lower().endswith((".tif", ".tiff"))))
    with open(path, "wb") as f:
        f.write(content)


def _read(path: str, day: date, shores: dict[str, list[tuple[float, float]]]) -> dict[str, SatellitePass]:
    import rasterio
    from rasterio.windows import from_bounds

    found = {}
    with rasterio.open(path) as ds:
        for lake_id, ring in shores.items():
            xs, ys = zip(*ring)
            window = from_bounds(min(xs), min(ys), max(xs), max(ys), ds.transform).round_offsets().round_lengths()
            data = ds.read(1, window=window, boundless=True, fill_value=0)
            t = ds.window_transform(window)
            rows, cols = data.shape
            classes = bytearray(rows * cols)
            values = []
            for r in range(rows):
                for c in range(cols):
                    if inside(*(t * (c + 0.5, r + 0.5)), ring):
                        values.append(int(data[r, c]))
                        classes[r * cols + c] = data[r, c]
            p = count(values, day)
            if p.pixels >= MIN_PIXELS:
                west, north = t * (0, 0)
                east, south = t * (cols, rows)
                found[lake_id] = SatellitePass(
                    day, p.pixels, p.ice, p.water, bytes(classes), cols, (west, south, east, north)
                )
    return found


def fetch(shores: dict[str, list[tuple[float, float]]], today: date) -> dict[str, list[SatellitePass]]:
    """Passes of the last days per lake (oldest first), for lakes whose outline `shores` gives in lon/lat."""
    if not configured() or not shores:
        return {}
    global requests_made
    passes: dict[str, list[SatellitePass]] = {}
    try:
        with httpx.Client() as client, tempfile.TemporaryDirectory() as folder:
            products = _products(client, today)
            client.headers["Authorization"] = f"Bearer {_token(client)}"
            requests_made += 2 + len(products)
            for product in products:
                day = date.fromisoformat(product["ContentDate"]["Start"][:10])
                resp = client.get(DOWNLOAD.format(id=product["Id"]), timeout=120, follow_redirects=True)
                resp.raise_for_status()
                path = os.path.join(folder, "lie.tif")
                _write_tif(resp.content, path)
                for lake_id, p in _read(path, day, shores).items():
                    passes.setdefault(lake_id, []).append(p)
    except (httpx.HTTPError, OSError, KeyError, ValueError, StopIteration, zipfile.BadZipFile) as e:
        log.warning("Satellite lake ice unavailable: %r", e)
    return passes
