"""Hourly forecast from Open-Meteo, using DWD's ICON models.

`icon_seamless` uses ICON-D2 (2 km) for the first two days, then ICON-EU and
ICON global. Open-Meteo's free tier is for non-commercial use only and allows
fewer than 10,000 calls a day; the backend calls it once per launch point and
caches the result, so app users never call it directly.

Data: Deutscher Wetterdienst via Open-Meteo, CC BY 4.0.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime, timezone

import httpx

BASE_URL = "https://api.open-meteo.com/v1/forecast"
HOURLY = [
    "temperature_2m",
    "wind_speed_10m",
    "wind_gusts_10m",
    "wind_direction_10m",
    "cloud_cover",
    "cloud_cover_low",
    "cloud_cover_mid",
    "cloud_cover_high",
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
    cloud_cover_mid_pct: float | None = None
    cloud_cover_high_pct: float | None = None
    # WHO UV index; only filled in the outlook (see fetch_outlook).
    uv_index: float | None = None


def request_params(lat: float, lon: float, hours: int = 48, past_hours: int = 0) -> dict[str, str]:
    params = {
        "latitude": f"{lat:.4f}",
        "longitude": f"{lon:.4f}",
        "hourly": ",".join(HOURLY),
        "models": "icon_seamless",
        "wind_speed_unit": "ms",
        "timezone": "GMT",
        "forecast_hours": str(hours),
    }
    if past_hours:
        params["past_hours"] = str(past_hours)
    return params


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
        col("cloud_cover_mid"),
        col("cloud_cover_high"),
        col("uv_index"),
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
            cloud_cover_mid_pct=ccm,
            cloud_cover_high_pct=cch,
            uv_index=uv,
        )
        for t, temp, ws, wg, wd, cc, ccl, vis, pr, cape, day, code, feels, rh, dew, hpa, ccm, cch, uv in rows
    ]


async def _get(client: httpx.AsyncClient, params: dict[str, str], timeout: float = 20) -> dict:
    # Live checks on GitHub saw about one connect timeout in six calls, so
    # connection failures are retried once before giving up.
    for attempt in range(2):
        try:
            resp = await client.get(BASE_URL, params=params, timeout=timeout)
            break
        except httpx.TransportError:
            if attempt == 1:
                raise
    resp.raise_for_status()
    return resp.json()


async def fetch(client: httpx.AsyncClient, lat: float, lon: float, hours: int = 48) -> list[ForecastHour]:
    return parse(await _get(client, request_params(lat, lon, hours)))


OUTLOOK_PAST_HOURS = 24
OUTLOOK_HOURS = 168


async def fetch_outlook(client: httpx.AsyncClient, lat: float, lon: float) -> list[ForecastHour]:
    """Yesterday plus the next 7 days, for the charts behind the conditions tiles.

    ICON has no UV index, so it comes from Open-Meteo's default model mix in a
    second, small call; without it the outlook simply has no UV values.
    """
    params = request_params(lat, lon, OUTLOOK_HOURS, OUTLOOK_PAST_HOURS)
    hours = parse(await _get(client, params))
    if all(h.uv_index is None for h in hours):
        uv_params = {k: v for k, v in params.items() if k != "models"}
        uv_params["hourly"] = "uv_index"
        try:
            payload = (await _get(client, uv_params))["hourly"]
            uv = {
                datetime.fromisoformat(t).replace(tzinfo=timezone.utc): v
                for t, v in zip(payload["time"], payload.get("uv_index") or [])
            }
            hours = [replace(h, uv_index=uv.get(h.time)) for h in hours]
        except (httpx.HTTPError, KeyError, ValueError):
            pass
    return hours


async def fetch_many(
    client: httpx.AsyncClient, points: list[tuple[float, float]], hours: int = 48
) -> list[list[ForecastHour]]:
    """Forecasts for several (lat, lon) points in one call; Open-Meteo answers with a list."""
    params = request_params(points[0][0], points[0][1], hours)
    params["latitude"] = ",".join(f"{lat:.4f}" for lat, _ in points)
    params["longitude"] = ",".join(f"{lon:.4f}" for _, lon in points)
    for attempt in range(2):
        try:
            resp = await client.get(BASE_URL, params=params, timeout=30)
            break
        except httpx.TransportError:
            if attempt == 1:
                raise
    resp.raise_for_status()
    payload = resp.json()
    payloads = payload if isinstance(payload, list) else [payload]
    return [parse(p) for p in payloads]
