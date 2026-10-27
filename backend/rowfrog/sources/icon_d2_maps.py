"""Weather maps from DWD's ICON-D2 model: wind, gusts, temperature, feels
like, humidity, air pressure, visibility and rain, hour by hour for 48 hours.

DWD publishes every run of ICON-D2 (every 3 hours) as open data on a
regular grid of about 2 km over Germany, Switzerland, Austria and their
neighbours. The publish job reads the newest complete run once, cuts it into
map tiles around the clubs and writes each value as one small file the app
colours itself, so it can show any unit, read the value at the club and draw
the wind arrows:

    maps/index              run, hours, tiles, and how to read the values
    maps/<tile>/<value>     raw deflate of uint8 [hour][row][column]

Every hour for the first day, then every 3 hours to 48 hours, at about 4 km:
some 300 KB a value and tile. The wind's direction is kept only where the
app draws an arrow, every ARROW_STEP pixels.

Rows run north to south and are spaced evenly in web-mercator, so a tile
lies straight on Apple's map; columns are evenly spaced in longitude.
Value = offset + scale × byte; 255 means no value (outside the model).
No Open-Meteo calls are used.

Data: Deutscher Wetterdienst, CC BY 4.0 (credit "Deutscher Wetterdienst").
"""

from __future__ import annotations

import bz2
import json
import math
import zlib
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import numpy as np

BASE = "https://opendata.dwd.de/weather/nwp/icon-d2/grib/"
HOURS = 48
# The model's variables the maps need.
SOURCES = ["u_10m", "v_10m", "vmax_10m", "t_2m", "relhum_2m", "pmsl", "vis", "tot_prec"]
# Map tiles: 6° × 4° (about 450 × 450 km), centred every 3° × 2°, so a club is
# always at least 1.5° and 1° from the edge of its tile.
TILE_LON, TILE_LAT = 6.0, 4.0
STEP_LON, STEP_LAT = 3.0, 2.0
ORIGIN_LON, ORIGIN_LAT = 0.0, 44.0
# Columns and rows per tile: about 4 km, twice the model's own spacing;
# the app draws them smoothed.
COLS, ROWS = 150, 130
# Hours from the run: each hour for a day, then every 3 hours.
STEPS = list(range(0, 25)) + list(range(27, HOURS + 1, 3))
# Wind arrows: one every ARROW_STEP pixels, the first at half a step.
ARROW_STEP = 5
PARALLEL = 8
MISSING = 255


@dataclass(frozen=True)
class Encoding:
    offset: float
    scale: float
    unit: str


# How each value is stored in a byte (0–254).
VALUES: dict[str, Encoding] = {
    "wind": Encoding(0, 0.2, "m/s"),  # 0–50.8 m/s
    "windDirection": Encoding(0, 1.5, "°"),  # where the wind comes from, 0–360
    "gust": Encoding(0, 0.2, "m/s"),
    "temperature": Encoding(-40, 0.4, "°C"),  # −40 to +61.6 °C
    "feelsLike": Encoding(-40, 0.4, "°C"),
    "humidity": Encoding(0, 0.5, "%"),
    "pressure": Encoding(940, 0.5, "hPa"),  # 940–1067 hPa
    "visibility": Encoding(0, 0.1, "km"),  # 0–25.4 km, more is shown as 25.4
    "rain": Encoding(0, 0.1, "mm/h"),  # 0–25.4 mm an hour, more is shown as 25.4
}

requests_made = 0


@dataclass(frozen=True)
class Tile:
    id: str
    west: float
    south: float

    @property
    def east(self) -> float:
        return self.west + TILE_LON

    @property
    def north(self) -> float:
        return self.south + TILE_LAT

    def as_json(self) -> dict:
        return {"id": self.id, "west": self.west, "east": self.east, "south": self.south, "north": self.north}


def tile_for(lat: float, lon: float) -> Tile:
    """The tile whose centre is nearest to a point."""
    i = round((lon - ORIGIN_LON - TILE_LON / 2) / STEP_LON)
    j = round((lat - ORIGIN_LAT - TILE_LAT / 2) / STEP_LAT)
    west = ORIGIN_LON + i * STEP_LON
    south = ORIGIN_LAT + j * STEP_LAT
    return Tile(f"{'e' if west >= 0 else 'w'}{abs(west):g}n{south:g}", west, south)


# The model's area (ICON-D2), roughly: tiles wholly outside it are not written.
DOMAIN_WEST, DOMAIN_EAST, DOMAIN_SOUTH, DOMAIN_NORTH = -3.9, 20.3, 43.2, 58.1


def tiles_around(points: list[tuple[float, float]]) -> list[Tile]:
    """Each point's tile and the eight around it, so a map as wide as an iPad's,
    or zoomed out, is filled to its edges (about 4.5° east and west of a club and
    3° north and south) instead of only the club's own tile."""
    tiles = set()
    for lat, lon in points:
        for dlat in (-STEP_LAT, 0, STEP_LAT):
            for dlon in (-STEP_LON, 0, STEP_LON):
                t = tile_for(lat + dlat, lon + dlon)
                if t.east > DOMAIN_WEST and t.west < DOMAIN_EAST and t.north > DOMAIN_SOUTH and t.south < DOMAIN_NORTH:
                    tiles.add(t)
    return sorted(tiles, key=lambda t: t.id)


def latest_run(client: httpx.Client, now: datetime) -> datetime | None:
    """The newest run whose last hour is there for every value."""
    for back in range(0, 13, 3):
        t = now - timedelta(hours=back)
        run = t.replace(hour=t.hour - t.hour % 3, minute=0, second=0, microsecond=0)
        if all(_head_ok(client, _url(run, var, HOURS)) for var in ("vis", "pmsl")):
            return run
    return None


def _url(run: datetime, var: str, step: int) -> str:
    stamp = run.strftime("%Y%m%d%H")
    return (f"{BASE}{run:%H}/{var}/icon-d2_germany_regular-lat-lon_single-level_"
            f"{stamp}_{step:03d}_2d_{var}.grib2.bz2")


def _head_ok(client: httpx.Client, url: str) -> bool:
    global requests_made
    requests_made += 1
    try:
        return client.head(url, timeout=30).status_code == 200
    except httpx.HTTPError:
        return False


@dataclass
class Grid:
    lat0: float
    lon0: float
    dlat: float
    dlon: float
    values: np.ndarray  # [lat (south to north), lon]


def _decode(data: bytes) -> Grid:
    import eccodes  # only the publishing job needs it

    gid = eccodes.codes_new_from_message(bz2.decompress(data))
    try:
        ni, nj = eccodes.codes_get(gid, "Ni"), eccodes.codes_get(gid, "Nj")
        lat0 = eccodes.codes_get(gid, "latitudeOfFirstGridPointInDegrees")
        lat1 = eccodes.codes_get(gid, "latitudeOfLastGridPointInDegrees")
        lon0 = eccodes.codes_get(gid, "longitudeOfFirstGridPointInDegrees")
        lon1 = eccodes.codes_get(gid, "longitudeOfLastGridPointInDegrees")
        missing = eccodes.codes_get(gid, "missingValue")
        values = eccodes.codes_get_values(gid).reshape(nj, ni).astype(np.float32)
    finally:
        eccodes.codes_release(gid)
    values[values == missing] = np.nan
    if lon0 > 180:
        lon0 -= 360
    if lon1 > 180:
        lon1 -= 360
    # Rows from south to north.
    if lat0 > lat1:
        values = values[::-1]
        lat0, lat1 = lat1, lat0
    return Grid(lat0, lon0, (lat1 - lat0) / (nj - 1), (lon1 - lon0) / (ni - 1), values)


def _fetch(client: httpx.Client, url: str) -> bytes:
    global requests_made
    for attempt in range(3):
        requests_made += 1
        try:
            resp = client.get(url, timeout=120)
            resp.raise_for_status()
            return resp.content
        except httpx.HTTPError:
            if attempt == 2:
                raise
    raise RuntimeError("unreachable")


def _mercator(lat: float) -> float:
    return math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))


def _sample_index(grid: Grid, tile: Tile) -> tuple[np.ndarray, np.ndarray]:
    """Grid rows and columns for the tile's pixels (nearest point)."""
    top, bottom = _mercator(tile.north), _mercator(tile.south)
    ys = top + (np.arange(ROWS) + 0.5) / ROWS * (bottom - top)
    lats = np.degrees(2 * np.arctan(np.exp(ys)) - np.pi / 2)
    lons = tile.west + (np.arange(COLS) + 0.5) / COLS * TILE_LON
    rows = np.rint((lats - grid.lat0) / grid.dlat).astype(int)
    cols = np.rint((lons - grid.lon0) / grid.dlon).astype(int)
    return rows, cols


def _cut(grid: Grid, rows: np.ndarray, cols: np.ndarray) -> np.ndarray:
    nj, ni = grid.values.shape
    inside_r = (rows >= 0) & (rows < nj)
    inside_c = (cols >= 0) & (cols < ni)
    out = grid.values[np.clip(rows, 0, nj - 1)][:, np.clip(cols, 0, ni - 1)]
    out = out.copy()
    out[~inside_r, :] = np.nan
    out[:, ~inside_c] = np.nan
    return out


def _encode(values: np.ndarray, enc: Encoding) -> np.ndarray:
    scaled = np.rint((values - enc.offset) / enc.scale)
    out = np.clip(scaled, 0, 254)
    out[np.isnan(values)] = MISSING
    return out.astype(np.uint8)


def feels_like(t_c: np.ndarray, rh: np.ndarray, wind: np.ndarray) -> np.ndarray:
    """Steadman's apparent temperature without sunshine, as the forecasts use
    (open_meteo.apparent_temperature)."""
    vapour = rh / 100 * 6.105 * np.exp(17.27 * t_c / (237.7 + t_c))
    return t_c + 0.33 * vapour - 0.70 * wind - 4.0


def rain_rate(total: np.ndarray, before: np.ndarray | None, hours: int) -> np.ndarray:
    """Rain an hour since the step before, from the model's total since the run
    began (mm). Every 3 hours later on, so an average of those hours."""
    if before is None or hours <= 0:
        return np.zeros_like(total)
    return np.maximum(total - before, 0) / hours


def build(out: Path, points: list[tuple[float, float]], now: datetime | None = None,
          last_run: datetime | None = None) -> datetime | None:
    """Writes the maps of the newest run for the tiles around `points`.
    Returns the run written, or None when there is nothing newer than `last_run`."""
    now = now or datetime.now(timezone.utc)
    tiles = tiles_around(points)
    with httpx.Client(headers={"User-Agent": "RowFrog/0.1 (+https://github.com/RowFrog/RowFrog)"},
                      follow_redirects=True) as client:
        run = latest_run(client, now)
        if run is None or (last_run is not None and run <= last_run):
            return None
        steps = STEPS
        urls = [(var, step, _url(run, var, step)) for var in SOURCES for step in steps]
        with ThreadPoolExecutor(PARALLEL) as pool:
            raw = list(pool.map(lambda u: (u[0], u[1], _fetch(client, u[2])), urls))

    # One step at a time, so only one hour of every value is held at full size.
    by_step: dict[int, dict[str, bytes]] = {}
    for var, step, data in raw:
        by_step.setdefault(step, {})[var] = data
    del raw
    cut: dict[str, dict[str, list[np.ndarray]]] = {t.id: {v: [] for v in VALUES} for t in tiles}
    index: dict[str, tuple[np.ndarray, np.ndarray]] = {}
    totals: dict[str, np.ndarray] = {}  # tile -> rain since the run began, at the step before
    last_step = 0
    for step in steps:
        grids = {var: _decode(data) for var, data in by_step.pop(step).items()}
        g0 = grids["t_2m"]
        for tile in tiles:
            if tile.id not in index:
                index[tile.id] = _sample_index(g0, tile)
            rows, cols = index[tile.id]
            u, v = _cut(grids["u_10m"], rows, cols), _cut(grids["v_10m"], rows, cols)
            speed = np.hypot(u, v)
            t_c = _cut(g0, rows, cols) - 273.15
            rh = np.clip(_cut(grids["relhum_2m"], rows, cols), 0, 100)
            # The first hour has no gusts yet (they are the strongest of the past hour).
            gust = _cut(grids["vmax_10m"], rows, cols) if step > 0 else speed
            values = {
                "wind": speed,
                # Where the wind comes from, clockwise from north.
                "windDirection": np.degrees(np.arctan2(-u, -v)) % 360,
                "gust": np.maximum(gust, speed),
                "temperature": t_c,
                "feelsLike": feels_like(t_c, rh, speed),
                "humidity": rh,
                "pressure": _cut(grids["pmsl"], rows, cols) / 100,
                "visibility": np.minimum(_cut(grids["vis"], rows, cols) / 1000, 25.4),
                "rain": np.minimum(rain_rate(total := _cut(grids["tot_prec"], rows, cols),
                                             totals.get(tile.id), step - last_step), 25.4),
            }
            totals[tile.id] = total
            for name, data in values.items():
                if name == "windDirection":
                    half = ARROW_STEP // 2
                    data = data[half::ARROW_STEP, half::ARROW_STEP]
                cut[tile.id][name].append(_encode(data, VALUES[name]))
        last_step = step

    for tile in tiles:
        folder = out / "maps" / tile.id
        folder.mkdir(parents=True, exist_ok=True)
        for name, layers in cut[tile.id].items():
            packer = zlib.compressobj(9, zlib.DEFLATED, -15)  # raw deflate, as Apple's .zlib reads it
            body = packer.compress(np.stack(layers).tobytes()) + packer.flush()
            (folder / name).write_bytes(body)
    meta = {
        "run": run.isoformat().replace("+00:00", "Z"),
        "hours": [(run + timedelta(hours=s)).isoformat().replace("+00:00", "Z") for s in steps],
        "columns": COLS,
        "rows": ROWS,
        "arrowStep": ARROW_STEP,
        "tiles": [t.as_json() for t in tiles],
        "values": {name: {"offset": e.offset, "scale": e.scale, "unit": e.unit} for name, e in VALUES.items()},
        "credit": "Deutscher Wetterdienst (DWD), ICON-D2, CC BY 4.0",
    }
    (out / "maps").mkdir(parents=True, exist_ok=True)
    (out / "maps" / "index").write_text(json.dumps(meta, separators=(",", ":")))
    return run


