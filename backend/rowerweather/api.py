"""HTTP API for the iPhone app.

Run locally:  uvicorn rowerweather.api:app --reload   (from the backend folder)
"""

from __future__ import annotations

import logging
import os
import time
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import FastAPI, HTTPException

from . import locations, outlines
from .forecast import RowingHour, rowing_forecast
from .sources import dwd_warnings, gkd, open_meteo
from .sun import sun_days

CACHE_SECONDS = 30 * 60
# Warnings can be issued at short notice, so they are fetched more often than the forecast.
WARNINGS_CACHE_SECONDS = 5 * 60
LAKE_AREAS_CACHE_SECONDS = 24 * 3600
# Club ids that get a made-up lake storm warning, marked as a sample, for screenshots.
SAMPLE_WARNING_CLUBS = {c for c in os.environ.get("RW_SAMPLE_WARNING_CLUBS", "").split(",") if c}
ATTRIBUTION = [
    "Weather: Deutscher Wetterdienst (DWD) via Open-Meteo, CC BY 4.0",
    "Warnings: Deutscher Wetterdienst (DWD), CC BY 4.0",
    "Lake outlines: © OpenStreetMap contributors, ODbL",
    "Water temperature: Gewässerkundlicher Dienst Bayern (LfU), CC BY 4.0",
]

app = FastAPI(title="RowerWeather")
_locations = locations.load()
_cache: dict[str, tuple[float, tuple]] = {}
_warnings_cache: dict[str, tuple[float, tuple]] = {}
_lake_areas: tuple[float, list[dwd_warnings.LakeArea]] | None = None


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
                    "source": c.source,
                    "abbreviation": c.abbreviation,
                }
                for c in _locations.clubs_on(lake.id)
            ],
        }
        for lake in _locations.lakes.values()
        if _locations.clubs_on(lake.id)
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
        "apparentTemperatureC": w.apparent_temperature_c,
        "cloudCoverPct": w.cloud_cover_pct,
        "precipitationMm": w.precipitation_mm,
        "weatherCode": w.weather_code,
        "sunUp": h.sun_up,
    }


def _warning_json(w: dwd_warnings.Warning, sample: bool = False) -> dict:
    return {
        "kind": w.kind,
        "area": w.area,
        "event": w.event,
        "severity": w.severity.lower(),
        "headline": w.headline,
        "description": w.description,
        "instruction": w.instruction,
        "onset": None if w.onset is None else _utc(w.onset),
        "expires": None if w.expires is None else _utc(w.expires),
        "sample": sample,
    }


def _sample_warning(area: str, now: datetime) -> dwd_warnings.Warning:
    start = now.replace(minute=0, second=0, microsecond=0)
    return dwd_warnings.Warning(
        kind="lake",
        area=area,
        event="STURM",
        severity="Severe",
        headline=f"Sturmwarnung für {area}",
        description="Es treten Sturmböen mit Geschwindigkeiten um 65 km/h (18 m/s, Bft 8) aus West auf.",
        instruction="Boote an Land holen oder sofort das nächste Ufer anfahren.",
        onset=start,
        expires=start + timedelta(hours=3),
    )


async def _lake_area(client: httpx.AsyncClient, club: locations.Club) -> dwd_warnings.LakeArea | None:
    global _lake_areas
    if _lake_areas is None or time.monotonic() - _lake_areas[0] > LAKE_AREAS_CACHE_SECONDS:
        _lake_areas = (time.monotonic(), await dwd_warnings.fetch_lake_areas(client))
    p = club.launch_point
    return dwd_warnings.lake_area_for(p.lon, p.lat, _lake_areas[1])


async def _warnings(client: httpx.AsyncClient, club: locations.Club, now: datetime) -> tuple[dict, list]:
    """The warnings block for the app and the warnings that count for the hourly light.

    If DWD cannot be reached the block says so ("unavailable"), so the app never
    shows "no warning" without having checked.
    """
    cached = _warnings_cache.get(club.id)
    if cached and time.monotonic() - cached[0] < WARNINGS_CACHE_SECONDS:
        return cached[1]
    try:
        area = await _lake_area(client, club)
        lake = []
        if area is not None:
            lake = [w for cell, w in await dwd_warnings.fetch_lake_warnings(client) if cell == area.warncell_id]
        local = await dwd_warnings.fetch_local_warnings(client, club.launch_point.lon, club.launch_point.lat)
    except (httpx.HTTPError, ValueError, KeyError) as e:
        logging.getLogger(__name__).warning("DWD warnings unavailable for %s: %r", club.id, e)
        result = ({"status": "unavailable", "lakeArea": None, "items": []}, [])
        _warnings_cache[club.id] = (time.monotonic() - WARNINGS_CACHE_SECONDS + 60, result)  # retry in a minute
        return result
    items = [_warning_json(w) for w in lake + local]
    if club.id in SAMPLE_WARNING_CLUBS and area is not None:
        sample = _sample_warning(area.name, now)
        lake.append(sample)
        items.insert(0, _warning_json(sample, sample=True))
    current = [w for w in lake + local if w.expires is None or w.expires > now]
    result = ({"status": "ok", "lakeArea": None if area is None else area.name, "items": items}, current)
    _warnings_cache[club.id] = (time.monotonic(), result)
    return result


@app.get("/clubs/{club_id}/forecast")
async def club_forecast(club_id: str) -> dict:
    club = _locations.clubs.get(club_id)
    if club is None:
        raise HTTPException(status_code=404, detail="unknown club")

    lake = _locations.lakes[club.lake_id]
    now = datetime.now(timezone.utc)
    async with httpx.AsyncClient() as client:
        cached = _cache.get(club_id)
        if cached and time.monotonic() - cached[0] < CACHE_SECONDS:
            weather, water = cached[1]
        else:
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
            _cache[club_id] = (time.monotonic(), (weather, water))
        warnings_block, warnings = await _warnings(client, club, now)
    hours = rowing_forecast(club, weather, outlines.load(club.lake_id), water.celsius if water else None, warnings)
    return {
        "clubId": club.id,
        "lakeId": club.lake_id,
        "generatedAt": now.replace(microsecond=0).isoformat(),
        "waterTemperature": None
        if water is None
        else {"celsius": water.celsius, "measuredAt": water.time.astimezone(timezone.utc).isoformat()},
        "warnings": warnings_block,
        "attribution": ATTRIBUTION,
        "daylight": [
            {"date": d.day.isoformat(), "sunrise": _utc(d.sunrise), "sunset": _utc(d.sunset)}
            for d in sun_days(now, now + timedelta(hours=len(hours)), club.launch_point.lat, club.launch_point.lon)
        ],
        "hours": [_hour_json(h) for h in hours],
    }
