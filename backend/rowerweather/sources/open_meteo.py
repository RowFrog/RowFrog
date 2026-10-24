"""Hourly forecast from Open-Meteo, using DWD's ICON models.

`icon_seamless` uses ICON-D2 (2 km) for the first two days, then ICON-EU and
ICON global. Open-Meteo's free tier is for non-commercial use only and allows
fewer than 10,000 calls a day; the backend calls it once per launch point and
caches the result, so app users never call it directly. A request for one
point counts as one call per 10 variables (see call_weight), so the backend
asks for few variables and works out the rest itself.

Data: Deutscher Wetterdienst via Open-Meteo, CC BY 4.0.
"""

from __future__ import annotations

import asyncio
import math
import time
from collections import deque
from dataclasses import dataclass, replace
from datetime import date, datetime, timezone

import httpx

BASE_URL = "https://api.open-meteo.com/v1/forecast"
ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
# Dew point and feels-like temperature are worked out from these (derive()),
# and daylight comes from the sun times, which keeps a club at 12 variables.
HOURLY = [
    "temperature_2m",
    "wind_speed_10m",
    "wind_gusts_10m",
    "wind_direction_10m",
    "cloud_cover",
    "cloud_cover_low",
    "visibility",
    "precipitation",
    "weather_code",
    "relative_humidity_2m",
    "pressure_msl",
    "cape",
]
# What the lake view needs at its forecast points: wind for the waves, fog and thunderstorms.
LAKE_HOURLY = [
    "wind_speed_10m",
    "wind_gusts_10m",
    "wind_direction_10m",
    "visibility",
    "precipitation",
    "cape",
]


# Open-Meteo allows 600 calls a minute; staying at half leaves room for other users of GitHub's runners.
MAX_CALLS_PER_MINUTE = 300


def call_weight(variables: int, points: int = 1, days: float = 2) -> float:
    """How many calls Open-Meteo counts for a request: one per point and 10 variables,
    more for over two weeks of data, at least one per point."""
    weight = variables / 10
    return points * max(1.0, weight, weight * days / 14)


def params_weight(params: dict[str, str]) -> float:
    variables = len((params.get("hourly") or params.get("daily") or "").split(","))
    points = params.get("latitude", "").count(",") + 1
    if "forecast_hours" in params:
        days = int(params["forecast_hours"]) / 24
    elif "start_date" in params:
        days = (date.fromisoformat(params["end_date"]) - date.fromisoformat(params["start_date"])).days + 1
    else:
        days = int(params.get("past_days", 0)) + int(params.get("forecast_days", 7))
    return call_weight(variables, points, days)


# Calls counted since the process started, and the recent ones for pacing: (monotonic time, weight).
calls_counted = 0.0
_recent: deque[tuple[float, float]] = deque()


async def _pace(weight: float) -> None:
    """Waits until the request fits into the last minute's allowance."""
    while True:
        now = time.monotonic()
        while _recent and now - _recent[0][0] > 60:
            _recent.popleft()
        used = sum(w for _, w in _recent)
        if not _recent or used + weight <= MAX_CALLS_PER_MINUTE:
            _recent.append((now, weight))
            return
        await asyncio.sleep(60 - (now - _recent[0][0]) + 0.5)


@dataclass(frozen=True)
class ForecastHour:
    time: datetime
    temperature_c: float | None
    wind_speed_ms: float | None
    wind_gust_ms: float | None
    wind_from_deg: float | None
    cloud_cover_pct: float | None
    cloud_cover_low_pct: float | None
    visibility_m: float | None
    precipitation_mm: float | None
    cape_jkg: float | None
    is_day: bool | None
    # WMO weather code (0 clear ... 61 rain ... 96/99 thunderstorm with hail).
    weather_code: int | None = None
    # How warm it feels, from temperature, wind, humidity and sun.
    apparent_temperature_c: float | None = None
    humidity_pct: float | None = None
    dew_point_c: float | None = None
    # Air pressure reduced to sea level, in hPa.
    pressure_hpa: float | None = None


def request_params(
    lat: float, lon: float, hours: int = 48, hourly: list[str] = HOURLY, models: str = "icon_seamless"
) -> dict[str, str]:
    return {
        "latitude": f"{lat:.4f}",
        "longitude": f"{lon:.4f}",
        "hourly": ",".join(hourly),
        "models": models,
        "wind_speed_unit": "ms",
        "timezone": "GMT",
        "forecast_hours": str(hours),
    }


def dew_point(temperature_c: float, humidity_pct: float) -> float:
    """Magnus formula, good to about 0.1 °C in the range that matters here."""
    gamma = math.log(max(humidity_pct, 1.0) / 100) + 17.62 * temperature_c / (243.12 + temperature_c)
    return round(243.12 * gamma / (17.62 - gamma), 1)


def apparent_temperature(temperature_c: float, humidity_pct: float, wind_ms: float) -> float:
    """Steadman's apparent temperature without sunshine (as used by the Australian
    Bureau of Meteorology), the formula Open-Meteo's own value is based on."""
    vapour_hpa = humidity_pct / 100 * 6.105 * math.exp(17.27 * temperature_c / (237.7 + temperature_c))
    return round(temperature_c + 0.33 * vapour_hpa - 0.70 * wind_ms - 4.0, 1)


def derive(h: ForecastHour) -> ForecastHour:
    """Fills in dew point and feels-like temperature when the request did not ask for them."""
    t, rh = h.temperature_c, h.humidity_pct
    if t is None or rh is None:
        return h
    return replace(
        h,
        dew_point_c=h.dew_point_c if h.dew_point_c is not None else dew_point(t, rh),
        apparent_temperature_c=h.apparent_temperature_c
        if h.apparent_temperature_c is not None
        else apparent_temperature(t, rh, h.wind_speed_ms or 0.0),
    )


def parse(payload: dict) -> list[ForecastHour]:
    h = payload["hourly"]

    def col(name: str) -> list:
        return h.get(name) or [None] * len(h["time"])

    rows = zip(
        h["time"],
        col("temperature_2m"),
        col("wind_speed_10m"),
        col("wind_gusts_10m"),
        col("wind_direction_10m"),
        col("cloud_cover"),
        col("cloud_cover_low"),
        col("visibility"),
        col("precipitation"),
        col("cape"),
        col("is_day"),
        col("weather_code"),
        col("apparent_temperature"),
        col("relative_humidity_2m"),
        col("dew_point_2m"),
        col("pressure_msl"),
    )
    hours = [
        ForecastHour(
            time=datetime.fromisoformat(t).replace(tzinfo=timezone.utc),
            temperature_c=temp,
            wind_speed_ms=ws,
            wind_gust_ms=wg,
            wind_from_deg=wd,
            cloud_cover_pct=cc,
            cloud_cover_low_pct=ccl,
            visibility_m=vis,
            precipitation_mm=pr,
            cape_jkg=cape,
            is_day=None if day is None else bool(day),
            weather_code=None if code is None else int(code),
            apparent_temperature_c=feels,
            humidity_pct=rh,
            dew_point_c=dew,
            pressure_hpa=hpa,
        )
        for t, temp, ws, wg, wd, cc, ccl, vis, pr, cape, day, code, feels, rh, dew, hpa in rows
    ]
    return [derive(h) for h in hours]


async def _get(client: httpx.AsyncClient, url: str, params: dict[str, str]) -> dict:
    global calls_counted
    weight = params_weight(params)
    # Live checks on GitHub saw about one connect timeout in six calls, so
    # connection failures are retried once before giving up.
    for attempt in range(2):
        await _pace(weight)
        calls_counted += weight
        try:
            resp = await client.get(url, params=params, timeout=20)
            break
        except httpx.TransportError:
            if attempt == 1:
                raise
    resp.raise_for_status()
    return resp.json()


async def fetch(
    client: httpx.AsyncClient, lat: float, lon: float, hours: int = 48, models: str = "icon_seamless"
) -> list[ForecastHour]:
    return parse(await _get(client, BASE_URL, request_params(lat, lon, hours, models=models)))


async def fetch_many(
    client: httpx.AsyncClient,
    points: list[tuple[float, float]],
    hours: int = 48,
    hourly: list[str] = HOURLY,
    models: str = "icon_seamless",
) -> list[list[ForecastHour]]:
    """Forecasts for several points in one request (Open-Meteo takes comma-separated
    coordinates and answers with a list). Open-Meteo still counts calls per point."""
    params = request_params(points[0][0], points[0][1], hours, hourly, models)
    params["latitude"] = ",".join(f"{lat:.4f}" for lat, _ in points)
    params["longitude"] = ",".join(f"{lon:.4f}" for _, lon in points)
    payload = await _get(client, BASE_URL, params)
    return [parse(p) for p in (payload if isinstance(payload, list) else [payload])]


def daily_params(lat: float, lon: float, past_days: int = 92, forecast_days: int = 7) -> dict[str, str]:
    """Daily mean air temperature for the ice estimate, by local (German) day."""
    return {
        "latitude": f"{lat:.4f}",
        "longitude": f"{lon:.4f}",
        "daily": "temperature_2m_mean",
        "timezone": "Europe/Berlin",
        "past_days": str(past_days),
        "forecast_days": str(forecast_days),
    }


def parse_daily(payload: dict) -> list[tuple[date, float]]:
    """(day, mean °C) oldest first; days without a value are left out."""
    d = payload["daily"]
    return [(date.fromisoformat(t), v) for t, v in zip(d["time"], d["temperature_2m_mean"]) if v is not None]


async def fetch_daily_mean(client: httpx.AsyncClient, lat: float, lon: float) -> list[tuple[date, float]]:
    return parse_daily(await _get(client, BASE_URL, daily_params(lat, lon)))


async def fetch_archive_daily_mean(
    client: httpx.AsyncClient, lat: float, lon: float, start: date, end: date
) -> list[tuple[date, float]]:
    """Past daily means from Open-Meteo's archive (ERA5), for testing the ice model on past winters."""
    params = {
        "latitude": f"{lat:.4f}",
        "longitude": f"{lon:.4f}",
        "daily": "temperature_2m_mean",
        "timezone": "Europe/Berlin",
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
    }
    return parse_daily(await _get(client, ARCHIVE_URL, params))
