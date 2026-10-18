"""Hourly forecast from Open-Meteo, using DWD's ICON models.

`icon_seamless` uses ICON-D2 (2 km) for the first two days, then ICON-EU and
ICON global. Open-Meteo's free tier is for non-commercial use only and allows
fewer than 10,000 calls a day; the backend calls it once per launch point and
caches the result, so app users never call it directly.

Data: Deutscher Wetterdienst via Open-Meteo, CC BY 4.0.
"""

from __future__ import annotations

from dataclasses import dataclass
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
    "visibility",
    "precipitation",
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
        )
        for t, temp, ws, wg, wd, cc, ccl, vis, pr, cape, day in rows
    ]


async def fetch(client: httpx.AsyncClient, lat: float, lon: float, hours: int = 48) -> list[ForecastHour]:
    resp = await client.get(BASE_URL, params=request_params(lat, lon, hours), timeout=20)
    resp.raise_for_status()
    return parse(resp.json())
