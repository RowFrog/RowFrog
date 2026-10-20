"""Hourly forecast from Open-Meteo, using DWD's ICON models.

`icon_seamless` uses ICON-D2 (2 km) for the first two days, then ICON-EU and
ICON global. Open-Meteo's free tier is for non-commercial use only and allows
fewer than 10,000 calls a day; the backend calls it once per launch point and
caches the result, so app users never call it directly.

Data: Deutscher Wetterdienst via Open-Meteo, CC BY 4.0.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timezone

import httpx

BASE_URL = "https://api.open-meteo.com/v1/forecast"
ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
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
    "apparent_temperature",
    "relative_humidity_2m",
    "dew_point_2m",
    "pressure_msl",
    "cape",
    "is_day",
]


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


def request_params(lat: float, lon: float, hours: int = 48) -> dict[str, str]:
    return {
        "latitude": f"{lat:.4f}",
        "longitude": f"{lon:.4f}",
        "hourly": ",".join(HOURLY),
        "models": "icon_seamless",
        "wind_speed_unit": "ms",
        "timezone": "GMT",
        "forecast_hours": str(hours),
    }


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
    return [
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


async def _get(client: httpx.AsyncClient, url: str, params: dict[str, str]) -> dict:
    # Live checks on GitHub saw about one connect timeout in six calls, so
    # connection failures are retried once before giving up.
    for attempt in range(2):
        try:
            resp = await client.get(url, params=params, timeout=20)
            break
        except httpx.TransportError:
            if attempt == 1:
                raise
    resp.raise_for_status()
    return resp.json()


async def fetch(client: httpx.AsyncClient, lat: float, lon: float, hours: int = 48) -> list[ForecastHour]:
    return parse(await _get(client, BASE_URL, request_params(lat, lon, hours)))


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
