"""HTTP API for the iPhone app.

Run locally:  uvicorn rowerweather.api:app --reload   (from the backend folder)
"""

from __future__ import annotations

import time
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import FastAPI, HTTPException

from . import locations, outlines
from .forecast import RowingHour, rowing_forecast
from .sources import gkd, open_meteo
from .sun import sun_days

CACHE_SECONDS = 30 * 60
ATTRIBUTION = [
    "Weather: Deutscher Wetterdienst (DWD) via Open-Meteo, CC BY 4.0",
    "Lake outlines: © OpenStreetMap contributors, ODbL",
    "Water temperature: Gewässerkundlicher Dienst Bayern (LfU), CC BY 4.0",
]

app = FastAPI(title="RowerWeather")
_locations = locations.load()
_cache: dict[str, tuple[float, dict]] = {}


def _point(p: locations.Point) -> dict:
    return {"lat": p.lat, "lon": p.lon}


@app.get("/lakes")
def list_lakes() -> list[dict]:
    return [
        {
            "id": lake.id,
            "name": lake.name,
            "center": _point(lake.center),
            "clubs": [
                {
                    "id": c.id,
                    "name": c.name,
                    "shortName": c.short_name,
                    "address": c.address,
                    "website": c.website,
                    "launchPoint": _point(c.launch_point),
                    "launchPointVerified": c.launch_point_verified,
                }
                for c in _locations.clubs_on(lake.id)
            ],
        }
        for lake in _locations.lakes.values()
    ]


def _utc(t: datetime) -> str:
    return t.astimezone(timezone.utc).replace(microsecond=0).isoformat()


def _hour_json(h: RowingHour) -> dict:
    w = h.weather
    return {
        "time": w.time.isoformat(),
        "light": h.assessment.light.name.lower(),
        "reasons": [{"condition": name, "light": light.name.lower()} for name, light in h.assessment.reasons],
        "windSpeedMs": w.wind_speed_ms,
        "windGustMs": w.wind_gust_ms,
        "windFromDeg": w.wind_from_deg,
        "waveHeightM": None if h.wave_height_m is None else round(h.wave_height_m, 2),
        "fetchM": None if h.fetch_m is None else round(h.fetch_m),
        "visibilityM": w.visibility_m,
        "temperatureC": w.temperature_c,
        "cloudCoverPct": w.cloud_cover_pct,
        "sunUp": h.sun_up,
    }


@app.get("/clubs/{club_id}/forecast")
async def club_forecast(club_id: str) -> dict:
    club = _locations.clubs.get(club_id)
    if club is None:
        raise HTTPException(status_code=404, detail="unknown club")

    cached = _cache.get(club_id)
    if cached and time.monotonic() - cached[0] < CACHE_SECONDS:
        return cached[1]

    lake = _locations.lakes[club.lake_id]
    now = datetime.now(timezone.utc)
    async with httpx.AsyncClient() as client:
        try:
            weather = await open_meteo.fetch(client, club.launch_point.lat, club.launch_point.lon)
        except httpx.HTTPError:
            raise HTTPException(status_code=503, detail="weather service unavailable, try again shortly")
        water = None
        if lake.gkd_water_temperature_station:
            try:
                water = await gkd.fetch_latest(client, lake.gkd_water_temperature_station, now)
            except httpx.HTTPError:
                water = None  # the forecast is still useful without it
    hours = rowing_forecast(club, weather, outlines.load(club.lake_id), water.celsius if water else None)
    body = {
        "clubId": club.id,
        "lakeId": club.lake_id,
        "generatedAt": now.replace(microsecond=0).isoformat(),
        "waterTemperature": None
        if water is None
        else {"celsius": water.celsius, "measuredAt": water.time.astimezone(timezone.utc).isoformat()},
        "attribution": ATTRIBUTION,
        "daylight": [
            {"date": d.day.isoformat(), "sunrise": _utc(d.sunrise), "sunset": _utc(d.sunset)}
            for d in sun_days(now, now + timedelta(hours=len(hours)), club.launch_point.lat, club.launch_point.lon)
        ],
        "hours": [_hour_json(h) for h in hours],
    }
    _cache[club_id] = (time.monotonic(), body)
    return body
