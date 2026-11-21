"""What the app showed, and measurements on the lakes, for the Model check.

The Model check (model_check.py) scores the raw weather models against DWD's
land stations. This module adds two things (owner, 11 Nov 2026):

- "app" rows: the forecasts the publisher actually wrote (clubs/<id>/forecast
  and lakes/<id>/view in its output folder), read at each Model check run and
  stored next to the models' rows, so the report can say how far the app's
  own numbers were off, including the lake squares and the water forecast.
  Read from the publisher's folder, not through api.rowfrog.com, so the check
  does not count as a visit and make a lake "used" (cloudflare/usage).
- Measurements of the Gewässerkundlicher Dienst Bayern (GKD): the Ammersee
  buoy's wind and air temperature (the only open wind measurement on a lake
  south of Munich) and lake water temperatures. GKD's tables show only the
  last days, so every run adds what it reads to a log in the Model check's
  data folder (measured/gkd/), and the history grows from the first run on.

Data: Gewässerkundlicher Dienst Bayern (Bayerisches Landesamt für Umwelt), CC BY 4.0.
"""

from __future__ import annotations

import csv
import json
import math
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import httpx

from . import source_status
from .sources import gkd

UTC = timezone.utc
LOCAL = ZoneInfo("Europe/Berlin")

# GKD table pages per measured value. The river name in the meteo paths does not
# matter to GKD (it answers the same page for any), "isar" is what its own links use.
GKD_PAGES = {
    "wind": "https://www.gkd.bayern.de/en/meteo/wind/isar/{station}/current-values/table",
    "temp": "https://www.gkd.bayern.de/en/meteo/air-temperature/isar/{station}/current-values/table",
    "water": "https://www.gkd.bayern.de/en/lakes/watertemperature/isar/{station}/current-values/table",
}
# The buoy measures wind about 1.8 m above the water (GKD's note); models and
# the app give it at 10 m. Over open water the log wind profile with a
# roughness length of 0.2 mm lifts it by ln(10/z0)/ln(1.8/z0) = 1.19.
BUOY_HEIGHT_M = 1.8
WATER_Z0_M = 0.0002
BUOY_TO_10M = math.log(10 / WATER_Z0_M) / math.log(BUOY_HEIGHT_M / WATER_Z0_M)
# A "wind" above this is not a speed in m/s (a table laid out differently than expected).
MAX_WIND_MS = 60.0
# The app's forecast is checked for the same 48 hours as the models.
HOURS = 48


# --- What the app showed -------------------------------------------------------


def _utc(text: str) -> datetime:
    t = datetime.fromisoformat(text.replace("Z", "+00:00"))
    return (t if t.tzinfo else t.replace(tzinfo=UTC)).astimezone(UTC)


def _row(point: str, issued: datetime, valid: datetime, **values) -> dict:
    return {
        "issued": issued.strftime("%Y-%m-%dT%H:%MZ"),
        "model": "app",
        "point": point,
        "valid": valid.strftime("%Y-%m-%dT%H:%MZ"),
        "lead_h": round((valid - issued).total_seconds() / 3600),
        **{k: "" if v is None else v for k, v in values.items()},
    }


def _issued(body: dict) -> datetime:
    return _utc(body["generatedAt"]).replace(second=0, microsecond=0)


def _in_reach(issued: datetime, valid: datetime) -> bool:
    return valid.minute == 0 and 0 <= (valid - issued).total_seconds() / 3600 <= HOURS


def club_rows(body: dict, point: str) -> list[dict]:
    """Rows from a club's forecast file (GET /clubs/<id>/forecast)."""
    issued = _issued(body)
    water = {d["date"]: d["celsius"] for d in body.get("waterForecast") or []}
    rows = []
    for h in body.get("hours") or []:
        valid = _utc(h["time"])
        if not _in_reach(issued, valid) or h.get("windSpeedMs") is None:
            continue
        rows.append(_row(
            point, issued, valid,
            wind=h.get("windSpeedMs"), gust=h.get("windGustMs"), dir=h.get("windFromDeg"),
            temp=h.get("temperatureC"), precip=h.get("precipitationMm"),
            water=water.get(valid.astimezone(LOCAL).date().isoformat()),
        ))
    return rows


def nearest_sample(body: dict, lat: float, lon: float) -> int | None:
    """Index of the lake view's weather point nearest to lat/lon."""
    points = body.get("points") or []
    if not points:
        return None
    k = math.cos(math.radians(lat))
    return min(range(len(points)), key=lambda i: (points[i]["lat"] - lat) ** 2 + ((points[i]["lon"] - lon) * k) ** 2)


def lake_rows(body: dict, point: str, lat: float, lon: float) -> list[dict]:
    """Rows from a lake view (GET /lakes/<id>/view) at its weather point nearest to the test point."""
    i = nearest_sample(body, lat, lon)
    if i is None:
        return []
    issued = _issued(body)
    rows = []
    for h in body.get("hours") or []:
        valid = _utc(h["time"])
        wind = (h.get("wind") or [])
        if not _in_reach(issued, valid) or i >= len(wind) or wind[i].get("speedMs") is None:
            continue
        w = wind[i]
        rows.append(_row(
            point, issued, valid,
            wind=w.get("speedMs"), gust=w.get("gustMs"), dir=w.get("fromDeg"),
            temp=None, precip=w.get("rainMm"), water=body.get("waterC"),
        ))
    return rows


def app_rows(app_dir: Path, points) -> tuple[list[dict], list[str]]:
    """'app' rows for every test point that names a club or a lake, from the publisher's folder."""
    rows, log = [], []
    for p in points:
        if p.club:
            path, read = app_dir / "clubs" / p.club / "forecast", lambda b, p=p: club_rows(b, p.id)
        elif p.lake:
            path, read = app_dir / "lakes" / p.lake / "view", lambda b, p=p: lake_rows(b, p.id, p.lat, p.lon)
        else:
            continue
        try:  # a file being rewritten by the publisher at this moment must not stop the others
            got = read(json.loads(path.read_text(encoding="utf-8")))
        except Exception as e:
            log.append(f"app {p.id}: {type(e).__name__}: {str(e)[:200]}")
            continue
        log.append(f"app {p.id}: {len(got)} hours" + (f", made {got[0]['issued']}" if got else ""))
        rows += got
    return rows, log


# --- GKD measurements ----------------------------------------------------------


def parse_table(page: str) -> dict[datetime, float]:
    """A GKD table page as {UTC time: value} (the page gives German local time)."""
    return {r.time.astimezone(UTC): r.celsius for r in gkd.parse(page)}


def fetch_table(client: httpx.Client, kind: str, station: str) -> dict[datetime, float]:
    resp = client.get(GKD_PAGES[kind].format(station=station), headers=gkd.HEADERS, timeout=30)
    resp.raise_for_status()
    if "Request Rejected" in resp.text:
        source_status.reject("gkd", "firewall")
        raise gkd.Rejected("GKD firewall rejected the request")
    values = parse_table(resp.text)
    if kind == "wind" and any(v > MAX_WIND_MS or v < 0 for v in values.values()):
        raise ValueError(f"wind table has values outside 0-{MAX_WIND_MS:.0f} m/s, layout changed?")
    return values


def log_path(data_dir: Path, kind: str, station: str) -> Path:
    return data_dir / "measured" / "gkd" / f"{kind}-{station}.csv"


def read_log(path: Path) -> dict[datetime, float]:
    if not path.exists():
        return {}
    with path.open(newline="", encoding="utf-8") as f:
        return {_utc(r["time"]): float(r["value"]) for r in csv.DictReader(f)}


def merge_log(path: Path, values: dict[datetime, float]) -> int:
    """Adds new readings to the log; returns how many were new."""
    old = read_log(path)
    new = {t: v for t, v in values.items() if t not in old}
    if new:
        path.parent.mkdir(parents=True, exist_ok=True)
        merged = {**old, **new}
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["time", "value"])
            for t in sorted(merged):
                w.writerow([t.strftime("%Y-%m-%dT%H:%MZ"), merged[t]])
    return len(new)


def gkd_wanted(points) -> set[tuple[str, str]]:
    return {(kind, station) for p in points for kind, station in (p.gkd or {}).items()}


def log_gkd(client: httpx.Client, data_dir: Path, points) -> list[str]:
    """Reads each GKD table the test points need once and adds it to the log."""
    log = []
    for kind, station in sorted(gkd_wanted(points)):
        try:
            values = fetch_table(client, kind, station)
        except Exception as e:  # GKD's firewall or a defect at the buoy: the log keeps what it has
            log.append(f"gkd {kind} {station}: {type(e).__name__}: {str(e)[:200]}")
            continue
        added = merge_log(log_path(data_dir, kind, station), values)
        log.append(f"gkd {kind} {station}: {len(values)} readings, {added} new")
    return log


def hourly(values: dict[datetime, float], kind: str) -> dict[datetime, float]:
    """Values at the full hours; the buoy's wind lifted to 10 m."""
    factor = BUOY_TO_10M if kind == "wind" else 1.0
    return {t: round(v * factor, 2) for t, v in values.items() if t.minute == 0}


def gkd_observations(data_dir: Path, points) -> dict[str, dict[str, dict[datetime, float]]]:
    """Per point and kind ("wind", "temp", "water"): {UTC hour: value}, from the whole GKD log."""
    obs: dict[str, dict[str, dict[datetime, float]]] = {}
    for p in points:
        for kind, station in (p.gkd or {}).items():
            values = hourly(read_log(log_path(data_dir, kind, station)), kind)
            if values:
                obs.setdefault(p.id, {})[kind] = values
    return obs
