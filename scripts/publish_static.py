#!/usr/bin/env python3
"""Write the backend's answers as static files, for hosting on GitHub Pages.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/publish_static.py OUT_DIR [--clubs confirmed|all] [--state FILE]

Calls the same functions the FastAPI app serves (no web server or test client)
and writes each answer at its API path, without a file extension:
    OUT_DIR/lakes/index                 = GET /lakes/index (the lake list)
    OUT_DIR/countries/index             = GET /countries/index (countries with clubs)
    OUT_DIR/countries/<cc>/lakes        = GET /countries/<cc>/lakes (one country's waters and clubs)
    OUT_DIR/lakes/<id>/view             = GET /lakes/<id>/view
    OUT_DIR/clubs/<id>/forecast         = GET /clubs/<id>/forecast
    OUT_DIR/clubs/<id>/models/<m>/forecast  the same with another weather model,
                                        for the confirmed clubs (hidden model picker)
So the app reads the files with the same paths as from a live backend, and
moving to a real server later only changes where api.rowfrog.com points.
With the Copernicus account (CDSE_CLIENT_ID / CDSE_CLIENT_SECRET) it also
writes Sentinel-2 pictures of each lake and, in winter, the satellite ice map:
    OUT_DIR/lakes/<id>/satellite        dates, cloud, picture box, credit
    OUT_DIR/lakes/<id>/satellite-latest.jpg, satellite-clearest.jpg, ice.png
    OUT_DIR/lakes/<id>/satellite-<kind>-tiles/<row>-<col>.jpg   10 m tiles of lakes too big for one picture
    OUT_DIR/lakes/<id>/satellite-<kind>-overview.jpg            2500 px overview of the biggest ones
After each new ICON-D2 run (every 3 hours) it also writes the weather maps
from DWD's open model data (rowfrog.sources.icon_d2_maps), no Open-Meteo calls:
    OUT_DIR/maps/index, OUT_DIR/maps/<tile>/<value>

"confirmed" rebuilds the clubs people use (until the usage counter is set up,
the clubs in data/locations.json), "all" every club in the catalogs too.
Warnings, water temperatures and, for the clubs people use, DWD's rain
radar (the widget's radar line) are fresh in every file, but weather is
loaded only when the weather model
has a new run for it (WEATHER_HOURS), to stay within Open-Meteo's free
10,000 calls a day; between loads the --state file (kept by the workflow's
cache) holds the last forecast. A club whose forecast fails keeps its
previous file, which still shows when it was made.

Which clubs and lakes are "used" comes from the usage counter in front of
api.rowfrog.com (rowfrog.usage, when it is set up); without it the
confirmed clubs count as used and the rest follow the fixed schedule.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import multiprocessing
import os
import pickle
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
from concurrent.futures import ProcessPoolExecutor
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import httpx
from fastapi import HTTPException
from fastapi.encoders import jsonable_encoder

from rowfrog import api, ice, lake_view, locations, outlines, water_estimate, weather_models
from rowfrog.api import LOCAL
from rowfrog.sources import dwd_radar, dwd_warnings, lake_ice_satellite, lake_temperature_satellite, open_meteo, sentinel2

try:  # the usage counter (PR #15) may not be part of this checkout yet
    from rowfrog import usage
except ImportError:
    usage = None

# Points per Open-Meteo request. Loading forecasts in batches takes a few
# requests instead of one per point; single requests from GitHub's shared
# runners often timed out or were refused.
BATCH = 50
# Waits before retrying a failed batch, in seconds; Open-Meteo's limit is per minute.
RETRY_WAITS = (65, 120)
# Hours loaded per forecast: two days from now, the longest wait for the next load and the
# night after the two days (api.FETCH_HOURS).
FETCH_HOURS = api.FETCH_HOURS

# ICON-D2 runs every 3 hours (00, 03, ... UTC) and its forecast is ready
# about READY_AFTER later. Loading more often brings nothing new.
READY_AFTER = timedelta(hours=2, minutes=30)
# Model runs noted in the availability log (v1/status/model-runs): two weeks.
MODEL_RUNS_KEPT = 112
WEATHER_HOURS = {"used": 3, "other": 6, "other with usage": 12}
# Finding 10 of the code review (2026-11-04): anyone can request forecasts,
# so someone could mark hundreds of different clubs as used, which moves them
# all to 3-hourly loads and uses up Open-Meteo's free calls. When this is above
# 0, at most this many clubs (and lakes) newly count as used per day, the most
# loaded first; clubs used on earlier days are never held back.
# OFF (0) FOR NOW. Owner decision: switch it on before launch (e.g. 50).
NEW_USED_PER_DAY = 0
# The 8-day outlook for the conditions charts costs about 2.4 calls per club
# (14 variables plus a UV call), so it is loaded for used clubs only, after
# every model run (3 hours): about 19 calls a day per used club.
OUTLOOK_HOURS = 3
# Lakes nobody uses are loaded twice a day, at a different hour from the clubs
# (04:00 and 16:00 UTC), so no single run takes too many calls.
LAKE_OTHER_HOURS = 12
LAKE_OTHER_OFFSET = timedelta(hours=1, minutes=30)

# The satellite ice map comes once a day from an afternoon pass; it is looked
# for in the morning and the evening (UTC).
ICE_MAP_LOOKS = (6, 18)

# Satellite lake temperatures (Copernicus LSWT, Landsat) are looked for once a day, from this hour (UTC).
WATER_SATELLITE_HOUR = 6

# How often a lake is looked at for new Sentinel-2 pictures, and how many lakes one run looks at.
PICTURE_REFRESH = {"used": timedelta(days=1), "other": timedelta(days=5)}
# Bumped when the search changes, so every lake is looked at again on the next run.
PICTURE_SEARCH_VERSION = 4
# Lakes looked at with versions before this one get the long first search.
PICTURE_FIRST_SEARCH_BEFORE = 3
PICTURES_PER_RUN = 40
# Requests for sharp tiles per run (Bodensee takes 40 a picture), so the first
# run after they came, or a run with many new passes, doesn't run too long.
# Pictures left without tiles get them in the next runs.
SHARP_TILES_PER_RUN = 100
SHARP_RETRY = timedelta(hours=3)

# Each club's DWD warn cell (its municipality) is looked up once and again
# after this many days; then a few queries read the local warnings of every
# club, instead of one query per club and run.
WARN_CELL_DAYS = 90
# Cell lookups at the same time (only the first run looks up every club).
WARN_CELL_LOOKUPS = 8


# Open-Meteo's newest ICON-D2 run, asked at the start of each run (meta.json).
# With it a run loads weather only once the new model run is really there,
# however late it comes; without it (the question failed) READY_AFTER is assumed.
MODEL_RUN: open_meteo.ModelRun | None = None


def last_ready(now: datetime, every_hours: int, offset: timedelta = timedelta()) -> datetime:
    """When the newest forecast run (every `every_hours` from 00 UTC) became ready."""
    delay, latest = READY_AFTER, now
    if MODEL_RUN and MODEL_RUN.available <= now:
        # Nothing newer than Open-Meteo's newest run counts, and its delay stands for the older runs too.
        delay, latest = max(MODEL_RUN.available - MODEL_RUN.started, timedelta()), MODEL_RUN.available
    base = latest - delay - offset
    run = base.replace(hour=base.hour - base.hour % every_hours, minute=0, second=0, microsecond=0)
    return run + delay + offset


def check_model_run(state: "State", now: datetime) -> None:
    """Asks Open-Meteo for its newest ICON-D2 run and notes when each run came,
    so the timer can later be set to when the runs really arrive."""
    global MODEL_RUN

    async def ask() -> open_meteo.ModelRun:
        async with httpx.AsyncClient() as client:
            return await open_meteo.newest_run(client)

    try:
        MODEL_RUN = asyncio.run(ask())
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as e:
        MODEL_RUN = None
        print(f"  newest model run unknown ({e!r}); assuming each is ready {READY_AFTER} after it starts")
        return
    run = MODEL_RUN
    print(f"  ICON-D2 run {run.started:%d %b %H:%M}Z on Open-Meteo since {run.available:%H:%M}Z "
          f"({(run.available - run.started).total_seconds() / 3600:.2f} h after it started), asked {now:%H:%M}Z")
    if not state.model_runs or state.model_runs[-1]["started"] != run.started.isoformat():
        state.model_runs.append({"started": run.started.isoformat(), "available": run.available.isoformat(),
                                 "seen": now.replace(microsecond=0).isoformat()})
        del state.model_runs[:-MODEL_RUNS_KEPT]


def due(loaded: datetime | None, now: datetime, every_hours: int, offset: timedelta = timedelta()) -> bool:
    return loaded is None or loaded < last_ready(now, every_hours, offset)


def ice_map_due(checked: datetime | None, now: datetime) -> bool:
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    looks = [midnight + timedelta(days=d, hours=h) for d in (-1, 0) for h in ICE_MAP_LOOKS]
    return checked is None or checked < max(t for t in looks if t <= now)


class State:
    """What one run leaves for the next: the last forecasts, satellite looks
    and water temperatures."""

    def __init__(self, path: Path | None):
        self.path = path
        self.clubs: dict[str, tuple[datetime, list]] = {}
        self.lakes: dict[str, tuple[datetime, int, list]] = {}  # loaded, points, weather per point
        self.ice_map: tuple[datetime | None, dict[str, list]] = (None, {})
        self.outlooks: dict[str, tuple[datetime, list]] = {}
        self.models: dict[str, tuple[datetime, list]] = {}  # "<club>@<model>" -> loaded, weather
        # Satellite lake temperature: day looked, LSWT files read (name -> readings per lake), readings per lake.
        self.water_satellite: tuple[date | None, dict, dict[str, list]] = (None, {}, {})
        self.warn_cells: dict[str, tuple[datetime, int | None]] = {}  # club -> looked up, DWD warn cell (None outside Germany)
        # The ICON-D2 run the weather maps were last made from.
        self.maps_run: datetime | None = None
        # When each ICON-D2 run started, came to Open-Meteo and was first seen by a run.
        self.model_runs: list[dict[str, str]] = []
        # Per club, the model run its saved forecast came from ({"started", "available"}).
        self.club_runs: dict[str, dict[str, str]] = {}
        if path and path.exists():
            try:
                saved = pickle.loads(path.read_bytes())
                self.clubs, self.lakes, self.ice_map = saved["clubs"], saved["lakes"], saved["ice_map"]
                self.outlooks = saved.get("outlooks", {})
                self.models = saved.get("models", {})
                self.water_satellite = saved.get("water_satellite", (None, {}, {}))
                self.warn_cells = saved.get("warn_cells", {})
                self.maps_run = saved.get("maps_run")
                self.model_runs = saved.get("model_runs", [])
                self.club_runs = saved.get("club_runs", {})
                api.prepared.last_water.update(saved.get("water", {}))
                api.prepared.last_levels.update(saved.get("levels", {}))
                api.prepared.ice_temps.update(saved["ice_temps"])
            except Exception as e:  # an old or broken state only means loading everything again
                print(f"  state not readable, starting afresh: {e!r}")

    def save(self) -> None:
        if not self.path:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        body = {
            "clubs": self.clubs,
            "lakes": self.lakes,
            "ice_map": self.ice_map,
            "ice_temps": api.prepared.ice_temps,
            "outlooks": self.outlooks,
            "models": self.models,
            "water_satellite": self.water_satellite,
            "water": api.prepared.last_water,
            "levels": api.prepared.last_levels,
            "warn_cells": self.warn_cells,
            "maps_run": self.maps_run,
            "model_runs": self.model_runs,
            "club_runs": self.club_runs,
        }
        self.path.write_bytes(pickle.dumps(body))


async def _batched(points: list[tuple[float, float]], hourly: list[str]) -> tuple[list[list | None], list[str]]:
    """Forecasts for `points` in batches of BATCH; None where a batch failed."""
    out: list[list | None] = []
    problems = []
    async with httpx.AsyncClient() as client:
        for start in range(0, len(points), BATCH):
            batch = points[start : start + BATCH]
            forecasts = None
            for attempt, wait in enumerate((0, *RETRY_WAITS)):
                await asyncio.sleep(wait)
                try:
                    forecasts = await open_meteo.fetch_many(client, batch, FETCH_HOURS, hourly)
                    break
                except (httpx.HTTPError, ValueError, KeyError) as e:
                    detail = e.response.text[:200] if isinstance(e, httpx.HTTPStatusError) else ""
                    problems.append(f"batch {start // BATCH + 1} attempt {attempt + 1}: {e!r} {detail}")
            out += forecasts if forecasts else [None] * len(batch)
    return out, problems


def club_weather(state: State, clubs: list[locations.Club], used: set[str], with_usage: bool, now: datetime) -> None:
    """Loads the forecasts that are due and hands every club's last forecast to the API."""
    other = WEATHER_HOURS["other with usage" if with_usage else "other"]
    stale = [
        c for c in clubs if due(state.clubs.get(c.id, (None,))[0], now, WEATHER_HOURS["used"] if c.id in used else other)
    ]
    if stale:
        points = [(c.launch_point.lat, c.launch_point.lon) for c in stale]
        forecasts, problems = asyncio.run(_batched(points, open_meteo.HOURLY))
        for line in problems:
            print("  weather", line)
        for club, weather in zip(stale, forecasts):
            if weather is not None:
                state.clubs[club.id] = (now, weather)
                # Which model run this is, for the app's "Forecast from" line (unknown when Open-Meteo was not asked).
                if MODEL_RUN and MODEL_RUN.available <= now:
                    state.club_runs[club.id] = {"started": MODEL_RUN.started.isoformat(),
                                                "available": MODEL_RUN.available.isoformat()}
                else:
                    state.club_runs.pop(club.id, None)
    print(f"  weather loaded for {len(stale)} of {len(clubs)} clubs")
    for club in clubs:
        if club.id in state.clubs:
            api.prepared.weather[club.id] = state.clubs[club.id][1]


def local_warnings(state: State, clubs: list[locations.Club], now: datetime) -> None:
    """Reads the local DWD warnings of all `clubs` in a few queries and hands them to the API.

    A club whose cell could not be looked up, or every club when the warnings
    query fails, asks DWD itself as before.
    """

    # DWD's warn cells cover Germany only; the API skips local warnings elsewhere.
    clubs = [c for c in clubs if c.country == "de"]

    async def load() -> tuple[int, dict[int, list] | None]:
        due_ = [
            c for c in clubs
            if c.id not in state.warn_cells or now - state.warn_cells[c.id][0] > timedelta(days=WARN_CELL_DAYS)
        ]
        gate = asyncio.Semaphore(WARN_CELL_LOOKUPS)
        async with httpx.AsyncClient() as client:

            async def look_up(club: locations.Club) -> None:
                async with gate:
                    try:
                        cell = await dwd_warnings.fetch_warn_cell(client, club.launch_point.lon, club.launch_point.lat)
                    except (httpx.HTTPError, ValueError, KeyError):
                        return
                    state.warn_cells[club.id] = (now, cell)

            await asyncio.gather(*(look_up(c) for c in due_))
            cells = {state.warn_cells[c.id][1] for c in clubs if c.id in state.warn_cells} - {None}
            try:
                return len(due_), await dwd_warnings.fetch_local_warnings_for_cells(client, cells)
            except (httpx.HTTPError, ValueError, KeyError) as e:
                print(f"  local warnings for all clubs failed, each club asks DWD itself: {e!r}")
                return len(due_), None

    looked, by_cell = asyncio.run(load())
    if by_cell is None:
        return
    primed = 0
    for club in clubs:
        if club.id in state.warn_cells:
            cell = state.warn_cells[club.id][1]
            api.prepared.local_warnings[club.id] = [] if cell is None else by_cell.get(cell, [])
            primed += 1
    queries = -(-len(by_cell) // dwd_warnings.CELLS_PER_QUERY)
    print(f"  local warnings for {primed} of {len(clubs)} clubs in {queries} DWD queries ({looked} warn cells looked up)")


def refresh_block(used: bool) -> dict:
    """How often this club's file and weather are renewed, for the app's tip on
    clubs nobody opened lately: their file is rewritten only in the all-clubs
    runs (every 6 hours) and their weather loaded every 12 hours. Opening the
    club counts it as used, so the next half-hourly run takes it up."""
    if used:
        return {"used": True, "fileEveryHours": 0.5, "weatherEveryHours": WEATHER_HOURS["used"]}
    return {"used": False, "fileEveryHours": 6, "weatherEveryHours": WEATHER_HOURS["other with usage"]}


def club_outlooks(state: State, clubs: list[locations.Club], used: set[str], now: datetime) -> None:
    """Loads the 8-day outlooks that are due for used clubs and hands them to the API;
    other clubs get none, and the app charts their next 48 hours instead."""

    async def load(stale: list[locations.Club]) -> None:
        async with httpx.AsyncClient() as client:
            for club in stale:
                try:
                    hours = await open_meteo.fetch_outlook(client, club.launch_point.lat, club.launch_point.lon)
                except (httpx.HTTPError, ValueError, KeyError) as e:
                    print(f"  outlook {club.id}: {e!r}")
                    continue
                state.outlooks[club.id] = (now, hours)

    stale = [c for c in clubs if c.id in used and due(state.outlooks.get(c.id, (None,))[0], now, OUTLOOK_HOURS)]
    asyncio.run(load(stale))
    print(f"  outlook loaded for {len(stale)} clubs")
    for club in clubs:
        saved = state.outlooks.get(club.id) if club.id in used else None
        api.prepared.outlook[club.id] = saved[1] if saved else None


def model_weather(state: State, clubs: list[locations.Club], now: datetime) -> list[tuple[locations.Club, str]]:
    """The other weather models the confirmed clubs offer (the app's hidden model
    picker), loaded every 3 hours with one request per model. Returns the
    (club, model) pairs that have a forecast."""
    confirmed = [c for c in clubs if api.offers_choices(c)]
    by_model: dict[str, list[locations.Club]] = {}
    for club in confirmed:
        for choice in weather_models.choices_for(club.launch_point.lat, club.launch_point.lon):
            by_model.setdefault(choice.id, []).append(club)

    async def load(model: str, stale: list[locations.Club]) -> list[list] | None:
        points = [(c.launch_point.lat, c.launch_point.lon) for c in stale]
        async with httpx.AsyncClient() as client:
            try:
                return await open_meteo.fetch_many(client, points, FETCH_HOURS, models=model)
            except (httpx.HTTPError, ValueError, KeyError) as e:
                print(f"  model {model}: {e!r}")
                return None

    pairs = []
    for model, model_clubs in by_model.items():
        stale = [c for c in model_clubs if due(state.models.get(f"{c.id}@{model}", (None,))[0], now, WEATHER_HOURS["used"])]
        if stale:
            for club, weather in zip(stale, asyncio.run(load(model, stale)) or []):
                state.models[f"{club.id}@{model}"] = (now, weather)
        for club in model_clubs:
            key = f"{club.id}@{model}"
            if key in state.models:
                api.prepared.weather[key] = state.models[key][1]
                pairs.append((club, model))
    return pairs


def lake_weather(state: State, lake_ids: list[str], used: set[str], now: datetime) -> list[str]:
    """The same for the lake views; returns the lakes that have a forecast."""
    stale = []
    for lake_id in lake_ids:
        samples = lake_view.USED_SAMPLES if lake_id in used else lake_view.MAX_SAMPLES
        if samples != lake_view.MAX_SAMPLES:
            api.prepared.lake_samples[lake_id] = samples
        loaded, points, _ = state.lakes.get(lake_id, (None, 0, None))
        try:
            grid = api.lake_grid(lake_id, outlines.load(lake_id))
        except Exception as e:  # one broken outline must not stop every other lake
            print(f"  lake grid {lake_id}: {e!r}")
            continue
        hours, offset = (WEATHER_HOURS["used"], timedelta()) if lake_id in used else (LAKE_OTHER_HOURS, LAKE_OTHER_OFFSET)
        if points != len(grid.samples) or due(loaded, now, hours, offset):
            stale.append((lake_id, grid))
    owners, points = [], []
    for lake_id, grid in stale:
        for lon, lat in grid.samples:
            owners.append(lake_id)
            points.append((lat, lon))
    if points:
        forecasts, problems = asyncio.run(_batched(points, open_meteo.LAKE_HOURLY))
        for line in problems:
            print("  lake weather", line)
        per_lake: dict[str, list] = {}
        for lake_id, weather in zip(owners, forecasts):
            per_lake.setdefault(lake_id, []).append(weather)
        for lake_id, weathers in per_lake.items():
            if all(w is not None for w in weathers):
                state.lakes[lake_id] = (now, len(weathers), weathers)
    print(f"  weather loaded for {len(stale)} of {len(lake_ids)} lakes ({len(points)} points)")
    ready = []
    for lake_id in lake_ids:
        if lake_id in state.lakes:
            api.prepared.lake_weather[lake_id] = state.lakes[lake_id][2]
            ready.append(lake_id)
    return ready


def satellite_ice(state: State, lake_ids: list[str], now: datetime) -> None:
    """Looks at the satellite ice map twice a day in the ice season and hands the passes to the API."""
    today = now.astimezone(LOCAL).date()
    if ice.out_of_season(today):
        state.ice_map = (None, {})
        return
    checked, passes = state.ice_map
    if lake_ice_satellite.configured() and ice_map_due(checked, now):
        lakes = locations.load().lakes
        shores = {}
        for lake_id in lake_ids:
            lake = lakes.get(lake_id)
            rings = outlines.load(lake_id) if lake and lake.kind == "lake" else None
            if rings:
                shores[lake_id] = rings[0]
        passes = lake_ice_satellite.fetch(shores, today)
        state.ice_map = (now, passes)
        for lake_id, found in sorted(passes.items()):
            last = found[-1]
            print(f"  satellite ice {lake_id}: {last.day} seen {last.seen_share:.0%} ice {last.ice_share:.0%}")
    api.prepared.satellite_ice.clear()
    api.prepared.satellite_ice.update(passes)


def satellite_water(state: State, lake_ids: list[str], now: datetime) -> None:
    """Looks once a day for satellite lake temperatures of the lakes without a GKD station and hands them to the API."""
    today = now.astimezone(LOCAL).date()
    looked, files, readings = state.water_satellite
    if looked != today and now.hour >= WATER_SATELLITE_HOUR:
        lakes = locations.load().lakes
        shores = {}
        for lake_id in lake_ids:
            lake = lakes.get(lake_id)
            rings = outlines.load(lake_id) if lake and lake.kind == "lake" and not lake.gkd_water_temperature_station else None
            if rings:
                shores[lake_id] = rings[0]
        # Landsat scenes stay readable, so after the first look only the last days are searched.
        days = 4 if readings else lake_temperature_satellite.LANDSAT_DAYS
        found = lake_temperature_satellite.fetch(shores, today, files, days)
        readings = lake_temperature_satellite.merge(readings, found, today, water_estimate.MAX_AGE_DAYS)
        # The two newest LSWT files are all that is used.
        files = {name: files[name] for name in sorted(files)[-2:]}
        state.water_satellite = (today, files, readings)
        print(f"  satellite water temperature: {len(readings)} of {len(shores)} lakes seen")
    api.prepared.satellite_water.clear()
    api.prepared.satellite_water.update(readings)


def _read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    except ValueError:
        return {}


def publish_ice_map(out: Path, lake_ids: list[str], today: date) -> None:
    """The newest usable satellite ice pass of each lake, as a picture over the lake (winter only)."""
    for lake_id in lake_ids:
        meta_path = out / "lakes" / lake_id / "satellite"
        meta = _read_json(meta_path)
        usable = [
            p
            for p in api.prepared.satellite_ice.get(lake_id, [])
            if p.seen_share >= ice.SATELLITE_SEEN_SHARE and p.bbox and (today - p.day).days <= ice.SATELLITE_DAYS
        ]
        if not usable:
            if meta.pop("ice", None) is not None:
                write(meta_path, meta)
            continue
        newest = usable[-1]
        if (meta.get("ice") or {}).get("date") == newest.day.isoformat():
            continue
        image = lake_ice_satellite.png(newest)
        if image is None:
            continue
        png_path = out / "lakes" / lake_id / "ice.png"
        png_path.parent.mkdir(parents=True, exist_ok=True)
        png_path.write_bytes(image)
        meta["ice"] = {
            "date": newest.day.isoformat(),
            "seenShare": round(newest.seen_share, 2),
            "iceShare": round(newest.ice_share, 2),
            "bbox": [round(v, 5) for v in newest.bbox],
            "image": "ice.png",
            "attribution": "Copernicus Land Monitoring Service, Lake Ice Extent",
        }
        write(meta_path, meta)


def publish_pictures(
    out: Path, lake_ids: list[str], used: set[str], now: datetime, places: dict | None = None, areas: dict | None = None
) -> None:
    """Looks for newer Sentinel-2 pictures of the lakes whose last look is old enough.

    `places` are pictures without a lake outline (see club_places), by id with their ring.
    `areas` are the used clubs' squares by lake (see club_areas), for the cloud around each club.

    Two per lake: the latest pass, whatever the cloud, and the latest clear
    one. Looks come at most 5 days apart and cover 30 days, so the clear one
    kept from an earlier look is still the newest clear pass there is. A lake looked at for the first time is
    searched over a whole year, so every lake has a picture.
    """
    client = sentinel2.client()
    if client is None:
        return
    today = now.date()
    looked = 0
    try:
        for lake_id in sorted(lake_ids, key=lambda i: (i not in used, i)):
            rings = (places or {}).get(lake_id) or outlines.load(lake_id)
            meta_path = out / "lakes" / lake_id / "satellite"
            old = _read_json(meta_path)
            version = old.get("searchVersion", 0)
            first = version < PICTURE_FIRST_SEARCH_BEFORE
            checked = None if version != PICTURE_SEARCH_VERSION or "checkedAt" not in old else datetime.fromisoformat(old["checkedAt"])
            refresh = PICTURE_REFRESH["used" if lake_id in used else "other"]
            sharp_ok = lake_id in used
            if sharp_ok and rings and checked and now - checked >= SHARP_RETRY and _lacks_sharp(old, rings[0]):
                checked = None  # look again until every picture has its tiles
            if not rings or (checked and now - checked < refresh) or looked >= PICTURES_PER_RUN:
                continue
            looked += 1
            days = sentinel2.FIRST_SEARCH_DAYS if first else sentinel2.SEARCH_DAYS
            try:
                latest, mostly_clear, clearest = sentinel2.choose(
                    sentinel2.cloud_by_day(client, rings[0], today - timedelta(days=days), today)
                )
                body = _picture_meta(client, out / "lakes" / lake_id, rings[0], old, latest, clearest, mostly_clear, sharp_ok)
                if body.get("latest"):
                    _club_cloud(client, body["latest"], (areas or {}).get(lake_id, {}), old.get("latest"))
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401:  # the sign-in lasts minutes; renew it once
                    client.close()
                    client = sentinel2.client()
                    if client is None:
                        return
                print(f"  picture {lake_id}: HTTP {e.response.status_code} {e.response.text[:200]}")
                continue
            except (httpx.HTTPError, KeyError, ValueError) as e:
                print(f"  picture {lake_id}: {e!r}")
                continue
            body.update(checkedAt=now.replace(microsecond=0).isoformat(), searchVersion=PICTURE_SEARCH_VERSION)
            write(meta_path, body)
            shown = {k: (body.get(k) or {}).get("date") for k in ("latest", "clearest")}
            print(f"  picture {lake_id}: latest {shown['latest']}, clearest {shown['clearest']}")
    finally:
        if client is not None:
            client.close()


# Half the side of the square around a club's launch point whose cloud counts.
CLUB_PLACE_M = 500
# Half the side of the square around a club on a lake whose cloud decides whether its
# satellite card opens on the clearest picture (owner 2026-11-12, docs/decisions/0024).
CLUB_AREA_M = 1000


def square(lat: float, lon: float, half_m: float) -> list[tuple[float, float]]:
    """The ring of the square of `2 * half_m` around a point."""
    dlat = half_m / 110_540
    dlon = half_m / (111_320 * math.cos(math.radians(lat)))
    return [(lon - dlon, lat - dlat), (lon + dlon, lat - dlat), (lon + dlon, lat + dlat), (lon - dlon, lat + dlat)]


def club_places(clubs) -> dict[str, list[list[tuple[float, float]]]]:
    """Picture places of clubs on water without an outline, "club-<id>".

    A club on a river without a section (or on an unknown water) gets a picture of at
    least 4 x 3 km around its launch point (sentinel2.MIN_WIDTH_M); clouds are
    counted over the square kilometre around it.
    """
    places = {}
    for club in clubs:
        if outlines.load(club.lake_id):
            continue
        places[f"club-{club.id}"] = [square(club.launch_point.lat, club.launch_point.lon, CLUB_PLACE_M)]
    return places


def club_areas(clubs) -> dict[str, dict[str, list[tuple[float, float]]]]:
    """By lake, the square of about 2 x 2 km around each used club's launch point, by club id."""
    areas: dict[str, dict[str, list[tuple[float, float]]]] = {}
    for club in clubs:
        point = club.launch_point
        areas.setdefault(club.lake_id, {})[club.id] = square(point.lat, point.lon, CLUB_AREA_M)
    return areas


def _club_cloud(client, entry: dict, areas: dict, old_entry: dict | None) -> None:
    """Adds to a latest picture the share under cloud around each club on the lake ("clubCloud").

    Kept from `old_entry` for the same pass; only clubs not measured yet cost a request.
    The apps open the clearest picture when it reaches 0.9 there (docs/decisions/0024).
    """
    if not areas:
        return
    kept = (old_entry or {}).get("clubCloud", {}) if (old_entry or {}).get("date") == entry["date"] else {}
    found = {k: v for k, v in kept.items() if k in areas}
    for club_id, ring in sorted(areas.items()):
        if club_id in found:
            continue
        share = sentinel2.cloud_on(client, ring, date.fromisoformat(entry["date"]))
        if share is not None:
            found[club_id] = round(share, 2)
    if found:
        entry["clubCloud"] = found


def river_places(lakes: dict, lake_ids: list[str]) -> dict[str, list[list[tuple[float, float]]]]:
    """Picture places of the river sections: the box of about 10 km around
    their clubs (builder's pictureBox), not the whole stretch."""
    places = {}
    for lake_id in lake_ids:
        lake = lakes.get(lake_id)
        if lake is not None and lake.section is not None:
            w, s, e, n = lake.section.picture_box
            places[lake_id] = [[(w, s), (e, s), (e, n), (w, n)]]
    return places


def _lacks_sharp(old: dict, ring) -> bool:
    """Whether a picture shown for a lake that gets sharp tiles has none yet."""
    if not sentinel2.sharp_size(sentinel2.frame(ring)[0]):
        return False
    return any(e and "tiles" not in e for e in (old.get(k) for k in ("latest", "clearest", "mostlyClear")))


def _picture_meta(client, folder: Path, ring, old: dict, latest, clearest, mostly_clear=None, sharp_ok: bool = True) -> dict:
    """The satellite file's picture part, rendering the pictures that are new.

    A third, "mostly clear" picture is added only when it is newer than the
    clearest and not the latest itself, so it shows something the other two don't.
    Lakes too big for 10 m in one picture also get each picture at 10 m in
    tiles, and the biggest an overview, for the full-screen view ("sharp"),
    while someone uses them (`sharp_ok`): for all 19 they would take about
    44 % of the free Copernicus processing units (owner's pick 2026-10-26).
    """
    bbox, width, height = sentinel2.frame(ring)
    sharp = sentinel2.sharp_size(bbox) if sharp_ok else None
    body = {k: v for k, v in old.items() if k in ("ice",)}
    body.update(bbox=[round(v, 5) for v in bbox], width=width, height=height)
    if sharp:
        grid = sentinel2.tiles(bbox, *sharp)
        body["sharp"] = {
            "width": sharp[0],
            "height": sharp[1],
            "tile": sentinel2.TILE_PIXELS,
            "rows": grid[-1][0] + 1,
            "columns": grid[-1][1] + 1,
        }
    # The tiles follow from the frame, so gaining or losing them keeps the pictures.
    old_frame = old.get("bbox") == body["bbox"] and old.get("width") == width
    for kind, found in (("latest", latest), ("clearest", clearest)):
        before = old.get(kind) if old_frame else None
        if found is None:  # nothing new: keep showing the last one
            if before:
                body[kind] = before if sharp else {k: v for k, v in before.items() if k not in ("tiles", "overview")}
            continue
        entry = {"date": found.day.isoformat(), "lakeCloud": round(found.lake_cloud, 2), "image": f"satellite-{kind}.jpg"}
        path = folder / entry["image"]
        folder.mkdir(parents=True, exist_ok=True)
        if before and before.get("date") == entry["date"] and path.exists():
            pass  # already there
        elif kind == "clearest" and latest is not None and found.day == latest.day:
            path.write_bytes((folder / "satellite-latest.jpg").read_bytes())  # the same pass
        else:
            path.write_bytes(sentinel2.jpeg(client, bbox, width, height, found.day))
        if sharp:
            same = body["latest"] if kind == "clearest" and latest is not None and found.day == latest.day else None
            entry.update(_sharp(client, folder, kind, bbox, sharp, found.day, before, same))
        body[kind] = entry
    clear_day = (body.get("clearest") or {}).get("date", "")
    if mostly_clear and latest and mostly_clear.day != latest.day and mostly_clear.day.isoformat() > clear_day:
        before = old.get("mostlyClear") if old_frame else None
        entry = {
            "date": mostly_clear.day.isoformat(),
            "lakeCloud": round(mostly_clear.lake_cloud, 2),
            "image": "satellite-mostly-clear.jpg",
        }
        path = folder / entry["image"]
        if not (before and before.get("date") == entry["date"] and path.exists()):
            path.write_bytes(sentinel2.jpeg(client, bbox, width, height, mostly_clear.day))
        if sharp:
            entry.update(_sharp(client, folder, "mostly-clear", bbox, sharp, mostly_clear.day, before))
        body["mostlyClear"] = entry
    shown = (body.get("latest"), body.get("mostlyClear"), body.get("clearest"))
    years = sorted({e["date"][:4] for e in shown if e})
    if years:
        body["attribution"] = f"Contains modified Copernicus Sentinel data {', '.join(years)}"
    (folder / "satellite.jpg").unlink(missing_ok=True)  # the single picture of the first version
    # Sharp files of pictures no longer shown, or of a lake that no longer needs them.
    kept = {e.get(k) for e in shown if e for k in ("tiles", "overview")}
    for kind in ("latest", "clearest", "mostly-clear"):
        if f"satellite-{kind}-tiles" not in kept and (folder / f"satellite-{kind}-tiles").exists():
            shutil.rmtree(folder / f"satellite-{kind}-tiles")
        if f"satellite-{kind}-overview.jpg" not in kept:
            (folder / f"satellite-{kind}-overview.jpg").unlink(missing_ok=True)
    return body


sharp_tiles_left = SHARP_TILES_PER_RUN


def _sharp(client, folder: Path, kind: str, bbox, size, day, before: dict | None, same: dict | None = None) -> dict:
    """Renders one picture at 10 m in tiles (and an overview for the biggest lakes) unless it is already there.

    `same` is the entry of another picture of the same pass, whose files are copied.
    Tiles are written to a fresh folder that replaces the old one once complete,
    so a failed run leaves the old tiles beside the old satellite file.
    """
    global sharp_tiles_left
    tiles_dir = f"satellite-{kind}-tiles"
    grid = sentinel2.tiles(bbox, *size)
    overview = sentinel2.overview_size(*size)
    fields = {"tiles": tiles_dir}
    if overview:
        fields["overview"] = f"satellite-{kind}-overview.jpg"
    complete = all((folder / tiles_dir / f"{row}-{col}.jpg").exists() for row, col, *_ in grid) and (
        not overview or (folder / fields["overview"]).exists()
    )
    if before and before.get("date") == day.isoformat() and before.get("tiles") == tiles_dir and complete:
        return fields
    copy = same if same and same.get("tiles") and (not overview or same.get("overview")) else None
    if not copy and sharp_tiles_left < len(grid):
        return {}  # in a later run
    if not copy:
        sharp_tiles_left -= len(grid)
    new = folder / f"{tiles_dir}.new"
    shutil.rmtree(new, ignore_errors=True)
    new.mkdir(parents=True)
    if copy:
        shutil.copytree(folder / copy["tiles"], new, dirs_exist_ok=True)
    else:
        for row, col, box, w, h in grid:
            (new / f"{row}-{col}.jpg").write_bytes(sentinel2.jpeg(client, box, w, h, day))
    if overview:
        if copy:
            data = (folder / copy["overview"]).read_bytes()
        else:
            data = sentinel2.jpeg(client, bbox, *overview, day)
        (folder / fields["overview"]).write_bytes(data)
    shutil.rmtree(folder / tiles_dir, ignore_errors=True)
    new.rename(folder / tiles_dir)
    return fields


# Left out when comparing a new file with the published one: the time it was built.
BUILD_TIME_KEYS = ("generatedAt",)


def unchanged(path: Path, body) -> bool:
    """True when the published file says the same apart from when it was built.
    Such a file is left as it is, so the gateway answers "not changed" and the
    app doesn't download it again (forecasts are trimmed to the current hour,
    so a kept build time is at most about an hour old)."""
    if not isinstance(body, dict) or not path.is_file():
        return False
    try:
        old = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    if not isinstance(old, dict):
        return False
    strip = lambda d: {k: v for k, v in d.items() if k not in BUILD_TIME_KEYS}  # noqa: E731
    return strip(old) == strip(json.loads(json.dumps(body, ensure_ascii=False)))


def write(path: Path, body) -> None:
    if path.parent.is_file():  # the lake list used to be a file at v1/lakes
        path.parent.unlink()
    if unchanged(path, body):
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(body, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    tmp.replace(path)
    if UPLOADER is not None:
        UPLOADER.add(path)


class Uploader:
    """Puts each changed file online while the run goes on, instead of all at the end.

    PUBLISH_UPLOAD is a command with `{files}` in it, for example on the Raspberry Pi
        rclone copy ~/site/v1 r2:rowfrog-api/v1 --files-from-raw {files} --no-check-dest
    Every few seconds the files written since the last time are listed (one path per
    line, relative to the output folder) in a temporary file, and the command is run
    with that file's path for `{files}`. One file is one upload either way, so this
    costs no more uploads than one copy at the end; it only puts each club and lake
    view online seconds after it is built. A failed upload is only logged: the full
    copy after the run (pi/run-publish.sh) still sends every changed file and
    removes the ones that are gone.
    """

    def __init__(self, out: Path, command: str, every: float = 5.0):
        self.out, self.every = out, every
        self.args = shlex.split(command)
        if "{files}" not in self.args:
            raise ValueError("PUBLISH_UPLOAD needs {files} where the list of files goes")
        self.waiting: list[str] = []
        self.sent = self.batches = 0
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._loop, name="upload", daemon=True)
        self.thread.start()

    def add(self, path: Path) -> None:
        try:
            name = path.relative_to(self.out).as_posix()
        except ValueError:
            return
        with self.lock:
            self.waiting.append(name)

    def _loop(self) -> None:
        while not self.stop.wait(self.every):
            self.send()

    def send(self) -> None:
        with self.lock:
            names, self.waiting = list(dict.fromkeys(self.waiting)), []
        if not names:
            return
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
            f.write("\n".join(names) + "\n")
        try:
            result = subprocess.run([f.name if a == "{files}" else a for a in self.args], timeout=600)
            if result.returncode == 0:
                self.sent += len(names)
                self.batches += 1
            else:
                print(f"  upload of {len(names)} files failed (exit {result.returncode}); the copy after the run sends them", flush=True)
        except (OSError, subprocess.SubprocessError) as e:
            print(f"  upload of {len(names)} files failed: {e!r}; the copy after the run sends them", flush=True)
        finally:
            os.unlink(f.name)

    def close(self) -> None:
        self.stop.set()
        self.thread.join()
        self.send()
        print(f"Uploaded {self.sent} files while the run went on, in {self.batches} batches", flush=True)


UPLOADER: Uploader | None = None


def start_uploader(out: Path) -> Uploader | None:
    """The Uploader for PUBLISH_UPLOAD, or None when it is not set (GitHub Pages, tests)."""
    command = os.environ.get("PUBLISH_UPLOAD")
    if not command:
        return None
    try:
        return Uploader(out, command, float(os.environ.get("PUBLISH_UPLOAD_EVERY", "5")))
    except ValueError as e:
        print(f"PUBLISH_UPLOAD not used: {e}")
        return None


def usage_now() -> tuple[set[str], set[str], bool]:
    """Club and lake ids in use, and whether the usage counter answered.

    Only clubs and lakes people actually load count as used, so entering a
    club's launch point costs nothing until someone uses it. Until the
    counter is set up, the confirmed clubs in data/locations.json stand in.
    """
    counted = usage.used(7) if usage else None
    if counted is None:
        clubs = {c.id for c in locations.load(catalog_paths=()).clubs.values()}
        lakes: set[str] = set()
    else:
        clubs, lakes = set(counted.clubs), set(counted.lakes)
        today = usage.used(1) if NEW_USED_PER_DAY else None
        if today is not None:
            clubs = capped(counted.clubs, today.clubs, NEW_USED_PER_DAY)
            lakes = capped(counted.lakes, today.lakes, NEW_USED_PER_DAY)
    all_clubs = locations.load().clubs
    lakes |= {all_clubs[c].lake_id for c in clubs if c in all_clubs}
    return clubs, lakes, counted is not None


def capped(week: dict[str, int], today: dict[str, int], most: int) -> set[str]:
    """The week's used ids, with at most `most` of those first loaded today.

    An id is new today when all its loads this week came today. Ids used on
    earlier days always stay; of the new ones, the most loaded come first, so
    real clubs win over ids someone requested once each. Off while
    NEW_USED_PER_DAY is 0.
    """
    new = [i for i, n in week.items() if today.get(i, 0) >= n]
    kept = set(week) - set(new)
    new.sort(key=lambda i: (-week[i], i))
    if len(new) > most:
        print(f"  usage: {len(new)} ids first loaded today, only the {most} most loaded count as used")
    return kept | set(new[:most])


def weather_maps(state: State, out: Path, clubs: list[locations.Club], now: datetime) -> None:
    """The weather maps around every club, once per ICON-D2 run."""
    try:
        from rowfrog.sources import icon_d2_maps  # needs numpy and eccodes (the satellite extra)

        run = icon_d2_maps.build(out, [(c.launch_point.lat, c.launch_point.lon) for c in clubs], now, state.maps_run)
    except Exception as e:  # the maps must never stop the forecasts
        print(f"  weather maps failed: {type(e).__name__}: {e}")
        return
    if run:
        state.maps_run = run
        print(f"Weather maps from the ICON-D2 run of {run:%Y-%m-%d %H} UTC, {icon_d2_maps.requests_made} DWD requests")
    else:
        print("Weather maps: no newer ICON-D2 run")


def lake_view_workers() -> int:
    """Processes for the lake views: they are pure calculation (about 4 s each on
    the Raspberry Pi 4, Nov 2026), so they run on all cores. LAKE_VIEW_WORKERS=1
    builds them one after another in this process, as before."""
    try:
        return max(1, int(os.environ["LAKE_VIEW_WORKERS"]))
    except (KeyError, ValueError):
        return min(4, os.cpu_count() or 1)


def lake_views(out: Path, lake_ids: list[str], workers: int | None = None) -> int:
    """Writes the lake views and returns how many. Their weather, water and warnings
    are loaded here first (network, shared caches); the building runs in `workers` processes."""
    inputs = []
    for lake_id in lake_ids:
        try:
            inputs.append(asyncio.run(api.lake_view_inputs(lake_id)))
        except HTTPException as e:
            print(f"  lake view {lake_id}: HTTP {e.status_code} {str(e.detail)[:120]}")
        except Exception as e:
            print(f"  lake view {lake_id}: {type(e).__name__}: {e}")
    workers = workers or lake_view_workers()
    views = done = 0

    def keep(lake_id: str, body: dict | None, problem: str | None) -> None:
        nonlocal views, done
        done += 1
        if problem:
            print(f"  lake view {lake_id}: {problem}")
            return
        write(out / "lakes" / lake_id / "view", body)  # one at a time: a view is about 3 MB in memory
        views += 1

    if workers > 1 and len(inputs) > 1:
        try:
            # "spawn": fresh processes that import rowfrog themselves, not copies of this one.
            with ProcessPoolExecutor(workers, mp_context=multiprocessing.get_context("spawn")) as pool:
                for (lake_id, *_), (body, problem) in zip(inputs, pool.map(api.lake_view_json, inputs, chunksize=4)):
                    keep(lake_id, body, problem)
        except Exception as e:  # a worker died (memory?) or could not start: the rest one after another
            print(f"  lake views on {workers} cores stopped after {done} of {len(inputs)}: {type(e).__name__}: {e}")
    for lake_id, *rest in inputs[done:]:
        keep(lake_id, *api.lake_view_json((lake_id, *rest)))
    return views


def built(forecast) -> tuple[dict | None, str | None]:
    """Runs one of the API's forecast functions directly (no web server or test
    client) and gives its JSON as the API would send it, or what went wrong.
    One broken club or lake must not stop the others."""
    try:
        return jsonable_encoder(asyncio.run(forecast)), None
    except HTTPException as e:
        return None, f"HTTP {e.status_code} {str(e.detail)[:120]}"
    except Exception as e:
        return None, f"{type(e).__name__}: {e}"


def parts(clubs, all_lakes, used_clubs, used_lakes, state, now):
    """The run's clubs and lakes in the order they are built: (clubs, lake ids) per part.

    In an all-clubs run the clubs and lakes people use come first, so with
    PUBLISH_UPLOAD they are online a minute or two after the run starts instead
    of after every other club; the rest follows. A run of only the used clubs,
    or a run while nobody uses anything, is one part, as before. Each part's lakes
    are the lakes of its clubs, and in the first part also the used lakes; the
    lakes nobody uses whose forecast is due go with the last part.
    """
    due_lakes = {i for i in all_lakes if due(state.lakes.get(i, (None,))[0], now, LAKE_OTHER_HOURS, LAKE_OTHER_OFFSET)}

    def lakes_of(part, extra):
        ids = {c.lake_id for c in part} | extra
        return [i for i in all_lakes if i in ids]

    first = [c for c in clubs if c.id in used_clubs]
    rest = [c for c in clubs if c.id not in used_clubs]
    if not first or not rest:
        return [(clubs, lakes_of(clubs, set(used_lakes) | due_lakes))]
    return [(first, lakes_of(first, set(used_lakes))), (rest, lakes_of(rest, due_lakes))]


def clubs_written() -> None:
    """Runs PUBLISH_CLUBS_DONE (a command, if set) once a part's club forecasts are
    written (see parts()), so they can go online before the slow lake views (the Raspberry Pi uploads them
    there; pi/run-publish.sh). Its failure is only logged; the run goes on."""
    command = os.environ.get("PUBLISH_CLUBS_DONE")
    if not command:
        return
    sys.stdout.flush()
    try:
        result = subprocess.run(shlex.split(command), timeout=600)
        print(f"Club forecasts handed on early (exit {result.returncode})", flush=True)
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        print(f"Club forecasts not handed on early: {e!r}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("--clubs", choices=["confirmed", "all"], default="confirmed")
    parser.add_argument("--state", type=Path, help="file that keeps forecasts between runs")
    args = parser.parse_args()
    now = datetime.now(timezone.utc)
    state = State(args.state)
    if args.state:
        # Lake grids are kept next to the state and built again only when an outline or the grid code changed.
        lake_view.GRID_CACHE_DIR = args.state.parent / "lake-grids"
    global UPLOADER
    UPLOADER = start_uploader(args.out)
    try:
        return publish(args, now, state)
    finally:
        if UPLOADER is not None:
            UPLOADER.close()
            UPLOADER = None


def publish(args, now: datetime, state: "State") -> int:
    used_clubs, used_lakes, with_usage = usage_now()
    print(f"Used: {len(used_clubs)} clubs, {len(used_lakes)} lakes{'' if with_usage else ' (no usage counter)'}")

    write(args.out / "lakes" / "index", jsonable_encoder(api.list_lakes()))
    countries = jsonable_encoder(api.list_countries())
    write(args.out / "countries" / "index", countries)
    for country in countries:
        write(args.out / "countries" / country["code"] / "lakes", jsonable_encoder(api.country_lakes(country["code"])))

    check_model_run(state, now)
    write(args.out / "status" / "model-runs", {"model": "dwd_icon_d2", "runs": state.model_runs})
    every = list(locations.load().clubs.values())
    clubs = every if args.clubs == "all" else [c for c in every if c.id in used_clubs]
    all_lakes = sorted({c.lake_id for c in every if outlines.load(c.lake_id)})
    satellite_ice(state, all_lakes, now)
    satellite_water(state, all_lakes, now)
    failed: list[str] = []
    model_count = models_written = views = 0
    lake_count = 0
    viewed: set[str] = set()
    for part, part_lakes in parts(clubs, all_lakes, used_clubs, used_lakes, state, now):
        # A part is loaded, built and (with PUBLISH_UPLOAD) put online before the next one starts.
        club_weather(state, part, used_clubs, with_usage, now)
        club_outlooks(state, part, used_clubs, now)
        model_pairs = model_weather(state, part, now)
        local_warnings(state, part, now)
        # The radar line on the widget, for the clubs people use: 10 DWD requests a club.
        radar_points = {c.id: (c.launch_point.lat, c.launch_point.lon) for c in part if c.id in used_clubs}
        radar = asyncio.run(dwd_radar.nowcasts(radar_points)) if radar_points else {}
        if radar_points:
            print(f"Radar for {len(radar)} clubs, {dwd_radar.requests_made} DWD requests so far")
        # Lake weather before the clubs, so a club's light can count the water near its launch point.
        ready_lakes = lake_weather(state, part_lakes, used_lakes, now)
        lake_count += len([i for i in part_lakes if i not in viewed])
        part_failed = []
        for club in part:
            if club.id not in api.prepared.weather:
                part_failed.append(f"{club.id}: no forecast loaded")
                continue
            body, problem = built(api.club_forecast(club.id))
            if problem:
                part_failed.append(f"{club.id}: {problem}")
                continue
            if club.id in radar:
                body["radar"] = radar[club.id]
            if club.id in state.club_runs:
                body["weatherRun"] = {"model": "ICON-D2", **state.club_runs[club.id]}
            if with_usage:
                body["refresh"] = refresh_block(club.id in used_clubs)
            write(args.out / "clubs" / club.id / "forecast", body)
        print(f"Wrote {len(part) - len(part_failed)} of {len(part)} forecasts to {args.out}")
        failed += part_failed
        model_count += len(model_pairs)
        for club, model in model_pairs:
            body, problem = built(api.club_forecast_with_model(club.id, model))
            if problem:
                print(f"  {club.id} with {model}: {problem}")
                continue
            write(args.out / "clubs" / club.id / "models" / model / "forecast", body)
            models_written += 1
        clubs_written()
        new_views = [i for i in ready_lakes if i not in viewed]
        views += lake_views(args.out, new_views)
        viewed.update(new_views)
    print(f"Wrote {models_written} of {model_count} forecasts with other weather models")
    print(f"Wrote {views} of {lake_count} lake views")
    state.save()

    weather_maps(state, args.out, every, now)
    state.save()

    publish_ice_map(args.out, all_lakes, now.astimezone(LOCAL).date())
    # River sections and clubs without an outline only when used: about 340
    # river clubs would take a third of the free Copernicus requests.
    places = club_places(c for c in every if c.id in used_clubs)
    sections = river_places(locations.load().lakes, all_lakes)
    places.update({i: ring for i, ring in sections.items() if i in used_lakes})
    lakes_only = [i for i in all_lakes if i not in sections]
    areas = club_areas(c for c in every if c.id in used_clubs and c.lake_id in lakes_only)
    publish_pictures(args.out, lakes_only + sorted(places), used_lakes | set(places), now, places, areas)
    calls = round(open_meteo.calls_counted, 1)
    copernicus = sentinel2.requests_made + lake_ice_satellite.requests_made
    print(f"Open-Meteo calls: {calls}, Copernicus requests: {copernicus}")
    if usage:
        usage.report_calls("open-meteo", calls, "publish")
        usage.report_calls("copernicus", copernicus, "publish")
    for line in failed:
        print("  failed", line)
    # Fail the run only when nothing could be written, so one flaky club does not raise alarms.
    return 1 if clubs and len(failed) == len(clubs) else 0


if __name__ == "__main__":
    sys.exit(main())
