#!/usr/bin/env python3
"""Check the satellite water temperature against the GKD lake stations.

Usage (from the repository root, after `pip install -e "backend[satellite]"`):
    CDSE_CLIENT_ID=... CDSE_CLIENT_SECRET=... python3 scripts/water_temperature_backtest.py [first day, default 1 May]

For Bavarian lakes that have a GKD station, the script reads every Copernicus
LSWT file and every Landsat 8/9 pass since the first day, and the station's
readings and the daily mean air temperature (Open-Meteo archive) for the same
days. It prints:
  1. satellite against station at the same time (bias and mean error),
  2. the estimate the app would have shown on each day (the newest reading
     available that day, carried forward with water_estimate.carry for
     several layer depths, or kept as it was), against the station's daily
     mean, next to the plain monthly typical value as a baseline.
Lakes without an outline in the repository are a circle around a point in
open water. The report goes to the log and, on GitHub Actions, the job summary.

Data: Copernicus (credit "Copernicus"), Landsat courtesy of the U.S. Geological
Survey, GKD Bayern (CC BY 4.0), Open-Meteo (CC BY 4.0).
"""

from __future__ import annotations

import asyncio
import html
import math
import os
import re
import statistics
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import httpx

from rowfrog import ice, outlines, water_estimate
from rowfrog.sources import gkd, lake_ice_satellite, lake_temperature_satellite as sat, open_meteo

GKD_TABLE = "https://www.gkd.bayern.de/de/seen/wassertemperatur/bayern/{station}/messwerte/tabelle?beginn={start}&ende={end}"
ROW = re.compile(r"(\d{2})\.(\d{2})\.(\d{4})\s+(\d{2}):(\d{2})(?:\s*Uhr)?\s+(-?\d+(?:,\d+)?)")
LOCAL = ZoneInfo("Europe/Berlin")
# Layer depths tried for carrying a reading forward; None keeps the reading as it was.
LAYERS = [None, 2.0, 5.0, 10.0, 20.0]
# LSWT files arrive this many days after their ten days end.
LSWT_DELAY_DAYS = 3


@dataclass(frozen=True)
class Lake:
    id: str
    station: str
    # A point in open water and a radius (m) for lakes without an outline in the repository.
    point: tuple[float, float] | None = None
    radius_m: float = 0


LAKES = [
    Lake("starnberger-see", "starnberg-16663002"),
    Lake("ammersee", "stegen-16602008"),
    Lake("bodensee", "lindau-20001001"),
    Lake("chiemsee", "stock-18400503", (12.47, 47.88), 3000),
    Lake("tegernsee", "tegernsee-18201303", (11.755, 47.72), 700),
    Lake("woerthsee", "woerthsee-16651003", (11.165, 48.063), 600),
    Lake("pilsensee", "pilsensee-16628055", (11.19, 48.03), 350),
    Lake("schliersee", "schliersee-18222008", (11.86, 47.725), 400),
    Lake("koenigssee", "koenigssee-18624806", (12.982, 47.565), 250),
]

out: list[str] = []


def say(line: str = "") -> None:
    print(line, flush=True)
    out.append(line)


def circle(lon: float, lat: float, radius_m: float, points: int = 48) -> list[tuple[float, float]]:
    kx = 111_320 * math.cos(math.radians(lat))
    return [
        (lon + radius_m * math.cos(2 * math.pi * i / points) / kx, lat + radius_m * math.sin(2 * math.pi * i / points) / 110_540)
        for i in range(points)
    ]


def shore(lake: Lake) -> list[tuple[float, float]] | None:
    if lake.point:
        return circle(*lake.point, lake.radius_m)
    rings = outlines.load(lake.id)
    return sat.thin(rings[0]) if rings else None


# --- ground truth and air -----------------------------------------------------------------------


def station_readings(client: httpx.Client, station: str, first: date, last: date) -> list[gkd.WaterTemperature]:
    """All readings between the days; the table page only lists about ten days at a time."""
    readings = {}
    start = first
    while start <= last:
        end = min(last, start + timedelta(days=9))
        url = GKD_TABLE.format(station=station, start=start.strftime("%d.%m.%Y"), end=end.strftime("%d.%m.%Y"))
        for attempt in range(2):
            try:
                resp = client.get(url, headers=gkd.HEADERS, timeout=60, follow_redirects=True)
                text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", resp.text)))
                for day, month, year, hour, minute, value in ROW.findall(text):
                    t = datetime(int(year), int(month), int(day), int(hour), int(minute), tzinfo=LOCAL)
                    readings[t] = float(value.replace(",", "."))
                break
            except httpx.HTTPError as e:
                if attempt:
                    say(f"  GKD {station} {start}: {e!r}")
        start = end + timedelta(days=1)
    return [gkd.WaterTemperature(t, readings[t]) for t in sorted(readings)]


def daily_means(readings: list[gkd.WaterTemperature]) -> dict[date, float]:
    by_day = defaultdict(list)
    for r in readings:
        by_day[r.time.date()].append(r.celsius)
    return {d: statistics.mean(v) for d, v in by_day.items() if len(v) >= 12}


async def air(lat: float, lon: float, first: date, last: date) -> list[ice.DayTemperature]:
    async with httpx.AsyncClient() as client:
        days = dict(await open_meteo.fetch_archive_daily_mean(client, lat, lon, first, last))
        # The archive is a few days behind; the forecast service's past days fill the end.
        for d, t in await open_meteo.fetch_daily_mean(client, lat, lon):
            if first <= d <= last:
                days.setdefault(d, t)
    return [ice.DayTemperature(d, days[d]) for d in sorted(days)]


# --- report ---------------------------------------------------------------------------------


def stats(errors: list[float]) -> str:
    if not errors:
        return "–"
    return f"{statistics.mean(errors):+.1f} / {statistics.mean(abs(e) for e in errors):.1f} (n {len(errors)})"


def main(first: date) -> int:
    today = datetime.now(timezone.utc).date()
    last = today - timedelta(days=1)
    lakes = [(lake, ring) for lake in LAKES if (ring := shore(lake))]
    shores = {lake.id: ring for lake, ring in lakes}
    say(f"# Satellite water temperature against GKD stations, {first} to {last}")
    say("Errors are satellite or estimate minus station, as mean (bias) / mean absolute, in °C.")

    readings: dict[str, list[sat.Reading]] = defaultdict(list)
    with httpx.Client() as client:
        truth = {}
        quarter_hours = {}
        for lake, _ in lakes:
            values = station_readings(client, lake.station, first, last)
            quarter_hours[lake.id] = values
            truth[lake.id] = daily_means(values)
            say(f"- GKD {lake.station}: {len(values)} readings, {len(truth[lake.id])} days")

        if sat.configured():
            token = lake_ice_satellite._token(client)
            for product in sat.lswt_products(client, first):
                try:
                    for lake_id, reading in sat.fetch_lswt(client, token, product, shores).items():
                        readings[lake_id].append(reading)
                except Exception as e:  # noqa: BLE001
                    say(f"  LSWT {product['Name']}: {e!r}")
        else:
            say("CDSE secrets or rasterio missing: no LSWT.")

        xs = [x for ring in shores.values() for x, _ in ring]
        ys = [y for ring in shores.values() for _, y in ring]
        scenes = sat.landsat_scenes(client, [min(xs), min(ys), max(xs), max(ys)], first, last)
        say(f"- Landsat: {len(scenes)} scenes")
        for scene in scenes:
            lon0, lat0, lon1, lat1 = scene["bbox"]
            here = {k: r for k, r in shores.items() if lon0 <= min(x for x, _ in r) and max(x for x, _ in r) <= lon1 and lat0 <= min(y for _, y in r) and max(y for _, y in r) <= lat1}
            if not here:
                continue
            try:
                for lake_id, (reading, _) in sat.read_landsat(client, scene, here).items():
                    if reading:
                        readings[lake_id].append(reading)
            except Exception as e:  # noqa: BLE001
                say(f"  Landsat {scene.get('id')}: {e!r}")

    temps = {}
    for lake, ring in lakes:
        lon = statistics.mean(x for x, _ in ring)
        lat = statistics.mean(y for _, y in ring)
        try:
            temps[lake.id] = asyncio.run(air(lat, lon, first - timedelta(days=1), last))
        except (httpx.HTTPError, KeyError, ValueError) as e:
            say(f"  air {lake.id}: {e!r}")
            temps[lake.id] = []

    say()
    say("## 1. Satellite against the station at the same time")
    say("| Lake | LSWT vs 10-day station mean | Landsat vs station at the pass |")
    say("| --- | --- | --- |")
    all_lswt, all_landsat = [], []
    for lake, _ in lakes:
        lswt_err, landsat_err = [], []
        for r in readings[lake.id]:
            if r.source == sat.LSWT:
                days = [truth[lake.id][d] for d in truth[lake.id] if r.first <= d <= r.last]
                if len(days) >= 7:
                    lswt_err.append(r.celsius - statistics.mean(days))
            else:
                near = [q for q in quarter_hours[lake.id] if abs(q.time - r.time) <= timedelta(minutes=45)]
                if near:
                    landsat_err.append(r.celsius - min(near, key=lambda q: abs(q.time - r.time)).celsius)
        all_lswt += lswt_err
        all_landsat += landsat_err
        say(f"| {lake.id} | {stats(lswt_err)} | {stats(landsat_err)} |")
    say(f"| all | {stats(all_lswt)} | {stats(all_landsat)} |")

    say()
    say("## 2. What the app would have shown each day, against the station's daily mean")
    say("Newest reading available that day (LSWT 3 days after its ten days), carried forward. "
        "Columns: layer depth for carrying forward (kept = no change); typical = monthly typical value.")
    header = ["kept" if h is None else f"{h:g} m" for h in LAYERS] + ["typical"]
    say("| Lake | days with a reading | " + " | ".join(header) + " | median age (days) |")
    say("| --- | --- | " + " | ".join("---" for _ in header) + " | --- |")
    totals: dict[str, list[float]] = defaultdict(list)
    by_age: dict[tuple[str, str], list[float]] = defaultdict(list)
    for lake, _ in lakes:
        errors: dict[str, list[float]] = defaultdict(list)
        ages = []
        for d, measured in sorted(truth[lake.id].items()):
            available = [
                r for r in readings[lake.id]
                if (r.last + timedelta(days=LSWT_DELAY_DAYS) <= d if r.source == sat.LSWT else r.day < d)
                and (d - r.day).days <= water_estimate.MAX_AGE_DAYS
            ]
            if not available:
                continue
            newest = max(available, key=lambda r: r.day)
            age = (d - newest.day).days
            ages.append(age)
            bucket = "1-5" if age <= 5 else "6-10" if age <= 10 else "11-20" if age <= 20 else "21-30"
            for h, name in zip(LAYERS, header):
                guess = newest.celsius if h is None else water_estimate.carry(newest.day, newest.celsius, temps[lake.id], d, h)
                errors[name].append(guess - measured)
                by_age[(name, bucket)].append(guess - measured)
            errors["typical"].append(ice.TYPICAL_WATER_C[d.month] - measured)
        for name, e in errors.items():
            totals[name] += e
        say(f"| {lake.id} | {len(ages)} | " + " | ".join(stats(errors[n]) for n in header) + f" | {statistics.median(ages) if ages else '–'} |")
    say("| all | | " + " | ".join(stats(totals[n]) for n in header) + " | |")

    say()
    say("Mean absolute error by age of the reading:")
    say("| Age (days) | " + " | ".join(header[:-1]) + " |")
    say("| --- | " + " | ".join("---" for _ in header[:-1]) + " |")
    for bucket in ("1-5", "6-10", "11-20", "21-30"):
        cells = []
        for name in header[:-1]:
            e = by_age.get((name, bucket), [])
            cells.append(f"{statistics.mean(abs(x) for x in e):.1f} (n {len(e)})" if e else "–")
        say(f"| {bucket} | " + " | ".join(cells) + " |")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    start = date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else date(datetime.now().year, 5, 1)
    sys.exit(main(start))
