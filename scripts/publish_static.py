#!/usr/bin/env python3
"""Write the backend's answers as static files, for hosting on GitHub Pages.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/publish_static.py OUT_DIR [--clubs confirmed|all]

Calls the same FastAPI app the server would run (no network server needed)
and writes each answer at its API path, without a file extension:
    OUT_DIR/lakes                       = GET /lakes
    OUT_DIR/clubs/<id>/forecast         = GET /clubs/<id>/forecast
So the app reads the files with the same paths as from a live backend, and
moving to a real server later only changes the app's RWAPIBaseURL.

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
from pathlib import Path

import httpx
from fastapi.testclient import TestClient

from rowerweather import api, locations
from rowerweather.api import app
from rowerweather.sources import open_meteo

# Clubs per Open-Meteo request. Loading forecasts in batches takes a few
# requests instead of one per club; single requests from GitHub's shared
# runners often timed out or were refused.
BATCH = 50
# Waits before retrying a failed batch, in seconds; Open-Meteo's limit is per minute.
RETRY_WAITS = (65, 120)


async def prime_weather(clubs: list[locations.Club]) -> list[str]:
    """Load the forecasts for `clubs` in batches into the API's cache; returns problems."""
    problems = []
    async with httpx.AsyncClient() as client:
        for start in range(0, len(clubs), BATCH):
            batch = clubs[start : start + BATCH]
            points = [(c.launch_point.lat, c.launch_point.lon) for c in batch]
            for attempt, wait in enumerate((0, *RETRY_WAITS)):
                await asyncio.sleep(wait)
                try:
                    forecasts = await open_meteo.fetch_many(client, points)
                    break
                except (httpx.HTTPError, ValueError, KeyError) as e:
                    detail = e.response.text[:200] if isinstance(e, httpx.HTTPStatusError) else ""
                    problems.append(f"batch {start // BATCH + 1} attempt {attempt + 1}: {e!r} {detail}")
            else:
                continue
            for club, weather in zip(batch, forecasts):
                api._primed_weather[club.id] = weather
    return problems


def write(path: Path, body) -> None:
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
    resp = client.get("/lakes")
    resp.raise_for_status()
    write(args.out / "lakes", resp.json())

    if args.clubs == "all":
        clubs = list(locations.load().clubs.values())
    else:
        clubs = list(locations.load(catalog_paths=()).clubs.values())
    club_ids = [c.id for c in clubs]
    for line in asyncio.run(prime_weather(clubs)):
        print("  weather", line)
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
    for line in failed:
        print("  failed", line)
    # Fail the run only when nothing could be written, so one flaky club does not raise alarms.
    return 1 if club_ids and len(failed) == len(club_ids) else 0


if __name__ == "__main__":
    sys.exit(main())
