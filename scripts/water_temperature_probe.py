#!/usr/bin/env python3
"""Look at satellite lake surface temperature for our lakes, before the app uses it.

Usage (from the repository root, after `pip install -e "backend[satellite]" netCDF4`):
    CDSE_CLIENT_ID=... CDSE_CLIENT_SECRET=... python3 scripts/water_temperature_probe.py

For lakes without a GKD station the app only has the ice model's estimate of
the water temperature. This script checks three satellite sources against the
GKD station on Starnberger See and prints, per lake, how many clear passes each
source had and what temperature it saw:
  1. Copernicus Lake Surface Water Temperature (CLMS LSWT, Sentinel-3, 1 km,
     10-daily) from the CDSE OData catalogue,
  2. Sentinel-3 SLSTR Level-2 swaths (sea surface temperature WST and land
     surface temperature LST, 1 km, about daily) from the CDSE catalogue;
     not run any more: on 24 Oct 2026 WST marked every lake pixel low quality
     and LST gave -38 °C on the Bodensee under cloud, so swaths() is kept
     only for a later look,
  3. Landsat 8/9 Collection 2 surface temperature (100 m thermal, 30 m grid,
     every 8 days with both satellites) from Microsoft's Planetary Computer.
Only pixels at least one pixel away from the shore count, so the land around
the lake does not warm or cool the value. Nothing is stored; the report goes
to the log and the job summary.

Data: Copernicus (free and open, credit "Copernicus"); Landsat courtesy of the
U.S. Geological Survey (public domain); GKD Bayern (CC BY 4.0).
"""

from __future__ import annotations

import io
import math
import os
import re
import statistics
import sys
import tempfile
import zipfile
from datetime import date, datetime, timedelta, timezone

import httpx
import numpy as np

from rowfrog import outlines
from rowfrog.sources import gkd

TOKEN_URL = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"
ODATA = "https://catalogue.dataspace.copernicus.eu/odata/v1/Products"
DOWNLOAD = "https://download.dataspace.copernicus.eu/odata/v1/Products({id})/$value"
STAC = "https://planetarycomputer.microsoft.com/api/stac/v1/search"
GKD_HISTORY = [
    "https://www.gkd.bayern.de/en/lakes/watertemperature/bayern/{station}/measured-values/table?beginn={start}&ende={end}",
    "https://www.gkd.bayern.de/de/seen/wassertemperatur/bayern/{station}/messwerte/tabelle?beginn={start}&ende={end}",
    "https://www.gkd.bayern.de/de/seen/wassertemperatur/isar/{station}/messwerte/tabelle?beginn={start}&ende={end}",
    "https://www.gkd.bayern.de/en/lakes/watertemperature/bayern/{station}/current-values/table?beginn={start}&ende={end}",
]
SIGN_TOKEN = "https://planetarycomputer.microsoft.com/api/sas/v1/token/landsat-c2-l2"
# Lakes without an outline in the repository, by a point near their middle: is the lake in the LSWT lake list?
POINTS = {
    "chiemsee": (12.43, 47.87), "tegernsee": (11.755, 47.715), "kochelsee": (11.35, 47.65),
    "walchensee": (11.33, 47.59), "staffelsee": (11.17, 47.69), "woerthsee": (11.165, 48.065),
    "pilsensee": (11.19, 48.03), "schliersee": (11.86, 47.73), "waginger-see": (12.78, 47.93),
    "koenigssee": (12.98, 47.55), "grosser-brombachsee": (10.93, 49.12), "altmuehlsee": (10.72, 49.14),
}

# Large to small, so the report shows where each resolution stops working.
LAKES = ["bodensee", "starnberger-see", "ammersee", "forggensee", "simssee", "regattastrecke-oberschleissheim"]
STATION = {"starnberger-see": "starnberg-16663002"}
TODAY = datetime.now(timezone.utc).date()
LANDSAT_DAYS = 120
SWATH_DAYS = 3

out: list[str] = []


def say(line: str = "") -> None:
    print(line, flush=True)
    out.append(line)


# --- geometry -----------------------------------------------------------------


def inside(x: float, y: float, ring: list[tuple[float, float]]) -> bool:
    hit = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


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


def water_pixel(lon: float, lat: float, ring, margin_m: float) -> bool:
    return inside(lon, lat, ring) and shore_distance_m(lon, lat, ring) >= margin_m


def summary(values: list[float]) -> str:
    if not values:
        return "no clear pixel"
    return f"{len(values)} px, median {statistics.median(values):.1f} °C (min {min(values):.1f}, max {max(values):.1f})"


# --- ground truth ---------------------------------------------------------------


def gkd_daily(client: httpx.Client, station: str, start: date) -> dict[date, list[gkd.WaterTemperature]]:
    days: dict[date, list[gkd.WaterTemperature]] = {}
    template = None
    for url in GKD_HISTORY:
        test = url.format(station=station, start=(TODAY - timedelta(days=30)).strftime("%d.%m.%Y"), end=TODAY.strftime("%d.%m.%Y"))
        try:
            resp = client.get(test, headers=gkd.HEADERS, timeout=60, follow_redirects=True)
        except httpx.HTTPError as e:
            say(f"GKD {test}: {e}")
            continue
        readings = gkd.parse(resp.text)
        span = f"{readings[-1].time:%Y-%m-%d} to {readings[0].time:%Y-%m-%d}" if readings else "-"
        say(f"GKD {resp.status_code} {len(resp.text)} chars, {len(readings)} readings ({span}): {test}")
        if len(readings) > 500 and template is None:
            template = url
    if template is None:
        return days
    month = start
    while month <= TODAY:
        end = min(TODAY, month + timedelta(days=30))
        try:
            resp = client.get(template.format(station=station, start=month.strftime("%d.%m.%Y"), end=end.strftime("%d.%m.%Y")),
                              headers=gkd.HEADERS, timeout=60, follow_redirects=True)
            for r in gkd.parse(resp.text):
                days.setdefault(r.time.date(), []).append(r)
        except httpx.HTTPError as e:
            say(f"GKD {month}: {e}")
        month = end + timedelta(days=1)
    say(f"GKD {station}: {sum(map(len, days.values()))} readings over {len(days)} days ({min(days, default='-')} to {max(days, default='-')})")
    return days


def gkd_mean(days: dict, first: date, last: date) -> float | None:
    values = [r.celsius for d, rs in days.items() if first <= d <= last for r in rs]
    return statistics.mean(values) if values else None


def gkd_at(days: dict, when: datetime) -> str:
    near = [r for r in days.get(when.date(), [])]
    if not near:
        return "GKD -"
    best = min(near, key=lambda r: abs(r.time - when))
    return f"GKD {best.celsius:.1f} °C at {best.time.astimezone(timezone.utc):%H:%M} UTC"


# --- Copernicus ---------------------------------------------------------------------


def cdse_token(client: httpx.Client) -> str | None:
    if not (os.environ.get("CDSE_CLIENT_ID") and os.environ.get("CDSE_CLIENT_SECRET")):
        say("CDSE_CLIENT_ID / CDSE_CLIENT_SECRET missing: Copernicus downloads skipped.")
        return None
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


def odata(client: httpx.Client, flt: str, top: int = 20, order: str = "ContentDate/Start desc") -> list[dict]:
    resp = client.get(ODATA, params={"$filter": flt, "$top": str(top), "$orderby": order}, timeout=90)
    if resp.status_code != 200:
        say(f"  OData {resp.status_code}: {resp.text[:300]}")
        return []
    return resp.json().get("value", [])


def download(client: httpx.Client, token: str, product: dict) -> bytes:
    resp = client.get(
        DOWNLOAD.format(id=product["Id"]),
        headers={"Authorization": f"Bearer {token}"},
        timeout=600,
        follow_redirects=True,
    )
    resp.raise_for_status()
    return resp.content


def clms_lswt(client: httpx.Client, token: str | None, rings: dict, gkd_days: dict) -> None:
    say("## 1. Copernicus Lake Surface Water Temperature (CLMS, 1 km, 10-daily)")
    products = odata(client, "contains(Name,'c_gls_LSWT_') and endswith(Name,'_cog') and ContentDate/Start gt 2026-04-30T00:00:00.000Z",
                     top=40, order="ContentDate/Start asc")
    say(f"{len(products)} ten-day files since May; newest {products[-1]['Name'] if products else '-'}, "
        f"published {products[-1].get('PublicationDate', '?')[:16] if products else '-'}")
    if not token:
        return
    import rasterio

    for p in products:
        first = date.fromisoformat(p["ContentDate"]["Start"][:10])
        last = date(first.year, first.month, 20) if first.day == 11 else first + timedelta(days=9)
        if first.day == 21:
            last = (first.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)
        content = download(client, token, p)
        with tempfile.TemporaryDirectory() as folder, zipfile.ZipFile(io.BytesIO(content)) as z:
            name = next(n for n in z.namelist() if "LSWT-LSWT_" in n)
            path = z.extract(name, folder)
            qname = next(n for n in z.namelist() if "LSWT-QLEVEL_" in n)
            qpath = z.extract(qname, folder)
            with rasterio.open(path) as ds, rasterio.open(qpath) as qs:
                parts = []
                for lake_id, ring in rings.items():
                    vals = sample_raster(ds, qs, ring, 700)
                    if vals:
                        parts.append(f"{lake_id} {statistics.median(vals):.1f} ({len(vals)} px)")
                for lake_id, (lon, lat) in POINTS.items():
                    r, c = ds.index(lon, lat)
                    win = ds.read(1, window=((r - 1, r + 2), (c - 1, c + 2)), masked=True)
                    q = qs.read(1, window=((r - 1, r + 2), (c - 1, c + 2)))
                    good = [float(v) * ds.scales[0] + ds.offsets[0] - 273.15 for v, ok in zip(win.compressed(), q[~np.ma.getmaskarray(win)]) if ok >= 4]
                    if good:
                        parts.append(f"{lake_id} {statistics.median(good):.1f} ({len(good)} px)")
        ref = gkd_mean(gkd_days, first, last)
        gkd_text = f"{ref:.1f}" if ref is not None else "-"
        say(f"- {first}–{last}: GKD Starnberg mean {gkd_text} °C | " + (", ".join(parts) or "no lake seen"))


def sample_raster(ds, qs, ring, margin_m: float) -> list[float]:
    """Best and acceptable quality (4, 5) LSWT pixels inside `ring`, in °C."""
    import numpy as np
    from rasterio.windows import from_bounds

    xs, ys = zip(*ring)
    window = from_bounds(min(xs), min(ys), max(xs), max(ys), ds.transform).round_offsets().round_lengths()
    data = ds.read(1, window=window, boundless=True, masked=True)
    quality = qs.read(1, window=window, boundless=True, fill_value=0)
    mask = np.ma.getmaskarray(data)
    t = ds.window_transform(window)
    values = []
    for r in range(data.shape[0]):
        for c in range(data.shape[1]):
            lon, lat = t * (c + 0.5, r + 0.5)
            if not mask[r, c] and quality[r, c] >= 4 and water_pixel(lon, lat, ring, margin_m):
                values.append(float(data.data[r, c]) * ds.scales[0] + ds.offsets[0] - 273.15)
    return values


def swaths(client: httpx.Client, token: str | None, rings: dict, gkd_days: dict) -> None:
    say("## 2. Sentinel-3 SLSTR Level-2 swaths (1 km, about daily)")
    lon, lat = statistics.mean(x for x, _ in rings["starnberger-see"]), statistics.mean(y for _, y in rings["starnberger-see"])
    start = (TODAY - timedelta(days=SWATH_DAYS)).isoformat()
    for kind in ("SL_2_WST", "SL_2_LST"):
        flt = (
            f"Collection/Name eq 'SENTINEL-3' and contains(Name,'{kind}') "
            f"and OData.CSC.Intersects(area=geography'SRID=4326;POINT({lon:.4f} {lat:.4f})') "
            f"and ContentDate/Start gt {start}T00:00:00.000Z"
        )
        products = odata(client, flt, top=40)
        say(f"### {kind}: {len(products)} products over Starnberger See in the last {SWATH_DAYS} days")
        for p in products[:12]:
            say(f"- {p['Name']} ({p.get('ContentLength', 0) // (1024 * 1024)} MB)")
        if not token:
            continue
        # Prefer the processed (NT) over the near-real-time (NR) files, newest first, and daytime and night.
        for p in products[:4]:
            try:
                read_swath(client, token, p, kind, rings, gkd_days)
            except Exception as e:  # noqa: BLE001
                say(f"  {p['Name']}: {e}")


def read_swath(client, token, product, kind, rings, gkd_days) -> None:
    import netCDF4
    import numpy as np

    when = datetime.strptime(re.search(r"_(\d{8}T\d{6})_", product["Name"]).group(1), "%Y%m%dT%H%M%S").replace(tzinfo=timezone.utc)
    content = download(client, token, product)
    with tempfile.TemporaryDirectory() as folder:
        with zipfile.ZipFile(io.BytesIO(content)) as z:
            z.extractall(folder)
            names = z.namelist()
        say(f"### {product['Name'][:80]}… ({when:%Y-%m-%d %H:%M} UTC, {gkd_at(gkd_days, when)})")

        def path(suffix):
            return os.path.join(folder, next(n for n in names if n.endswith(suffix)))

        if kind == "SL_2_WST":
            nc = netCDF4.Dataset(path(".nc"))
            lat = nc["lat"][:]
            lon = nc["lon"][:]
            sst = nc["sea_surface_temperature"][0] if nc["sea_surface_temperature"].ndim == 3 else nc["sea_surface_temperature"][:]
            ql = nc["quality_level"][0] if nc["quality_level"].ndim == 3 else nc["quality_level"][:]
            values = {"all": sst, "quality ≥3": np.ma.masked_where(ql < 3, sst)}
        else:
            lst = netCDF4.Dataset(path("LST_in.nc"))["LST"][:]
            geo = netCDF4.Dataset(path("geodetic_in.nc"))
            lat, lon = geo["latitude_in"][:], geo["longitude_in"][:]
            flags = netCDF4.Dataset(path("flags_in.nc"))
            cloud = flags["bayes_in"][:] if "bayes_in" in flags.variables else None
            values = {"all": lst}
            if cloud is not None:
                values["bayes clear"] = np.ma.masked_where((np.asarray(cloud) & 2) != 0, lst)
        for lake_id, ring in rings.items():
            xs, ys = zip(*ring)
            box = (lon >= min(xs)) & (lon <= max(xs)) & (lat >= min(ys)) & (lat <= max(ys))
            idx = np.argwhere(np.asarray(box))
            if not len(idx):
                continue
            keep = [(r, c) for r, c in idx if water_pixel(float(lon[r, c]), float(lat[r, c]), ring, 700)]
            parts = []
            for label, field in values.items():
                vals = [float(field[r, c]) - 273.15 for r, c in keep if not np.ma.is_masked(field[r, c])]
                parts.append(f"{label}: {summary(vals)}")
            say(f"    {lake_id} ({len(keep)} water px): " + "; ".join(parts))


# --- Landsat -------------------------------------------------------------------------


_sas: dict[str, object] = {}


def sas(client: httpx.Client) -> str:
    """A read token for the Landsat files, renewed before it runs out."""
    if not _sas or datetime.now(timezone.utc) > _sas["until"]:
        body = client.get(SIGN_TOKEN, timeout=30).json()
        _sas["token"] = body["token"]
        _sas["until"] = datetime.now(timezone.utc) + timedelta(minutes=30)
    return _sas["token"]


def landsat(client: httpx.Client, rings: dict, gkd_days: dict) -> None:
    import rasterio
    from rasterio.features import rasterize
    from rasterio.warp import transform as warp
    from rasterio.windows import from_bounds

    say(f"## 3. Landsat 8/9 Collection 2 surface temperature (Planetary Computer, last {LANDSAT_DAYS} days)")
    bbox = [
        min(min(x for x, _ in r) for r in rings.values()),
        min(min(y for _, y in r) for r in rings.values()),
        max(max(x for x, _ in r) for r in rings.values()),
        max(max(y for _, y in r) for r in rings.values()),
    ]
    body = {
        "collections": ["landsat-c2-l2"],
        "bbox": bbox,
        "datetime": f"{TODAY - timedelta(days=LANDSAT_DAYS)}T00:00:00Z/{TODAY}T23:59:59Z",
        "limit": 200,
    }
    resp = client.post(STAC, json=body, timeout=90)
    resp.raise_for_status()
    items = sorted(resp.json()["features"], key=lambda f: f["properties"]["datetime"])
    say(f"{len(items)} scenes touch the lakes (both satellites, all clouds)")
    os.environ.setdefault("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
    clear = {lake: 0 for lake in rings}
    for item in items:
        props = item["properties"]
        when = datetime.fromisoformat(props["datetime"].replace("Z", "+00:00"))
        hrefs = {key: item["assets"][key]["href"] + "?" + sas(client) for key in ("lwir11", "qa_pixel")}
        line = []
        with rasterio.open(hrefs["lwir11"]) as st, rasterio.open(hrefs["qa_pixel"]) as qa:
            for lake_id, ring in rings.items():
                xs, ys = warp("EPSG:4326", st.crs, [p[0] for p in ring], [p[1] for p in ring])
                left, right, bottom, top = min(xs), max(xs), min(ys), max(ys)
                b = st.bounds
                if right < b.left or left > b.right or top < b.bottom or bottom > b.top:
                    continue
                window = from_bounds(left, bottom, right, top, st.transform).round_offsets().round_lengths()
                temp = st.read(1, window=window, boundless=True, fill_value=0)
                bits = qa.read(1, window=window, boundless=True, fill_value=1)
                t = st.window_transform(window)
                lake = rasterize([{"type": "Polygon", "coordinates": [list(zip(xs, ys))]}], out_shape=temp.shape, transform=t).astype(bool)
                # One pixel of the native 100 m thermal band (4 of 30 m) away from the shore.
                for _ in range(4):
                    lake[1:, :] &= lake[:-1, :].copy()
                    lake[:-1, :] &= lake[1:, :].copy()
                    lake[:, 1:] &= lake[:, :-1].copy()
                    lake[:, :-1] &= lake[:, 1:].copy()
                total = int(lake.sum())
                bad = (bits & 0b11011) != 0
                ok = lake & ~bad & (temp != 0)
                water = list(temp[ok] * 0.00341802 + 149.0 - 273.15)
                share = len(water) / total if total else 0
                if share >= 0.3:
                    clear[lake_id] += 1
                line.append(f"{lake_id} {share:.0%} clear" + (f" {statistics.median(water):.1f} °C" if water else ""))
        if any("clear " in part and not part.endswith("0% clear") for part in line):
            ref = gkd_at(gkd_days, when) if any(s.startswith("starnberger-see") for s in line) else ""
            say(f"- {when:%Y-%m-%d %H:%M} {props.get('platform')} cloud {props.get('eo:cloud_cover', 0):.0f} %: " + ", ".join(line) + (f" | {ref}" if ref else ""))
    say("Passes with at least 30 % of the lake clear: " + ", ".join(f"{k} {v}" for k, v in clear.items()))


def simplify(ring: list[tuple[float, float]], step: int) -> list[tuple[float, float]]:
    return ring[::step] if len(ring) > step * 50 else ring


def main() -> int:
    rings = {}
    for lake_id in LAKES:
        r = outlines.load(lake_id)
        if r:
            # The shore only (islands are left in); long OSM shores are thinned for speed.
            rings[lake_id] = simplify(r[0], max(1, len(r[0]) // 1500))
    say(f"# Satellite water temperature probe, {TODAY}")
    say("Lakes: " + ", ".join(f"{k} ({len(v)} shore points)" for k, v in rings.items()))
    with httpx.Client() as client:
        gkd_days = gkd_daily(client, STATION["starnberger-see"], TODAY - timedelta(days=LANDSAT_DAYS))
        token = None
        try:
            token = cdse_token(client)
        except httpx.HTTPError as e:
            say(f"CDSE token: {e}")
        for step in (lambda: clms_lswt(client, token, rings, gkd_days), lambda: landsat(client, rings, gkd_days)):
            try:
                step()
            except Exception as e:  # noqa: BLE001
                say(f"  failed: {type(e).__name__}: {e}")
            say()
    summary_file = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_file:
        with open(summary_file, "a", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
