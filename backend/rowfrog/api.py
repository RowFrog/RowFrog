"""HTTP API for the iPhone app.

Run locally:  uvicorn rowfrog.api:app --reload   (from the backend folder)
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass, fields, replace
from datetime import date, datetime, timedelta, timezone

import httpx
from fastapi import FastAPI, HTTPException

from . import ice, lake_level, lake_view, locations, outlines, river, water_estimate, warning_links, water_stations, weather_models
from .forecast import LOCAL, RowingHour, _thunderstorm, rowing_forecast
from .prepared import Prepared
from .score import HAIL_CODES, Light
from .sources import bafu, dwd_warnings, geosphere_warnings, gkd, meteoalarm, lake_temperature_satellite, open_meteo, pegelonline
from .sun import sun_days

CACHE_SECONDS = 30 * 60
# Warnings can be issued at short notice, so they are fetched more often than the forecast.
WARNINGS_CACHE_SECONDS = 5 * 60
LAKE_AREAS_CACHE_SECONDS = 24 * 3600
# Hours of forecast the app gets, from the current hour.
FORECAST_HOURS = 48
# Club ids that get a made-up warning, marked as a sample, for screenshots: a lake storm warning
# where DWD has a lake area, else a thunderstorm warning from the place's own service.
SAMPLE_WARNING_CLUBS = {c for c in os.environ.get("RW_SAMPLE_WARNING_CLUBS", "").split(",") if c}
# Clubs that get a made-up frost warning from six hours on, marked as a sample, to show that frost
# leaves the light alone and how a warning for later shows.
SAMPLE_FROST_CLUBS = {c for c in os.environ.get("RW_SAMPLE_FROST_CLUBS", "").split(",") if c}
# "from,speed,gusts" (degrees, m/s) replaces the wind in the lake view, marked as a
# sample, so screenshots show waves building across the lake on a calm day.
SAMPLE_LAKE_WIND = os.environ.get("RW_SAMPLE_LAKE_WIND", "")
# Lake ids that get a made-up Landsat reading from five days ago, for screenshots
# of the satellite water estimate (the publishing job loads the real ones).
SAMPLE_SATELLITE_WATER = {l for l in os.environ.get("RW_SAMPLE_SATELLITE_WATER", "").split(",") if l}
# Added to the credits when the forecast carries a satellite water estimate.
SATELLITE_WATER_CREDIT = {
    "copernicus-lswt": "Water temperature estimate: Copernicus Land Monitoring Service (Lake Surface Water Temperature)",
    "landsat": "Water temperature estimate: Landsat courtesy of the U.S. Geological Survey",
}
ATTRIBUTION = [
    "Weather: Deutscher Wetterdienst (DWD) via Open-Meteo, CC BY 4.0",
    "Warnings: Deutscher Wetterdienst (DWD), CC BY 4.0",
    "Lake outlines: © OpenStreetMap contributors, ODbL",
    "Water temperature: Gewässerkundlicher Dienst Bayern (LfU), CC BY 4.0",
]
# Who issues the weather warnings for a place, by country: (source, name, page).
# DWD's cover Germany only, GeoSphere's Austria and MeteoSwiss's (via MeteoAlarm)
# Switzerland; where the app reads no service it says so instead of "no warning".
LOCAL_WARNING_SERVICES = {
    "de": ("dwd", "Deutscher Wetterdienst (DWD)", "https://www.wettergefahren.de/"),
    "at": ("geosphere", "GeoSphere Austria", "https://warnungen.zamg.at/"),
    "ch": ("meteoswiss", "MeteoSwiss", "https://www.meteoswiss.admin.ch/weather/hazards/hazard-map.html"),
}
CHECKED_COUNTRIES = {"de", "at", "ch"}
# Added to the credits for clubs whose warnings come from another service than DWD.
WARNING_CREDIT = {
    "at": "Warnings: GeoSphere Austria, CC BY 4.0",
    "ch": "Warnings: MeteoSwiss, via MeteoAlarm (EUMETNET)",
}
# Added to the credits when the club's station is not a GKD Bayern one.
STATION_CREDIT = {
    "pegelonline": "Water temperature: PEGELONLINE, Wasserstraßen- und Schifffahrtsverwaltung des Bundes (WSV), DL-DE Zero 2.0",
    "bafu": "Water temperature: Bundesamt für Umwelt BAFU (Swiss Federal Office for the Environment), via api.existenz.ch",
}

app = FastAPI(title="RowFrog")
_locations = locations.load()
_cache: dict[str, tuple[float, tuple]] = {}
# River gauge readings per gauge (level, discharge, speed), shared by the clubs near it.
_gauge_cache: dict[str, tuple[float, tuple]] = {}
# What the publishing job loaded ahead in bulk (rowfrog.prepared); empty when the API runs on its own.
prepared = Prepared()
_warnings_cache: dict[str, tuple[float, tuple]] = {}
# All active lake warnings: one answer serves every lake club for a few minutes.
_lake_warnings: tuple[float, list[tuple[int, dwd_warnings.Warning]]] | None = None
_english: tuple[float, dict[str, dwd_warnings.EnglishText]] | None = None
_lake_areas: tuple[float, list[dwd_warnings.LakeArea]] | None = None
# All running Swiss warnings from MeteoAlarm: one answer serves every Swiss club for a few minutes.
_swiss_alerts: tuple[float, list[meteoalarm.Alert]] | None = None
for _lake_id in SAMPLE_SATELLITE_WATER:
    _day = datetime.now(LOCAL).date() - timedelta(days=5)
    prepared.satellite_water[_lake_id] = [
        lake_temperature_satellite.Reading(lake_temperature_satellite.LANDSAT, _day, 15.2, 800, platform="landsat-9")
    ]
# After two lakes in a row get no daily temperatures, the others skip them for
# AIR_DAYS_PAUSE seconds. On 1 Nov 2026 these calls alone timed out lake after
# lake (about a minute each) while forecasts still loaded, so the publish run
# overran; the ice estimate simply waits for a later run.
AIR_DAYS_PAUSE = 600
_air_days_failed = 0
_air_days_paused_until = 0.0
_lake_view_cache: dict[str, tuple[float, tuple]] = {}


def _point(p: locations.Point) -> dict:
    return {"lat": p.lat, "lon": p.lon}


def _lake_json(lake: locations.Lake, country: str | None = None) -> dict:
    """A water with its clubs; with `country`, only the clubs in that country."""
    return {
        "id": lake.id,
        "name": lake.name,
        "country": lake.country,
        "center": _point(lake.center),
        # "lake" or "river" (with "section": a stretch of a river or canal, see locations.py).
        "kind": lake.kind,
        "section": _section_json(lake),
        # The lake view needs an outline (data/outlines).
        "hasOutline": (outlines.DEFAULT_DIR / f"{lake.id}.geojson").exists(),
        "clubs": [
            {
                "id": c.id,
                "name": c.name,
                "shortName": c.short_name,
                "address": c.address,
                "website": c.website,
                "launchPoint": _point(c.launch_point),
                "launchPointVerified": c.launch_point_verified,
                # Set by the club or checked by hand; then the maps split off the clubhouse.
                "launchPointSet": c.launch_point_set,
                "clubhouse": _point(c.clubhouse) if c.clubhouse else None,
                "source": c.source,
                "abbreviation": c.abbreviation,
                "country": c.country,
                "region": c.region,
            }
            for c in _locations.clubs_on(lake.id, country)
        ],
    }


@app.get("/lakes")
# The same list under a path that also works as a static file next to lakes/<id>/view.
@app.get("/lakes/index")
def list_lakes() -> list[dict]:
    """Every water with clubs, in all countries; for app versions before the country files."""
    return [_lake_json(lake) for lake in _locations.lakes.values() if _locations.clubs_on(lake.id)]


@app.get("/countries")
@app.get("/countries/index")
def list_countries() -> list[dict]:
    """The countries the search covers, with how many clubs and where they lie.

    The app loads its own country's file first and others when needed; the
    box around a country's clubs tells it which countries are near the user.
    """
    out = []
    for code in _locations.countries():
        clubs = [c for c in _locations.clubs.values() if c.country == code]
        lats = [c.launch_point.lat for c in clubs]
        lons = [c.launch_point.lon for c in clubs]
        name, name_de = locations.COUNTRIES.get(code, (code.upper(), code.upper()))
        out.append({
            "code": code,
            "name": name,
            "nameDe": name_de,
            "clubs": len(clubs),
            "bounds": {"south": min(lats), "west": min(lons), "north": max(lats), "east": max(lons)},
        })
    return out


@app.get("/countries/{code}/lakes")
def country_lakes(code: str) -> list[dict]:
    """The waters with clubs in one country, with only that country's clubs.

    A lake on a border (Lake Constance) is listed in each country with its own clubs.
    """
    if code not in _locations.countries():
        raise HTTPException(status_code=404, detail="unknown country")
    return [_lake_json(lake, code) for lake in _locations.lakes.values() if _locations.clubs_on(lake.id, code)]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _from_now(weather: list, now: datetime) -> list:
    """The forecast from the current hour on; stored forecasts can be a few hours old."""
    hour = now.replace(minute=0, second=0, microsecond=0)
    return [h for h in weather if h.time >= hour][:FORECAST_HOURS]


def lake_grid(lake_id: str, rings) -> lake_view.Grid:
    lake = _locations.lakes.get(lake_id)
    if lake is not None and lake.section is not None:
        return lake_view.grid_for(lake_id, rings, lake_view.river_samples(lake.section.length_km), narrow=True)
    return lake_view.grid_for(lake_id, rings, prepared.lake_samples.get(lake_id, lake_view.MAX_SAMPLES))


async def _gauge_readings(client: httpx.AsyncClient, gauge: river.Gauge):
    """The gauge's level, discharge and speed of the last two days, cached for clubs sharing it."""
    cached = _gauge_cache.get(gauge.id)
    if cached and time.monotonic() - cached[0] < CACHE_SECONDS:
        return cached[1]
    found = []
    for series in ("W", "Q", "VA"):
        if series not in gauge.series:
            found.append([])
            continue
        try:
            found.append([river.Reading(t, v) for t, v in await pegelonline.fetch_series(client, gauge.id, series)])
        except (httpx.HTTPError, ValueError, KeyError) as e:
            logging.getLogger(__name__).warning("PEGELONLINE %s %s failed: %r", gauge.name, series, e)
            if series == "W":
                return None
            found.append([])
    _gauge_cache[gauge.id] = (time.monotonic(), tuple(found))
    return tuple(found)


async def _lake_levels(client: httpx.AsyncClient, lake: lake_level.LevelLake):
    """The lake gauge's levels of the last week, cached for clubs on the same lake."""
    cached = _gauge_cache.get("gkd:" + lake.station)
    if cached and time.monotonic() - cached[0] < CACHE_SECONDS:
        return cached[1]
    try:
        found = await gkd.fetch_levels(client, lake.station)
    except httpx.HTTPError as e:
        logging.getLogger(__name__).warning("GKD level %s failed: %r", lake.name, e)
        return None
    _gauge_cache["gkd:" + lake.station] = (time.monotonic(), found)
    return found


def _section_width_m(lake: locations.Lake, rings) -> float | None:
    """A river section's mean width: its water area over its length."""
    if lake.section is None or not rings or not lake.section.length_km:
        return None
    lons = [x for ring in rings for x, _ in ring]
    lats = [y for ring in rings for _, y in ring]
    lon0, lat0 = (min(lons) + max(lons)) / 2, (min(lats) + max(lats)) / 2
    area = lake_view._water_area_m2([[lake_view._local(x, y, lon0, lat0) for x, y in ring] for ring in rings])
    return area / (lake.section.length_km * 1000)


def _end_json(end: locations.SectionEnd | None) -> dict | None:
    if end is None:
        return None
    return {"km": end.km, "end": end.end, "what": end.what, "at": _point(end.at)}


def _section_json(lake: locations.Lake, full: bool = False) -> dict | None:
    """A river section's facts for the app: the place it is named after and,
    for the River view (`full`), where it ends each way and the river line."""
    s = lake.section
    if s is None:
        return None
    out = {"place": s.place, "waterway": s.waterway, "lengthKm": s.length_km}
    if full:
        out.update(
            up=_end_json(s.up),
            down=_end_json(s.down),
            flow=[[[x, y] for x, y in line] for line in outlines.flow(lake.id)],
        )
    return out


def _utc(t: datetime) -> str:
    return t.astimezone(timezone.utc).replace(microsecond=0).isoformat()


def _reasons_json(reasons: list[tuple[str, Light]], warning_topic: str | None) -> list[dict]:
    """The weather warning reason also says what the warning is about ("wind", "thunderstorm", ...)."""
    out = []
    for name, light in reasons:
        item = {"condition": name, "light": light.name.lower()}
        if name == "weather_warning" and warning_topic:
            item["topic"] = warning_topic
        out.append(item)
    return out


def _hour_json(h: RowingHour) -> dict:
    w = h.weather
    return {
        "time": w.time.isoformat(),
        "light": h.assessment.light.name.lower(),
        "reasons": _reasons_json(h.assessment.reasons, h.warning_topic),
        "windSpeedMs": w.wind_speed_ms,
        "windGustMs": w.wind_gust_ms,
        "windFromDeg": w.wind_from_deg,
        "waveHeightM": None if h.wave_height_m is None else round(h.wave_height_m, 2),
        "fetchM": None if h.fetch_m is None else round(h.fetch_m),
        "visibilityM": w.visibility_m,
        "temperatureC": w.temperature_c,
        "apparentTemperatureC": w.apparent_temperature_c,
        "humidityPct": w.humidity_pct,
        "dewPointC": w.dew_point_c,
        "pressureHpa": w.pressure_hpa,
        "cloudCoverPct": w.cloud_cover_pct,
        "cloudCoverLowPct": w.cloud_cover_low_pct,
        "cloudCoverMidPct": w.cloud_cover_mid_pct,
        "cloudCoverHighPct": w.cloud_cover_high_pct,
        "uvIndex": w.uv_index,
        "capeJkg": w.cape_jkg,
        "precipitationMm": w.precipitation_mm,
        "weatherCode": w.weather_code,
        "sunUp": h.sun_up,
    }


def _english_json(e: dwd_warnings.EnglishText | None) -> dict | None:
    if e is None:
        return None
    return {
        "event": e.event,
        "headline": e.headline,
        "description": e.description,
        "instruction": e.instruction,
        "official": e.official,
    }


def _warning_json(
    w: dwd_warnings.Warning, english: dwd_warnings.EnglishText | None = None, sample: bool = False, club: locations.Club | None = None
) -> dict:
    return {
        "kind": w.kind,
        "source": w.source,
        "area": w.area,
        "event": w.event,
        "severity": w.severity.lower(),
        "headline": w.headline,
        "description": w.description,
        "instruction": w.instruction,
        "onset": None if w.onset is None else _utc(w.onset),
        "expires": None if w.expires is None else _utc(w.expires),
        "sample": sample,
        # DWD's English text where it publishes one, else the event and headline translated.
        "english": _english_json(english),
        # The issuing service's page for this warning's place, {"de": url, "en": url} (warning_links.py).
        "links": None if club is None else warning_links.links(w.source, w.kind, club.address, club.launch_point.lon, club.launch_point.lat),
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


_SAMPLE_ENGLISH = dwd_warnings.EnglishText(
    event="gale",
    headline="Gale warning for the lake",
    description="Gale-force gusts around 65 km/h (18 m/s, Bft 8) from the west.",
    instruction="Bring boats ashore or head for the nearest shore at once.",
    official=True,
)


def _sample_local_warning(club: locations.Club, now: datetime) -> dwd_warnings.Warning:
    start = now.replace(minute=0, second=0, microsecond=0)
    return dwd_warnings.Warning(
        kind="local",
        area=club.name,
        event="GEWITTER",
        severity="Moderate",
        headline="Gewitterwarnung",
        description="Es treten Gewitter mit Starkregen und Sturmböen um 70 km/h auf.",
        instruction="Gewässer meiden und Schutz in Gebäuden suchen.",
        onset=start,
        expires=start + timedelta(hours=3),
        identifier=f"sample-{club.id}",
        source=LOCAL_WARNING_SERVICES[club.country][0],
    )


def _sample_frost_warning(club: locations.Club, now: datetime) -> dwd_warnings.Warning:
    start = now.replace(minute=0, second=0, microsecond=0)
    return dwd_warnings.Warning(
        kind="local",
        area=club.name,
        event="FROST",
        severity="Minor",
        headline="Amtliche WARNUNG vor FROST",
        description="Es tritt leichter Frost um -1 °C auf.",
        instruction="Hinweis auf: mögliche Frostschäden.",
        onset=start + timedelta(hours=6),
        expires=start + timedelta(hours=15),
        identifier=f"sample-frost-{club.id}",
        source=LOCAL_WARNING_SERVICES[club.country][0],
    )


_SAMPLE_FROST_ENGLISH = dwd_warnings.EnglishText(
    event="frost",
    headline="Official WARNING of FROST",
    description="Light frost around -1 °C.",
    instruction="Possible frost damage.",
    official=True,
)


_SAMPLE_LOCAL_ENGLISH = dwd_warnings.EnglishText(
    event="thunderstorms",
    headline="Thunderstorm warning",
    description="Thunderstorms with heavy rain and gusts around 70 km/h.",
    instruction="Stay off the water and seek shelter in a building.",
    official=True,
)


async def _english_texts(client: httpx.AsyncClient) -> dict[str, dwd_warnings.EnglishText]:
    """DWD's English warnings, cached like the warnings; empty when they cannot be loaded."""
    global _english
    if _english is not None and time.monotonic() - _english[0] < WARNINGS_CACHE_SECONDS:
        return _english[1]
    try:
        texts = await dwd_warnings.fetch_english_texts(client)
    except (httpx.HTTPError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as e:
        logging.getLogger(__name__).warning("DWD English warnings unavailable: %r", e)
        texts = {}
    _english = (time.monotonic(), texts)
    return texts


def _english_for(w: dwd_warnings.Warning, texts: dict[str, dwd_warnings.EnglishText]) -> dwd_warnings.EnglishText:
    return texts.get(w.identifier) or dwd_warnings.english_fallback(w)


async def _lake_area(client: httpx.AsyncClient, club: locations.Club) -> dwd_warnings.LakeArea | None:
    global _lake_areas
    if _lake_areas is None or time.monotonic() - _lake_areas[0] > LAKE_AREAS_CACHE_SECONDS:
        _lake_areas = (time.monotonic(), await dwd_warnings.fetch_lake_areas(client))
    p = club.launch_point
    return dwd_warnings.lake_area_for(p.lon, p.lat, _lake_areas[1])


async def _all_lake_warnings(client: httpx.AsyncClient) -> list[tuple[int, dwd_warnings.Warning]]:
    global _lake_warnings
    if _lake_warnings is None or time.monotonic() - _lake_warnings[0] > WARNINGS_CACHE_SECONDS:
        _lake_warnings = (time.monotonic(), await dwd_warnings.fetch_lake_warnings(client))
    return _lake_warnings[1]


def _local_service(club: locations.Club) -> dict:
    """Whose weather warnings count for the club's place, and whether the app checked them."""
    source, name, url = LOCAL_WARNING_SERVICES.get(club.country, (None, None, None))
    return {"source": source, "service": name, "url": url, "checked": club.country in CHECKED_COUNTRIES}


async def _local_warnings(
    client: httpx.AsyncClient, club: locations.Club
) -> tuple[list[dwd_warnings.Warning], dict[str, dwd_warnings.EnglishText]]:
    """The weather warnings for the club's place from its country's service, with
    English texts where that service sends them (DWD's are looked up later)."""
    global _swiss_alerts
    p = club.launch_point
    if club.country not in CHECKED_COUNTRIES:
        return [], {}
    if club.country == "at":
        return await geosphere_warnings.fetch(client, p.lon, p.lat)
    if club.country == "ch":
        if _swiss_alerts is None or time.monotonic() - _swiss_alerts[0] > WARNINGS_CACHE_SECONDS:
            _swiss_alerts = (time.monotonic(), await meteoalarm.fetch(client, _now()))
        found = meteoalarm.for_point(_swiss_alerts[1], p.lon, p.lat)
        return [a.warning for a in found], {a.warning.identifier: a.english for a in found if a.english}
    local = prepared.local_warnings.get(club.id)
    if local is None:
        local = await dwd_warnings.fetch_local_warnings(client, p.lon, p.lat)
    return local, {}


async def _warnings(client: httpx.AsyncClient, club: locations.Club, now: datetime) -> tuple[dict, list]:
    """The warnings block for the app and the warnings that count for the hourly light.

    If DWD (or GeoSphere) cannot be reached the block says so ("unavailable"), so
    the app never shows "no warning" without having checked. Outside Germany DWD
    has no local warnings: Austrian places get GeoSphere's, elsewhere only the
    lake warning (Lake Constance) is read and `local` says the place's own
    service was not checked.
    """
    cached = _warnings_cache.get(club.id)
    if cached and time.monotonic() - cached[0] < WARNINGS_CACHE_SECONDS:
        return cached[1]
    try:
        area = await _lake_area(client, club)
        lake = []
        if area is not None:
            lake = [w for cell, w in await _all_lake_warnings(client) if cell == area.warncell_id]
        local, own_english = await _local_warnings(client, club)
    except (httpx.HTTPError, ValueError, KeyError) as e:
        logging.getLogger(__name__).warning("Warnings unavailable for %s: %r", club.id, e)
        result = ({"status": "unavailable", "lakeArea": None, "items": [], "local": _local_service(club)}, [])
        _warnings_cache[club.id] = (time.monotonic() - WARNINGS_CACHE_SECONDS + 60, result)  # retry in a minute
        return result
    english = await _english_texts(client) if lake or any(w.source == "dwd" for w in local) else {}
    english = {**english, **own_english}
    items = [_warning_json(w, _english_for(w, english), club=club) for w in lake + local]
    if club.id in SAMPLE_WARNING_CLUBS and area is not None:
        sample = _sample_warning(area.name, now)
        lake.append(sample)
        items.insert(0, _warning_json(sample, _SAMPLE_ENGLISH, sample=True, club=club))
    elif club.id in SAMPLE_WARNING_CLUBS and club.country in CHECKED_COUNTRIES:
        # Without a DWD lake area (Austria, Switzerland): a made-up thunderstorm warning from the place's own service.
        sample = _sample_local_warning(club, now)
        local.append(sample)
        items.insert(0, _warning_json(sample, _SAMPLE_LOCAL_ENGLISH, sample=True, club=club))
    if club.id in SAMPLE_FROST_CLUBS and club.country in CHECKED_COUNTRIES:
        sample = _sample_frost_warning(club, now)
        local.append(sample)
        items.append(_warning_json(sample, _SAMPLE_FROST_ENGLISH, sample=True, club=club))
    current = [w for w in lake + local if w.expires is None or w.expires > now]
    block = {"status": "ok", "lakeArea": None if area is None else area.name, "items": items, "local": _local_service(club)}
    if area is not None:
        # Only some of DWD's lake areas have storm lights on the shore; the app explains them only there.
        block["shoreLights"] = dwd_warnings.has_shore_lights(area.warncell_id)
    result = (block, current)
    _warnings_cache[club.id] = (time.monotonic(), result)
    return result


def _water_station_json(
    station: water_stations.Station | None, lake: locations.Lake | None = None, club: locations.Club | None = None
) -> dict | None:
    """Where the water temperature comes from, for the detail view: name, place, distance from the launch point
    and, for GKD, the station's page. The lake's own GKD station takes its place from locations.json."""
    if station is None:
        return None
    name, lat, lon = station.name, station.lat, station.lon
    if lake is not None and station.network == "gkd" and station.id == lake.gkd_water_temperature_station:
        name = name or lake.gkd_station_name
        if lat is None and lake.gkd_station_point is not None:
            lat, lon = lake.gkd_station_point.lat, lake.gkd_station_point.lon
    if name is None:
        return None
    point = None if lat is None or lon is None else locations.Point(lat=lat, lon=lon)
    distance_m = None if point is None or club is None else round(locations._distance_m(club.launch_point, point))
    url = None
    if station.network == "gkd":
        url = gkd.PAGE_URL.format(kind=gkd.KINDS.get(station.kind, "lakes"), station=station.id).removesuffix("/table")
    return {
        "network": station.network,
        "name": name,
        "lat": lat,
        "lon": lon,
        "distanceKm": station.distance_km if station.distance_km is not None else (None if distance_m is None else round(distance_m / 1000, 1)),
        "distanceM": distance_m,
        "url": url,
    }


def _water_estimate_json(e: water_estimate.WaterEstimate | None) -> dict | None:
    if e is None:
        return None
    r = e.reading
    return {
        "celsius": e.celsius,
        "basis": "satellite",
        "reading": {
            "source": r.source,
            # "landsat-8" / "landsat-9" for Landsat, None for Copernicus LSWT.
            "platform": r.platform,
            "date": r.day.isoformat(),
            # The ten days an LSWT reading averages; None for Landsat.
            "from": None if r.first is None else r.first.isoformat(),
            "to": None if r.last is None else r.last.isoformat(),
            "celsius": r.celsius,
        },
    }


def _ice_json(e: ice.IceEstimate | None) -> dict:
    if e is None:
        return {"status": "unavailable", "light": None, "days": []}
    return {
        "status": e.status,
        "light": Light(e.light).name.lower(),
        "thicknessCm": e.thickness_cm,
        "waterTemperatureC": e.water_c,
        "basis": e.basis,
        "frostDegreeDays7": e.frost_degree_days_7,
        "satellite": None
        if e.satellite is None
        else {
            "date": e.satellite.day.isoformat(),
            "seenShare": round(e.satellite.seen_share, 2),
            "iceShare": round(e.satellite.ice_share, 2),
        },
        "days": [{"date": d.day.isoformat(), "status": d.status, "thicknessCm": d.thickness_cm} for d in e.days],
    }


async def _air_days(client: httpx.AsyncClient, lake: locations.Lake, today: date) -> list[ice.DayTemperature] | None:
    """The lake's daily mean air temperatures (92 days back, 7 ahead), loaded once a day; None when unavailable."""
    global _air_days_failed, _air_days_paused_until
    cached = prepared.ice_temps.get(lake.id)
    if cached and cached[0] == today:
        return cached[1]
    if time.monotonic() < _air_days_paused_until:
        return None
    try:
        daily = await open_meteo.fetch_daily_mean(client, lake.center.lat, lake.center.lon)
    except (httpx.HTTPError, ValueError, KeyError) as e:
        logging.getLogger(__name__).warning("Daily air temperatures unavailable for %s: %r", lake.id, e)
        _air_days_failed += 1
        if _air_days_failed >= 2:
            _air_days_paused_until = time.monotonic() + AIR_DAYS_PAUSE
            logging.getLogger(__name__).warning("Daily air temperatures paused for %d s", AIR_DAYS_PAUSE)
        return None
    _air_days_failed = 0
    temps = [ice.DayTemperature(d, t) for d, t in daily]
    prepared.ice_temps[lake.id] = (today, temps)
    return temps


async def _ice(
    client: httpx.AsyncClient, lake: locations.Lake, water_c: float | None, now: datetime, estimated_water_c: float | None = None
) -> ice.IceEstimate | None:
    """The ice estimate for the lake; None when the air temperatures cannot be loaded.

    Without a station, `estimated_water_c` (the satellite reading carried
    forward) restarts the model today, like a measurement, but the estimate
    stays marked "model".
    """
    today = now.astimezone(LOCAL).date()
    if ice.out_of_season(today):
        return ice.IceEstimate(ice.OPEN, None, water_c, "season", None, [])
    if lake.kind != "river" and water_c is not None and water_c > ice.WARM_WATER_C:
        return ice.IceEstimate(ice.OPEN, None, water_c, "measured", None, [])
    temps = await _air_days(client, lake, today)
    if temps is None:
        return None
    if lake.kind == "river":
        return ice.river(temps, today)
    if water_c is None and estimated_water_c is not None:
        estimate = ice.simulate(temps, today, lake.mean_depth_m, estimated_water_c)
        estimate = replace(estimate, basis="model")
    else:
        estimate = ice.simulate(temps, today, lake.mean_depth_m, water_c)
    return ice.with_satellite(estimate, prepared.satellite_ice.get(lake.id, []), today)


def _filled(picked: list[open_meteo.ForecastHour], auto: list[open_meteo.ForecastHour]) -> list[open_meteo.ForecastHour]:
    """The picked model's hours, with every value it does not give (past its reach,
    or a variable it lacks) taken from the automatic chain."""
    by_time = {h.time: h for h in picked}
    out = []
    for a in auto:
        p = by_time.get(a.time)
        if p is None:
            out.append(a)
            continue
        out.append(replace(a, **{f.name: getattr(p, f.name) for f in fields(a) if getattr(p, f.name) is not None}))
    return out


def offers_choices(club: locations.Club) -> bool:
    # Only the confirmed clubs, because each model costs extra Open-Meteo calls.
    return club.source is None


async def _water(
    client: httpx.AsyncClient, station: water_stations.Station, now: datetime
) -> tuple[gkd.WaterTemperature | None, list[gkd.WaterTemperature]]:
    """The station's newest reading and hourly history. GKD sometimes fails a
    request, so it is tried twice, then the last good reading stands in while
    it is younger than gkd.MAX_AGE."""
    for attempt in (1, 2):
        try:
            if station.network == "pegelonline":
                water, history = await pegelonline.fetch_recent(client, station.id, now)
            elif station.network == "bafu":
                water, history = await bafu.fetch_recent(client, station.id, now)
            else:
                water, history = await gkd.fetch_recent(client, station.id, now, station.kind)
        except (httpx.HTTPError, ValueError) as e:
            logging.getLogger(__name__).warning("%s failed for %s (try %d): %r", station.network, station.id, attempt, e)
            if attempt == 1:
                await asyncio.sleep(2)
            continue
        if water is not None:
            prepared.last_water[station.key] = (water, history)
            return water, history
        break  # the station has gone quiet; an older reading would be older still
    saved = prepared.last_water.get(station.key)
    if saved and now - saved[0].time <= gkd.MAX_AGE:
        return saved
    return None, []


@app.get("/clubs/{club_id}/forecast")
async def club_forecast(club_id: str) -> dict:
    return await _club_forecast(club_id, None)


@app.get("/clubs/{club_id}/models/{model_id}/forecast")
async def club_forecast_with_model(club_id: str, model_id: str) -> dict:
    """The forecast with a model the user picked (a hidden test in the app)."""
    club = _locations.clubs.get(club_id)
    picked = None if club is None else weather_models.choice(club.launch_point.lat, club.launch_point.lon, model_id)
    if club is None or picked is None or not offers_choices(club):
        raise HTTPException(status_code=404, detail="no such model for this club")
    return await _club_forecast(club_id, picked)


async def _club_forecast(club_id: str, picked: weather_models.Choice | None) -> dict:
    club = _locations.clubs.get(club_id)
    if club is None:
        raise HTTPException(status_code=404, detail="unknown club")
    now = _now()
    inputs = await _club_inputs(club, picked, now)
    return build_club_forecast(club, _locations.lakes[club.lake_id], inputs, picked, now)


@dataclass
class ClubInputs:
    """Everything a club's forecast is built from, as loaded (or prepared) for it.

    _club_inputs loads it; build_club_forecast turns it into the JSON without
    any network, so the building can be tested and reused on its own (code
    review finding 4).
    """

    weather: list
    outlook: list | None
    station: water_stations.Station | None
    water: gkd.WaterTemperature | None
    water_history: list
    warnings_block: dict
    warnings: list
    estimate: water_estimate.WaterEstimate | None
    water_model_c: float | None
    ice_estimate: ice.IceEstimate | None
    air_days: list | None
    gauge: river.Gauge | None
    readings: tuple | None
    level_lake: lake_level.LevelLake | None
    levels: tuple | None
    # The lake view's forecast points, for the water near the launch point (option C);
    # only when already loaded for the lake view, never fetched for the club alone.
    lake_weather: list | None = None


async def _club_inputs(club: locations.Club, picked: weather_models.Choice | None, now: datetime) -> ClubInputs:
    """Loads a club's inputs: from api.prepared or the short cache where there, else from the sources."""
    club_id = club.id
    lake = _locations.lakes[club.lake_id]
    station = water_stations.for_club(club, lake)
    async with httpx.AsyncClient() as client:
        cached = _cache.get(club_id)
        if cached and time.monotonic() - cached[0] < CACHE_SECONDS:
            weather, water, water_history, outlook = cached[1]
        else:
            weather = prepared.weather.pop(club_id, None)
            if weather is None:
                try:
                    weather = await open_meteo.fetch(client, club.launch_point.lat, club.launch_point.lon)
                except httpx.HTTPError as e:
                    logging.getLogger(__name__).warning("Open-Meteo unavailable for %s: %r", club_id, e)
                    raise HTTPException(status_code=503, detail="weather service unavailable, try again shortly")
            water, water_history = None, []
            if station:
                water, water_history = await _water(client, station, now)
            # Yesterday and the next 7 days for the charts; the forecast works without it.
            if club_id in prepared.outlook:
                outlook = prepared.outlook.pop(club_id)
            else:
                try:
                    outlook = await open_meteo.fetch_outlook(client, club.launch_point.lat, club.launch_point.lon)
                except httpx.HTTPError:
                    outlook = None
            _cache[club_id] = (time.monotonic(), (weather, water, water_history, outlook))
        if picked is not None:
            key = f"{club_id}@{picked.id}"
            cached = _cache.get(key)
            if cached and time.monotonic() - cached[0] < CACHE_SECONDS:
                weather = cached[1]
            else:
                other = prepared.weather.pop(key, None)
                if other is None:
                    try:
                        other = await open_meteo.fetch(client, club.launch_point.lat, club.launch_point.lon, models=picked.id)
                    except httpx.HTTPError:
                        raise HTTPException(status_code=503, detail="weather service unavailable, try again shortly")
                weather = _filled(other, weather)
                _cache[key] = (time.monotonic(), weather)
        warnings_block, warnings = await _warnings(client, club, now)
        estimate = None
        if water is None and prepared.satellite_water.get(lake.id):
            today = now.astimezone(LOCAL).date()
            temps = await _air_days(client, lake, today)
            estimate = water_estimate.estimate(prepared.satellite_water[lake.id], temps or [], today)
        # Neither a station nor a recent satellite reading: worked out from the air alone, all year.
        water_model_c = None
        if water is None and estimate is None and lake.kind == "lake":
            today = now.astimezone(LOCAL).date()
            water_model_c = water_estimate.from_air(await _air_days(client, lake, today) or [], today)
        ice_estimate = await _ice(client, lake, water.celsius if water else None, now, estimate.celsius if estimate else None)
        # For the water forecast; lakes only, since a river's water comes from upstream.
        air_days = await _air_days(client, lake, now.astimezone(LOCAL).date()) if lake.kind == "lake" else None
        gauge = river.gauge_for(club.id) if lake.kind == "river" else None
        readings = await _gauge_readings(client, gauge) if gauge else None
        # Lakes lowered on purpose (Forggensee in winter): the level from the lake's gauge.
        level_lake = lake_level.for_lake(lake.id) if lake.kind == "lake" else None
        levels = await _lake_levels(client, level_lake) if level_lake else None
    return ClubInputs(weather, outlook, station, water, water_history, warnings_block, warnings, estimate, water_model_c,
                      ice_estimate, air_days, gauge, readings, level_lake, levels, _loaded_lake_weather(lake.id))


def _loaded_lake_weather(lake_id: str) -> list | None:
    """The lake view's point forecasts where the publish job or the short cache has them."""
    if (primed := prepared.lake_weather.get(lake_id)) is not None:
        return primed
    cached = _lake_view_cache.get(lake_id)
    if cached and time.monotonic() - cached[0] < CACHE_SECONDS:
        return cached[1][0]
    return None


def _nearby(club: locations.Club, lake_weather: list | None, water_c: float | None, now: datetime) -> dict:
    """The water within 1 km of the launch point, per hour (lake_view.nearby_water); {} without a lake view."""
    rings = outlines.load(club.lake_id)
    if not lake_weather or not rings:
        return {}
    try:
        grid = lake_grid(club.lake_id, rings)
    except Exception:  # a broken outline must not stop the club's forecast
        return {}
    weather = [_from_now(w, now) for w in lake_weather]
    if SAMPLE_LAKE_WIND:
        weather = _sample_wind(weather)
    if len(weather) != len(grid.samples):
        return {}
    return lake_view.nearby_water(grid, weather, club.launch_point.lat, club.launch_point.lon, water_c)


def _with_nearby(hour: dict, n: lake_view.Nearby | None) -> dict:
    """Adds the water near the launch point to an hour: its values for the app's boat limits,
    and where it is worse than the launch point, a "nearby_water" reason that sets the light."""
    if n is None:
        return hour
    hour["nearby"] = {
        "light": n.light.name.lower(),
        "windMs": round(n.wind_ms, 1),
        "gustMs": round(n.gust_ms, 1),
        "waveM": round(n.wave_m, 2),
        "visM": None if n.vis_m is None else round(n.vis_m),
        "rainMm": None if n.rain_mm is None else round(n.rain_mm, 1),
        "other": n.other.name.lower(),
        "otherCause": n.other_cause,
    }
    own = Light[hour["light"].upper()]
    if n.light > own and n.cause:
        value = None if n.value is None else round(n.value, 2 if n.cause == "waves" else 1 if n.cause != "fog" else 0)
        hour["reasons"] = [{"condition": "nearby_water", "light": n.light.name.lower(), "topic": n.cause, "value": value}] + hour["reasons"]
        hour["light"] = n.light.name.lower()
    return hour


def build_club_forecast(
    club: locations.Club, lake: locations.Lake, inputs: ClubInputs, picked: weather_models.Choice | None, now: datetime
) -> dict:
    """A club's forecast JSON from its inputs; no network."""
    weather, outlook, station = inputs.weather, inputs.outlook, inputs.station
    water, water_history, warnings_block, warnings = inputs.water, inputs.water_history, inputs.warnings_block, inputs.warnings
    estimate, water_model_c, ice_estimate, air_days = inputs.estimate, inputs.water_model_c, inputs.ice_estimate, inputs.air_days
    gauge, readings, level_lake, levels = inputs.gauge, inputs.readings, inputs.level_lake, inputs.levels
    ice_by_day = {} if ice_estimate is None else {d.day: Light(ice.STATUS_LIGHT[d.status]) for d in ice_estimate.days}
    weather = _from_now(weather, now)
    if not weather:
        raise HTTPException(status_code=503, detail="forecast too old, try again shortly")
    rings = outlines.load(club.lake_id)
    river_now = None
    if gauge and readings:
        river_now = river.now_at(gauge, *readings, _section_width_m(lake, rings), lake.name, now)
    river_reason = river_now.light if river_now else None
    river_until = now + timedelta(hours=river.GAUGE_HOURS)
    level_now = lake_level.now_at(level_lake, levels, now) if level_lake and levels else None
    if level_now is not None and level_now.light:
        # A lake's level changes over days, so a lowered lake counts for the whole forecast.
        river_reason, river_until = level_now.light, now + timedelta(days=30)
    # The light follows the water as measured, else as estimated (satellite or
    # air), so two clubs with water below 15 °C get the same advice.
    water_c = water.celsius if water else estimate.celsius if estimate else water_model_c
    water_forecast = water_by_day = None
    if water_c is not None and air_days:
        water_forecast = water_estimate.forecast(water_c, air_days, now.astimezone(LOCAL).date())
        water_by_day = dict(water_forecast)
    hours = rowing_forecast(club, weather, rings, water_c, warnings, ice_by_day=ice_by_day, water_by_day=water_by_day,
                            river=river_reason, river_until=river_until)
    outlook_hours = (
        rowing_forecast(club, outlook, rings, water_c, warnings, ice_by_day=ice_by_day, water_by_day=water_by_day,
                        river=river_reason, river_until=river_until)
        if outlook
        else None
    )
    chain = weather_models.chain_for(club.launch_point.lat, club.launch_point.lon)
    # Option C: the light also counts the water within 1 km of the launch point.
    nearby = _nearby(club, inputs.lake_weather, water_c, now)
    return {
        "clubId": club.id,
        "lakeId": club.lake_id,
        "generatedAt": now.replace(microsecond=0).isoformat(),
        "waterTemperature": None
        if water is None
        else {
            "celsius": water.celsius,
            "measuredAt": water.time.astimezone(timezone.utc).isoformat(),
            # The station page's history, one value per hour, for the water temperature chart.
            "history": [{"time": _utc(r.time), "celsius": r.celsius} for r in water_history],
            "station": _water_station_json(station, lake, club),
        },
        # Without a station: the newest satellite reading carried forward to today (water_estimate.py).
        "waterEstimate": _water_estimate_json(estimate),
        "waterModelC": water_model_c,
        # Today's water carried on with the forecast air, one value per day (lakes only).
        "waterForecast": None if water_forecast is None else [{"date": d.isoformat(), "celsius": c} for d, c in water_forecast],
        "warnings": warnings_block,
        "ice": _ice_json(ice_estimate),
        # Rivers: level, trend and current now from the gauge, for the Current tile (river.py);
        # without a gauge an empty block, so the app still shows the tile instead of the ice tile.
        "river": river.to_json(river_now, gauge) if gauge else {"gauge": None, "now": None} if lake.kind == "river" else None,
        # Lakes lowered on purpose: the level from the lake's gauge (lake_level.py); while
        # the lake is lowered the app shows the Water level tile instead of the ice tile.
        "waterLevel": lake_level.to_json(level_now, level_lake) if level_lake else None,
        # A picked model gets its own weather credit; the hours past its reach stay DWD's.
        "attribution": (ATTRIBUTION if picked is None else [picked.credit, *ATTRIBUTION[1:]])
        + ([STATION_CREDIT[station.network]] if water is not None and station.network in STATION_CREDIT else [])
        + ([WARNING_CREDIT[club.country]] if club.country in WARNING_CREDIT else [])
        + ([] if estimate is None else [SATELLITE_WATER_CREDIT[estimate.reading.source]])
        + (["River level: WSV PEGELONLINE, DL-DE Zero 2.0"] if river_now is not None else [])
        + (["Lake level: " + lake_level.ATTRIBUTION] if level_now is not None else []),
        "forecastSource": weather_models.source_json(chain, len(hours))
        if picked is None
        else weather_models.picked_source_json(chain, picked, len(hours)),
        "modelChoices": weather_models.choices_json(club.launch_point.lat, club.launch_point.lon)
        if offers_choices(club)
        else [],
        "daylight": [
            {"date": d.day.isoformat(), "sunrise": _utc(d.sunrise), "sunset": _utc(d.sunset)}
            for d in sun_days(now, now + timedelta(hours=len(hours)), club.launch_point.lat, club.launch_point.lon)
        ],
        "hours": [_with_nearby(_hour_json(h), nearby.get(h.weather.time)) for h in hours],
        "outlook": None if outlook_hours is None else [_hour_json(h) for h in outlook_hours],
    }


def _sample_wind(weather: list[list]) -> list[list]:
    wind_from, speed, gusts = (float(v) for v in SAMPLE_LAKE_WIND.split(","))
    return [[replace(h, wind_from_deg=wind_from, wind_speed_ms=speed, wind_gust_ms=gusts) for h in w] for w in weather]


@app.get("/lakes/{lake_id}/view")
async def lake_view_forecast(lake_id: str) -> dict:
    """Conditions across the whole lake, hour by hour, for the app's lake view (see lake_view.py)."""
    lake = _locations.lakes.get(lake_id)
    rings = outlines.load(lake_id) if lake else None
    if lake is None or rings is None:
        raise HTTPException(status_code=404, detail="no outline for this lake")
    grid = lake_grid(lake_id, rings)
    clubs = _locations.clubs_on(lake_id)
    now = _now()
    async with httpx.AsyncClient() as client:
        cached = _lake_view_cache.get(lake_id)
        if cached and time.monotonic() - cached[0] < CACHE_SECONDS:
            weather, water = cached[1]
        elif (primed := prepared.lake_weather.pop(lake_id, None)) is not None:
            weather, water = primed, None
            if station := water_stations.for_lake(lake, clubs):
                water = (await _water(client, station, now))[0]
            _lake_view_cache[lake_id] = (time.monotonic(), (weather, water))
        else:
            try:
                weather = await open_meteo.fetch_many(
                    client, [(lat, lon) for lon, lat in grid.samples], hourly=open_meteo.LAKE_HOURLY
                )
            except httpx.HTTPError as e:
                body = e.response.text[:300] if isinstance(e, httpx.HTTPStatusError) else ""
                logging.getLogger(__name__).warning("Open-Meteo failed for lake view %s: %r %s", lake_id, e, body)
                raise HTTPException(status_code=503, detail="weather service unavailable, try again shortly")
            water = None
            if station := water_stations.for_lake(lake, clubs):
                water = (await _water(client, station, now))[0]
            _lake_view_cache[lake_id] = (time.monotonic(), (weather, water))
        # DWD lake warnings are per lake area, so any club on the lake finds them.
        warnings = (await _warnings(client, clubs[0], now))[1] if clubs else []
    weather = [_from_now(w, now) for w in weather]
    sample = bool(SAMPLE_LAKE_WIND)
    if sample:
        weather = _sample_wind(weather)
    hours = lake_view.lake_hours(grid, weather, warnings, water.celsius if water else None)
    return {
        "lakeId": lake.id,
        "name": lake.name,
        "kind": lake.kind,
        "section": _section_json(lake, full=True),
        "generatedAt": now.replace(microsecond=0).isoformat(),
        "sample": sample,
        "attribution": ATTRIBUTION,
        # The measured water the lights used; the app lowers its own wind limits
        # with it and draws the shore blue in cold water.
        "waterC": round(water.celsius, 1) if water else None,
        "grid": {
            "south": round(grid.south, 6),
            "west": round(grid.west, 6),
            "dLat": grid.d_lat,
            "dLon": grid.d_lon,
            "cols": grid.cols,
            "rows": grid.rows,
            "cellM": round(grid.cell_m),
            "cells": grid.cells,
            "cellPoint": grid.nearest,
            "cellZone": grid.zone_of,
        },
        "zones": grid.zones,
        "outline": [[[x, y] for x, y in ring] for ring in grid.outline],
        "points": [{"lat": round(lat, 5), "lon": round(lon, 5)} for lon, lat in grid.samples],
        "clubs": [{"id": c.id, "shortName": c.short_name, "launchPoint": _point(c.launch_point)} for c in clubs],
        "hours": [
            {
                "time": h.time.isoformat(),
                "lakeWide": {
                    "light": h.lake_wide_light.name.lower(),
                    "reasons": _reasons_json(h.lake_wide, h.warning_topic),
                },
                # One digit per water cell: 0 green, 1 amber, 2 red.
                "lights": "".join(str(int(light)) for light in h.lights),
                "wavesCm": [round(w * 100) for w in h.waves_m],
                # "other": the light from fog, thunderstorms, heavy rain and hail at the point,
                # 0 green to 2 red; "visM", "storm" (thunderstorm light), "rainMm" and "hail"
                # say which of them sets it, for the tapped spot's values.
                "wind": [
                    {
                        "speedMs": w.wind_speed_ms,
                        "gustMs": w.wind_gust_ms,
                        "fromDeg": w.wind_from_deg,
                        "other": int(other),
                        "visM": None if w.visibility_m is None else round(w.visibility_m),
                        "storm": int(_thunderstorm(w)),
                        "rainMm": None if w.precipitation_mm is None else round(w.precipitation_mm, 1),
                        "hail": w.weather_code in HAIL_CODES,
                    }
                    for w, other in zip(h.wind, h.point_other or [Light.GREEN] * len(h.wind))
                ],
                "zones": [
                    {"light": light.name.lower(), "maxWaveM": round(wave, 2)}
                    for light, wave in zip(h.zone_lights, h.zone_max_wave_m)
                ],
            }
            for h in hours
        ],
    }
