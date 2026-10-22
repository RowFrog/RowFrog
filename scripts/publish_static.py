#!/usr/bin/env python3
"""Write the backend's answers as static files, for hosting on GitHub Pages.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/publish_static.py OUT_DIR [--clubs confirmed|all]

Calls the same FastAPI app the server would run (no network server needed)
and writes each answer at its API path, without a file extension:
    OUT_DIR/lakes/index                 = GET /lakes/index (the lake list)
    OUT_DIR/lakes/<id>/view             = GET /lakes/<id>/view
    OUT_DIR/clubs/<id>/forecast         = GET /clubs/<id>/forecast
So the app reads the files with the same paths as from a live backend, and
moving to a real server later only changes the app's RWAPIBaseURL.
With the Copernicus account (CDSE_CLIENT_ID / CDSE_CLIENT_SECRET) it also
writes the latest cloud-free Sentinel-2 picture of each lake:
    OUT_DIR/lakes/<id>/satellite        when it was taken, its size, credit
    OUT_DIR/lakes/<id>/satellite.jpg    the picture

"confirmed" refreshes the clubs in data/locations.json, "all" every club in
the catalogs too; the scheduled workflow runs the first often and the second
a few times a day, to stay within Open-Meteo's free daily limit. A club whose
forecast fails keeps its previous file, which still shows when it was made.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
from fastapi.testclient import TestClient

from rowerweather import api, ice, lake_view, locations, outlines
from rowerweather.api import LOCAL, app
from rowerweather.sources import lake_ice_satellite, open_meteo, sentinel2

# Clubs per Open-Meteo request. Loading forecasts in batches takes a few
# requests instead of one per club; single requests from GitHub's shared
# runners often timed out or were refused.
BATCH = 50
# Waits before retrying a failed batch, in seconds; Open-Meteo's limit is per minute.
RETRY_WAITS = (65, 120)
# How often a lake's satellite picture is looked for, and how many lakes one run looks at.
PICTURE_REFRESH = {"confirmed": timedelta(hours=24), "other": timedelta(hours=72)}
PICTURES_PER_RUN = 40


async def _batched(points: list[tuple[float, float]]) -> tuple[list[list | None], list[str]]:
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
                    forecasts = await open_meteo.fetch_many(client, batch)
                    break
                except (httpx.HTTPError, ValueError, KeyError) as e:
                    detail = e.response.text[:200] if isinstance(e, httpx.HTTPStatusError) else ""
                    problems.append(f"batch {start // BATCH + 1} attempt {attempt + 1}: {e!r} {detail}")
            out += forecasts if forecasts else [None] * len(batch)
    return out, problems


async def prime_weather(clubs: list[locations.Club]) -> list[str]:
    """Load the forecasts for `clubs` in batches into the API's cache; returns problems."""
    forecasts, problems = await _batched([(c.launch_point.lat, c.launch_point.lon) for c in clubs])
    for club, weather in zip(clubs, forecasts):
        if weather is not None:
            api._primed_weather[club.id] = weather
    return problems


async def prime_lake_weather(lake_ids: list[str]) -> list[str]:
    """The same for the lake views' sample points, all lakes together."""
    owners, points = [], []
    for lake_id in lake_ids:
        for lon, lat in lake_view.grid_for(lake_id, outlines.load(lake_id)).samples:
            owners.append(lake_id)
            points.append((lat, lon))
    forecasts, problems = await _batched(points)
    per_lake: dict[str, list] = {}
    for lake_id, weather in zip(owners, forecasts):
        per_lake.setdefault(lake_id, []).append(weather)
    for lake_id, weathers in per_lake.items():
        if all(w is not None for w in weathers):
            api._primed_lake_weather[lake_id] = weathers
    return problems


def prime_satellite_ice(clubs: list[locations.Club]) -> None:
    """Load the last days of the satellite ice map for the clubs' lakes, in the ice season."""
    today = datetime.now(LOCAL).date()
    if ice.out_of_season(today) or not lake_ice_satellite.configured():
        return
    lakes = locations.load().lakes
    shores = {}
    for lake_id in {c.lake_id for c in clubs}:
        lake = lakes.get(lake_id)
        rings = outlines.load(lake_id) if lake and lake.kind == "lake" else None
        if rings:
            shores[lake_id] = rings[0]
    api._satellite_ice.update(lake_ice_satellite.fetch(shores, today))
    for lake_id, passes in sorted(api._satellite_ice.items()):
        last = passes[-1]
        print(f"  satellite {lake_id}: {last.day} seen {last.seen_share:.0%} ice {last.ice_share:.0%}")


def publish_pictures(out: Path, lake_ids: list[str], confirmed: set[str]) -> None:
    """Look for newer Sentinel-2 pictures of the lakes whose last look is old enough."""
    client = sentinel2.client()
    if client is None:
        return
    now = datetime.now(timezone.utc)
    looked = 0
    try:
        for lake_id in sorted(lake_ids, key=lambda i: (i not in confirmed, i)):
            rings = outlines.load(lake_id)
            meta_path = out / "lakes" / lake_id / "satellite"
            old = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
            refresh = PICTURE_REFRESH["confirmed" if lake_id in confirmed else "other"]
            checked = datetime.fromisoformat(old["checkedAt"]) if "checkedAt" in old else None
            if not rings or (checked and now - checked < refresh) or looked >= PICTURES_PER_RUN:
                continue
            looked += 1
            try:
                picture = sentinel2.latest(client, rings[0], now)
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
            body = dict(old, checkedAt=now.replace(microsecond=0).isoformat())
            if picture and picture.taken.isoformat() != old.get("taken"):
                jpg = out / "lakes" / lake_id / "satellite.jpg"
                jpg.parent.mkdir(parents=True, exist_ok=True)
                jpg.write_bytes(picture.jpeg)
                body.update(
                    taken=picture.taken.isoformat(),
                    lakeCloud=round(picture.lake_cloud, 2),
                    bbox=[round(v, 5) for v in picture.bbox],
                    width=picture.width,
                    height=picture.height,
                    image="satellite.jpg",
                    attribution=f"Contains modified Copernicus Sentinel data {picture.taken.year}",
                )
            write(meta_path, body)
            print(f"  picture {lake_id}: {body.get('taken', 'none in the last 30 days')}")
    finally:
        if client is not None:
            client.close()


def write(path: Path, body) -> None:
    if path.parent.is_file():  # the lake list used to be a file at v1/lakes
        path.parent.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(body, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("--clubs", choices=["confirmed", "all"], default="confirmed")
    args = parser.parse_args()

    client = TestClient(app)
    resp = client.get("/lakes/index")
    resp.raise_for_status()
    write(args.out / "lakes" / "index", resp.json())

    if args.clubs == "all":
        clubs = list(locations.load().clubs.values())
    else:
        clubs = list(locations.load(catalog_paths=()).clubs.values())
    club_ids = [c.id for c in clubs]
    for line in asyncio.run(prime_weather(clubs)):
        print("  weather", line)
    prime_satellite_ice(clubs)
    failed = []
    for club_id in club_ids:
        try:
            resp = client.get(f"/clubs/{club_id}/forecast")
        except Exception as e:  # one broken club must not stop the others
            failed.append(f"{club_id}: {type(e).__name__}: {e}")
            continue
        if resp.status_code != 200:
            failed.append(f"{club_id}: HTTP {resp.status_code} {resp.text[:120]}")
            continue
        write(args.out / "clubs" / club_id / "forecast", resp.json())
    print(f"Wrote {len(club_ids) - len(failed)} of {len(club_ids)} forecasts to {args.out}")
    lake_ids = sorted({c.lake_id for c in clubs if outlines.load(c.lake_id)})
    for line in asyncio.run(prime_lake_weather(lake_ids)):
        print("  lake weather", line)
    views = 0
    for lake_id in lake_ids:
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
    confirmed = {c.lake_id for c in locations.load(catalog_paths=()).clubs.values()}
    publish_pictures(args.out, lake_ids, confirmed)
    for line in failed:
        print("  failed", line)
    # Fail the run only when nothing could be written, so one flaky club does not raise alarms.
    return 1 if club_ids and len(failed) == len(club_ids) else 0


if __name__ == "__main__":
    sys.exit(main())
