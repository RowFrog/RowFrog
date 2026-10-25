"""Compare weather models against measured wind and temperature.

Used by scripts/model_check.py and the "Model check" workflow. Twice a day it
stores every candidate model's forecast for the test points in
data/model-check/points.json; the report then matches those forecasts with
DWD 10-minute station measurements near each point and scores the models.

Forecasts: Open-Meteo, one request per model with all points at once (a model
that does not cover a point answers with empty values, which are skipped).
Measurements: DWD Climate Data Center, 10-minute wind, gusts and air
temperature ("recent" files, updated daily, times in UTC). CC BY 4.0.
"""

from __future__ import annotations

import csv
import gzip
import io
import json
import math
import re
import zipfile
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from statistics import mean

import httpx

from .score import Thresholds

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
ARCHIVE_URL = "https://historical-forecast-api.open-meteo.com/v1/forecast"
DWD_10MIN = "https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/10_minutes"

# Candidate models per stage, by Open-Meteo id. A stage includes all earlier ones.
MODELS = {
    1: [
        "icon_d2",
        "icon_eu",
        "meteoswiss_icon_ch1",
        "meteoswiss_icon_ch2",
        "geosphere_arome_austria",
        "ecmwf_ifs025",
        "ecmwf_aifs025_single",
        "knmi_harmonie_arome_europe",
        "dmi_harmonie_arome_europe",
        "best_match",
    ],
}
# What the app uses for the first 48 hours today (icon_seamless starts with ICON-D2).
CURRENT = "icon_d2"
REFERENCE = "best_match"

VARIABLES = ["wind_speed_10m", "wind_gusts_10m", "wind_direction_10m", "temperature_2m", "precipitation"]
FIELDS = ["issued", "model", "point", "valid", "lead_h", "wind", "gust", "dir", "temp", "precip"]

# A model and best_match "disagree" for an hour when one of these differences is exceeded.
DISAGREE = {"wind": 2.0, "gust": 3.0, "temp": 2.0}
# Stations further away than this are not used for a point.
MAX_STATION_KM = 35.0


@dataclass(frozen=True)
class Point:
    id: str
    name: str
    lat: float
    lon: float
    stage: int


def load_points(path: Path, stage: int) -> list[Point]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return [Point(**p) for p in data["points"] if p["stage"] <= stage]


def models_for(stage: int) -> list[str]:
    return [m for s in sorted(MODELS) if s <= stage for m in MODELS[s]]


def distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(a))


# --- Forecasts -------------------------------------------------------------


def forecast_params(points: list[Point], model: str, hours: int = 48) -> dict[str, str]:
    return {
        "latitude": ",".join(f"{p.lat:.4f}" for p in points),
        "longitude": ",".join(f"{p.lon:.4f}" for p in points),
        "hourly": ",".join(VARIABLES),
        "models": model,
        "wind_speed_unit": "ms",
        "timezone": "GMT",
        "forecast_hours": str(hours),
    }


def rows_from_payload(payload, points: list[Point], model: str, issued: datetime | None) -> list[dict]:
    """CSV rows for one model's answer; hours without wind (outside the model's area) are left out.

    `issued` None means archived forecasts, whose lead time is unknown."""
    answers = payload if isinstance(payload, list) else [payload]
    rows = []
    for point, answer in zip(points, answers):
        h = answer.get("hourly") or {}
        times = h.get("time") or []

        def col(name: str) -> list:
            return h.get(name) or [None] * len(times)

        for t, ws, wg, wd, tt, pr in zip(
            times, col("wind_speed_10m"), col("wind_gusts_10m"), col("wind_direction_10m"),
            col("temperature_2m"), col("precipitation"),
        ):
            if ws is None:
                continue
            valid = datetime.fromisoformat(t).replace(tzinfo=timezone.utc)
            lead = "" if issued is None else round((valid - issued).total_seconds() / 3600)
            rows.append({
                "issued": "archive" if issued is None else issued.strftime("%Y-%m-%dT%H:%MZ"),
                "model": model,
                "point": point.id,
                "valid": valid.strftime("%Y-%m-%dT%H:%MZ"),
                "lead_h": lead,
                "wind": ws, "gust": wg, "dir": wd, "temp": tt, "precip": pr,
            })
    return rows


def fetch_forecasts(client: httpx.Client, points: list[Point], models: list[str], now: datetime) -> tuple[list[dict], list[str]]:
    issued = now.replace(minute=0, second=0, microsecond=0)
    rows, log = [], []
    for model in models:
        try:
            resp = client.get(FORECAST_URL, params=forecast_params(points, model), timeout=60)
            resp.raise_for_status()
            got = rows_from_payload(resp.json(), points, model, issued)
        except Exception as e:  # one model failing (or an unknown id) must not stop the others
            log.append(f"{model}: {type(e).__name__}: {str(e)[:200]}")
            continue
        covered = sorted({r["point"] for r in got})
        log.append(f"{model}: {len(got)} hours, {len(covered)} of {len(points)} points")
        rows += got
    return rows, log


def fetch_archive(client: httpx.Client, points: list[Point], models: list[str], days: int, today: date) -> tuple[list[dict], list[str]]:
    """Past forecasts that Open-Meteo has kept (first hours of each run, joined together)."""
    rows, log = [], []
    for model in models:
        params = forecast_params(points, model)
        del params["forecast_hours"]
        params["start_date"] = (today - timedelta(days=days)).isoformat()
        params["end_date"] = (today - timedelta(days=1)).isoformat()
        try:
            resp = client.get(ARCHIVE_URL, params=params, timeout=120)
            resp.raise_for_status()
            got = rows_from_payload(resp.json(), points, model, None)
        except Exception as e:
            log.append(f"archive {model}: {type(e).__name__}: {str(e)[:200]}")
            continue
        log.append(f"archive {model}: {len(got)} hours")
        rows += got
    return rows, log


def write_rows(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(path, "wt", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)


def read_rows(data_dir: Path) -> list[dict]:
    rows = []
    for path in sorted((data_dir / "forecasts").rglob("*.csv.gz")):
        with gzip.open(path, "rt", newline="", encoding="utf-8") as f:
            rows += list(csv.DictReader(f))
    return rows


# --- Measurements ----------------------------------------------------------

# DWD product folder, file name part, and the value columns we use.
PRODUCTS = {
    "wind": ("wind", "ff", ["FF_10"]),
    "gust": ("extreme_wind", "fx", ["FX_10"]),
    "temp": ("air_temperature", "tu", ["TT_10"]),
}


@dataclass(frozen=True)
class Station:
    id: str
    name: str
    lat: float
    lon: float
    until: date


def _text(content: bytes) -> str:
    try:
        return content.decode("utf-8")
    except UnicodeDecodeError:
        return content.decode("latin-1")


def parse_station_list(text: str) -> list[Station]:
    """DWD's 'Beschreibung_Stationen' file: id, from, until, height, lat, lon, name, state, ..."""
    stations = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 7 or not parts[0].isdigit():
            continue
        try:
            until = datetime.strptime(parts[2], "%Y%m%d").date()
            lat, lon = float(parts[4]), float(parts[5])
        except ValueError:
            continue
        stations.append(Station(parts[0].zfill(5), " ".join(parts[6:-2]) or parts[6], lat, lon, until))
    return stations


def nearest_station(stations: list[Station], lat: float, lon: float, since: date) -> tuple[Station, float] | None:
    live = [(s, distance_km(lat, lon, s.lat, s.lon)) for s in stations if s.until >= since]
    live = [x for x in live if x[1] <= MAX_STATION_KM]
    return min(live, key=lambda x: x[1]) if live else None


def parse_measurements(text: str, column: str) -> dict[datetime, float]:
    """One DWD 10-minute 'produkt' file: semicolon separated, MESS_DATUM = yyyymmddHHMM in UTC, -999 = missing."""
    lines = [l for l in text.splitlines() if l.strip()]
    header = [h.strip() for h in lines[0].split(";")]
    i_time, i_value = header.index("MESS_DATUM"), header.index(column)
    values = {}
    for line in lines[1:]:
        parts = [p.strip() for p in line.split(";")]
        try:
            v = float(parts[i_value])
            t = datetime.strptime(parts[i_time], "%Y%m%d%H%M").replace(tzinfo=timezone.utc)
        except (ValueError, IndexError):
            continue
        if v > -998:
            values[t] = v
    return values


def hourly(values: dict[datetime, float], kind: str) -> dict[datetime, float]:
    """Model-comparable hourly values: wind and temperature at the full hour, gusts as the hour's maximum."""
    if kind != "gust":
        return {t: v for t, v in values.items() if t.minute == 0}
    hours: dict[datetime, list[float]] = {}
    for t, v in values.items():
        end = t.replace(minute=0) if t.minute == 0 else t.replace(minute=0) + timedelta(hours=1)
        hours.setdefault(end, []).append(v)
    return {t: max(vs) for t, vs in hours.items() if len(vs) >= 4}


class Dwd:
    def __init__(self, client: httpx.Client):
        self.client = client
        self._lists: dict[str, list[Station]] = {}
        self._index: dict[str, str] = {}

    def stations(self, kind: str) -> list[Station]:
        if kind not in self._lists:
            folder, short, _ = PRODUCTS[kind]
            url = f"{DWD_10MIN}/{folder}/recent/zehn_min_{short}_Beschreibung_Stationen.txt"
            resp = self.client.get(url, timeout=60)
            resp.raise_for_status()
            self._lists[kind] = parse_station_list(_text(resp.content))
        return self._lists[kind]

    def measurements(self, kind: str, station_id: str) -> dict[datetime, float]:
        folder, _, (column,) = PRODUCTS[kind]
        if kind not in self._index:
            resp = self.client.get(f"{DWD_10MIN}/{folder}/recent/", timeout=60)
            resp.raise_for_status()
            self._index[kind] = resp.text
        names = re.findall(rf'href="([^"]*_{station_id}_akt\.zip)"', self._index[kind])
        if not names:
            return {}
        resp = self.client.get(f"{DWD_10MIN}/{folder}/recent/{names[0]}", timeout=120)
        resp.raise_for_status()
        with zipfile.ZipFile(io.BytesIO(resp.content)) as z:
            produkt = [n for n in z.namelist() if n.startswith("produkt")]
            return hourly(parse_measurements(_text(z.read(produkt[0])), column), kind) if produkt else {}


def observations(client: httpx.Client, points: list[Point], since: date) -> tuple[dict, dict, list[str]]:
    """Per point and kind: {valid time: value}, plus the stations used."""
    dwd = Dwd(client)
    obs: dict[str, dict[str, dict[datetime, float]]] = {}
    used: dict[str, dict[str, dict]] = {}
    log, cache = [], {}
    for p in points:
        for kind in PRODUCTS:
            try:
                found = nearest_station(dwd.stations(kind), p.lat, p.lon, since)
                if not found:
                    log.append(f"{p.id} {kind}: no DWD station within {MAX_STATION_KM:.0f} km")
                    continue
                station, km = found
                if (kind, station.id) not in cache:
                    cache[(kind, station.id)] = dwd.measurements(kind, station.id)
                obs.setdefault(p.id, {})[kind] = cache[(kind, station.id)]
                used.setdefault(p.id, {})[kind] = {"station": station.id, "name": station.name, "km": round(km, 1)}
            except Exception as e:
                log.append(f"{p.id} {kind}: {type(e).__name__}: {str(e)[:200]}")
    return obs, used, log


# --- Scoring ---------------------------------------------------------------


def light(wind: float | None, gust: float | None, limits: Thresholds = Thresholds()) -> int | None:
    """The wind part of the rowing light: 0 green, 1 amber, 2 red."""
    if wind is None or gust is None:
        return None
    if wind >= limits.wind_red_ms or gust >= limits.gust_red_ms:
        return 2
    if wind >= limits.wind_amber_ms or gust >= limits.gust_amber_ms:
        return 1
    return 0


def _f(v) -> float | None:
    return None if v in ("", None) else float(v)


def bucket(row: dict) -> str:
    if row["issued"] == "archive":
        return "archive"
    lead = int(row["lead_h"])
    return "day 1" if lead <= 24 else "day 2"


@dataclass
class Score:
    n: int = 0
    wind_err: list = None
    gust_err: list = None
    temp_err: list = None
    light_wrong: int = 0
    light_n: int = 0

    def __post_init__(self):
        self.wind_err, self.gust_err, self.temp_err = [], [], []


def score(rows: list[dict], obs: dict) -> dict[tuple[str, str, str], Score]:
    """Scores keyed by (point, model, bucket); 'all' as point is every point together."""
    scores: dict[tuple[str, str, str], Score] = {}
    for r in rows:
        point_obs = obs.get(r["point"])
        if not point_obs:
            continue
        valid = datetime.strptime(r["valid"], "%Y-%m-%dT%H:%MZ").replace(tzinfo=timezone.utc)
        ow, og, ot = (point_obs.get(k, {}).get(valid) for k in ("wind", "gust", "temp"))
        if ow is None and og is None and ot is None:
            continue
        fw, fg, ft = _f(r["wind"]), _f(r["gust"]), _f(r["temp"])
        for key in ((r["point"], r["model"], bucket(r)), ("all", r["model"], bucket(r))):
            s = scores.setdefault(key, Score())
            s.n += 1
            if ow is not None and fw is not None:
                s.wind_err.append(fw - ow)
            if og is not None and fg is not None:
                s.gust_err.append(fg - og)
            if ot is not None and ft is not None:
                s.temp_err.append(ft - ot)
            lo, lf = light(ow, og), light(fw, fg)
            if lo is not None and lf is not None:
                s.light_n += 1
                s.light_wrong += lo != lf
    return scores


def disagreements(rows: list[dict], model: str = CURRENT, reference: str = REFERENCE) -> list[dict]:
    """Hours where `model` and `reference` from the same run differ by more than DISAGREE."""
    ref = {(r["issued"], r["point"], r["valid"]): r for r in rows if r["model"] == reference}
    found = []
    for r in rows:
        if r["model"] != model:
            continue
        other = ref.get((r["issued"], r["point"], r["valid"]))
        if not other:
            continue
        diffs = {}
        for k, limit in DISAGREE.items():
            a, b = _f(r[k]), _f(other[k])
            if a is not None and b is not None and abs(a - b) > limit:
                diffs[k] = round(a - b, 1)
        if diffs:
            found.append({"issued": r["issued"], "point": r["point"], "valid": r["valid"], **diffs})
    return found


# --- Report ----------------------------------------------------------------


def _mae(errs: list) -> str:
    return f"{mean(abs(e) for e in errs):.1f}" if errs else "–"


def _bias(errs: list) -> str:
    return f"{mean(errs):+.1f}" if errs else "–"


def _table(scores: dict, point: str, buck: str) -> list[str]:
    rows = [(m, s) for (p, m, b), s in scores.items() if p == point and b == buck and s.wind_err]
    if not rows:
        return []
    rows.sort(key=lambda x: mean(abs(e) for e in x[1].wind_err))
    out = [
        "| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for m, s in rows:
        wrong = f"{100 * s.light_wrong / s.light_n:.0f} %" if s.light_n else "–"
        name = f"**{m}** (app today)" if m == CURRENT else m
        out.append(f"| {name} | {s.n} | {_mae(s.wind_err)} | {_bias(s.wind_err)} | {_mae(s.gust_err)} | {_mae(s.temp_err)} | {wrong} |")
    return out


def report(points: list[Point], rows: list[dict], obs: dict, used: dict, now: datetime) -> str:
    scores = score(rows, obs)
    runs = sorted({r["issued"] for r in rows if r["issued"] != "archive"})
    lines = [
        f"# Model check, {now:%Y-%m-%d %H:%M} UTC",
        "",
        f"{len(runs)} forecast runs stored" + (f" ({runs[0]} to {runs[-1]})" if runs else "") + ".",
        "Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.",
        "\"Light wrong\" = how often wind and gusts alone would have given a different rowing light than measured.",
        "Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.",
        "",
    ]
    for buck in ("day 1", "day 2", "archive"):
        table = _table(scores, "all", buck)
        if table:
            lines += [f"## All points, {buck}", ""] + table + [""]
    dis = disagreements(rows)
    if dis:
        per_point: dict[str, int] = {}
        for d in dis:
            per_point[d["point"]] = per_point.get(d["point"], 0) + 1
        lines += [
            f"## {CURRENT} vs {REFERENCE}",
            "",
            f"{len(dis)} forecast hours differ by more than wind {DISAGREE['wind']} m/s, gusts {DISAGREE['gust']} m/s or air {DISAGREE['temp']} °C.",
            "",
            "| Point | Hours |",
            "| --- | --- |",
        ] + [f"| {p} | {n} |" for p, n in sorted(per_point.items(), key=lambda x: -x[1])] + [""]
        last = dis[-10:]
        lines += ["Latest:", "", "| Run | Point | Hour | Differences |", "| --- | --- | --- | --- |"]
        lines += [
            f"| {d['issued']} | {d['point']} | {d['valid']} | "
            + ", ".join(f"{k} {d[k]:+}" for k in DISAGREE if k in d) + " |"
            for d in last
        ] + [""]
    lines += ["## Per point (day 1)", ""]
    for p in points:
        st = used.get(p.id, {})
        where = ", ".join(f"{k}: {v['name']} ({v['km']} km)" for k, v in st.items()) or "no station"
        lines += [f"### {p.name}", "", f"Stations: {where}", ""]
        table = _table(scores, p.id, "day 1")
        lines += (table or ["No matched hours yet."]) + [""]
    lines += ["Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0)."]
    return "\n".join(lines)
