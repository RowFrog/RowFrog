#!/usr/bin/env python3
"""Write the backend's answers as static files, for hosting on GitHub Pages.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/publish_static.py OUT_DIR [--clubs confirmed|all] [--state FILE]

Calls the same FastAPI app the server would run (no network server needed)
and writes each answer at its API path, without a file extension:
    OUT_DIR/lakes/index                 = GET /lakes/index (the lake list)
    OUT_DIR/countries/index             = GET /countries/index (countries with clubs)
    OUT_DIR/countries/<cc>/lakes        = GET /countries/<cc>/lakes (one country's waters and clubs)
    OUT_DIR/lakes/<id>/view             = GET /lakes/<id>/view
    OUT_DIR/clubs/<id>/forecast         = GET /clubs/<id>/forecast
So the app reads the files with the same paths as from a live backend, and
moving to a real server later only changes where api.rowfrog.com points.
With the Copernicus account (CDSE_CLIENT_ID / CDSE_CLIENT_SECRET) it also
writes Sentinel-2 pictures of each lake and, in winter, the satellite ice map:
    OUT_DIR/lakes/<id>/satellite        dates, cloud, picture box, credit
    OUT_DIR/lakes/<id>/satellite-latest.jpg, satellite-clearest.jpg, ice.png

"confirmed" rebuilds the clubs people use (until the usage counter is set up,
the clubs in data/locations.json), "all" every club in the catalogs too.
Warnings and water temperatures are fresh in every file, but weather is
loaded only when the weather model
has a new run for it (WEATHER_HOURS), to stay within Open-Meteo's free
10,000 calls a day; between loads the --state file (kept by the workflow's
cache) holds the last forecast. A club whose forecast fails keeps its
previous file, which still shows when it was made.

Which clubs and lakes are "used" comes from the usage counter in front of
api.rowfrog.com (rowerweather.usage, when it is set up); without it the
confirmed clubs count as used and the rest follow the fixed schedule.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import pickle
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import httpx
from fastapi.testclient import TestClient

from rowerweather import api, ice, lake_view, locations, outlines
from rowerweather.api import LOCAL, app
from rowerweather.sources import lake_ice_satellite, open_meteo, sentinel2

try:  # the usage counter (PR #15) may not be part of this checkout yet
    from rowerweather import usage
except ImportError:
    usage = None

# Points per Open-Meteo request. Loading forecasts in batches takes a few
# requests instead of one per point; single requests from GitHub's shared
# runners often timed out or were refused.
BATCH = 50
# Waits before retrying a failed batch, in seconds; Open-Meteo's limit is per minute.
RETRY_WAITS = (65, 120)
# Hours loaded per forecast: two days from now plus the longest wait for the next load.
FETCH_HOURS = 60

# ICON-D2 runs every 3 hours (00, 03, ... UTC) and its forecast is ready
# about READY_AFTER later. Loading more often brings nothing new.
READY_AFTER = timedelta(hours=2, minutes=30)
WEATHER_HOURS = {"used": 3, "other": 6, "other with usage": 12}
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

# How often a lake is looked at for new Sentinel-2 pictures, and how many lakes one run looks at.
PICTURE_REFRESH = {"used": timedelta(days=1), "other": timedelta(days=5)}
# Bumped when the search changes, so every lake is looked at again on the next run.
PICTURE_SEARCH_VERSION = 4
# Lakes looked at with versions before this one get the long first search.
PICTURE_FIRST_SEARCH_BEFORE = 3
PICTURES_PER_RUN = 40


def last_ready(now: datetime, every_hours: int, offset: timedelta = timedelta()) -> datetime:
    """When the newest forecast run (every `every_hours` from 00 UTC) became ready."""
    base = now - READY_AFTER - offset
    run = base.replace(hour=base.hour - base.hour % every_hours, minute=0, second=0, microsecond=0)
    return run + READY_AFTER + offset


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
        if path and path.exists():
            try:
                saved = pickle.loads(path.read_bytes())
                self.clubs, self.lakes, self.ice_map = saved["clubs"], saved["lakes"], saved["ice_map"]
                self.outlooks = saved.get("outlooks", {})
                api._last_water.update(saved.get("water", {}))
                api._ice_temps.update(saved["ice_temps"])
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
            "ice_temps": api._ice_temps,
            "outlooks": self.outlooks,
            "water": api._last_water,
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
    print(f"  weather loaded for {len(stale)} of {len(clubs)} clubs")
    for club in clubs:
        if club.id in state.clubs:
            api._primed_weather[club.id] = state.clubs[club.id][1]


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
        api._primed_outlook[club.id] = saved[1] if saved else None


def lake_weather(state: State, lake_ids: list[str], used: set[str], now: datetime) -> list[str]:
    """The same for the lake views; returns the lakes that have a forecast."""
    stale = []
    for lake_id in lake_ids:
        samples = lake_view.USED_SAMPLES if lake_id in used else lake_view.MAX_SAMPLES
        if samples != lake_view.MAX_SAMPLES:
            api._lake_samples[lake_id] = samples
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
            api._primed_lake_weather[lake_id] = state.lakes[lake_id][2]
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
    api._satellite_ice.clear()
    api._satellite_ice.update(passes)


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
            for p in api._satellite_ice.get(lake_id, [])
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


def publish_pictures(out: Path, lake_ids: list[str], used: set[str], now: datetime) -> None:
    """Looks for newer Sentinel-2 pictures of the lakes whose last look is old enough.

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
            rings = outlines.load(lake_id)
            meta_path = out / "lakes" / lake_id / "satellite"
            old = _read_json(meta_path)
            version = old.get("searchVersion", 0)
            first = version < PICTURE_FIRST_SEARCH_BEFORE
            checked = None if version != PICTURE_SEARCH_VERSION or "checkedAt" not in old else datetime.fromisoformat(old["checkedAt"])
            refresh = PICTURE_REFRESH["used" if lake_id in used else "other"]
            if not rings or (checked and now - checked < refresh) or looked >= PICTURES_PER_RUN:
                continue
            looked += 1
            days = sentinel2.FIRST_SEARCH_DAYS if first else sentinel2.SEARCH_DAYS
            try:
                latest, mostly_clear, clearest = sentinel2.choose(
                    sentinel2.cloud_by_day(client, rings[0], today - timedelta(days=days), today)
                )
                body = _picture_meta(client, out / "lakes" / lake_id, rings[0], old, latest, clearest, mostly_clear)
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


def _picture_meta(client, folder: Path, ring, old: dict, latest, clearest, mostly_clear=None) -> dict:
    """The satellite file's picture part, rendering the pictures that are new.

    A third, "mostly clear" picture is added only when it is newer than the
    clearest and not the latest itself, so it shows something the other two don't.
    """
    bbox, width, height = sentinel2.frame(ring)
    body = {k: v for k, v in old.items() if k in ("ice",)}
    body.update(bbox=[round(v, 5) for v in bbox], width=width, height=height)
    old_frame = old.get("bbox") == body["bbox"] and old.get("width") == width
    for kind, found in (("latest", latest), ("clearest", clearest)):
        before = old.get(kind) if old_frame else None
        if found is None:  # nothing new: keep showing the last one
            if before:
                body[kind] = before
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
        body["mostlyClear"] = entry
    shown = (body.get("latest"), body.get("mostlyClear"), body.get("clearest"))
    years = sorted({e["date"][:4] for e in shown if e})
    if years:
        body["attribution"] = f"Contains modified Copernicus Sentinel data {', '.join(years)}"
    (folder / "satellite.jpg").unlink(missing_ok=True)  # the single picture of the first version
    return body


def write(path: Path, body) -> None:
    if path.parent.is_file():  # the lake list used to be a file at v1/lakes
        path.parent.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(body, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    tmp.replace(path)


def usage_now() -> tuple[set[str], set[str], bool]:
    """Club and lake ids in use, and whether the usage counter answered.

    Only clubs and lakes people actually load count as used, so entering a
    club's launch point costs nothing until someone uses it. Until the
    counter is set up, the confirmed clubs in data/locations.json stand in.
    """
    counted = usage.used(7) if usage else None
    if counted is None:
        clubs = {c.id for c in locations.load(catalog_paths=()).clubs.values()}
    else:
        clubs = set(counted.clubs)
    all_clubs = locations.load().clubs
    lakes = {all_clubs[c].lake_id for c in clubs if c in all_clubs}
    if counted is not None:
        lakes |= set(counted.lakes)
    return clubs, lakes, counted is not None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("--clubs", choices=["confirmed", "all"], default="confirmed")
    parser.add_argument("--state", type=Path, help="file that keeps forecasts between runs")
    args = parser.parse_args()
    now = datetime.now(timezone.utc)
    state = State(args.state)
    used_clubs, used_lakes, with_usage = usage_now()
    print(f"Used: {len(used_clubs)} clubs, {len(used_lakes)} lakes{'' if with_usage else ' (no usage counter)'}")

    client = TestClient(app)
    resp = client.get("/lakes/index")
    resp.raise_for_status()
    write(args.out / "lakes" / "index", resp.json())
    resp = client.get("/countries/index")
    resp.raise_for_status()
    write(args.out / "countries" / "index", resp.json())
    for country in resp.json():
        lakes = client.get(f"/countries/{country['code']}/lakes")
        lakes.raise_for_status()
        write(args.out / "countries" / country["code"] / "lakes", lakes.json())

    every = list(locations.load().clubs.values())
    clubs = every if args.clubs == "all" else [c for c in every if c.id in used_clubs]
    club_weather(state, clubs, used_clubs, with_usage, now)
    club_outlooks(state, clubs, used_clubs, now)
    all_lakes = sorted({c.lake_id for c in every if outlines.load(c.lake_id)})
    satellite_ice(state, all_lakes, now)
    failed = []
    for club in clubs:
        if club.id not in api._primed_weather:
            failed.append(f"{club.id}: no forecast loaded")
            continue
        try:
            resp = client.get(f"/clubs/{club.id}/forecast")
        except Exception as e:  # one broken club must not stop the others
            failed.append(f"{club.id}: {type(e).__name__}: {e}")
            continue
        if resp.status_code != 200:
            failed.append(f"{club.id}: HTTP {resp.status_code} {resp.text[:120]}")
            continue
        write(args.out / "clubs" / club.id / "forecast", resp.json())
    print(f"Wrote {len(clubs) - len(failed)} of {len(clubs)} forecasts to {args.out}")

    # The lakes of this run's clubs, and any other lake whose forecast is due.
    run_lakes = {c.lake_id for c in clubs}
    lake_ids = [
        i
        for i in all_lakes
        if i in run_lakes or i in used_lakes or due(state.lakes.get(i, (None,))[0], now, LAKE_OTHER_HOURS, LAKE_OTHER_OFFSET)
    ]
    views = 0
    for lake_id in lake_weather(state, lake_ids, used_lakes, now):
        try:
            resp = client.get(f"/lakes/{lake_id}/view")
        except Exception as e:
            print(f"  lake view {lake_id}: {type(e).__name__}: {e}")
            continue
        if resp.status_code != 200:
            print(f"  lake view {lake_id}: HTTP {resp.status_code} {resp.text[:120]}")
            continue
        write(args.out / "lakes" / lake_id / "view", resp.json())
        views += 1
    print(f"Wrote {views} of {len(lake_ids)} lake views")
    state.save()

    publish_ice_map(args.out, all_lakes, now.astimezone(LOCAL).date())
    publish_pictures(args.out, all_lakes, used_lakes, now)
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
