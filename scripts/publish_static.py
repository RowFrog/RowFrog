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
import json
import sys
import time
from pathlib import Path

from fastapi.testclient import TestClient

from rowerweather import locations
from rowerweather.api import app

# Pause between clubs, to stay well under Open-Meteo's per-minute limit.
PAUSE_SECONDS = 0.2


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
        club_ids = list(locations.load().clubs)
    else:
        club_ids = list(locations.load(catalog_paths=()).clubs)
    failed = []
    for i, club_id in enumerate(club_ids):
        if i:
            time.sleep(PAUSE_SECONDS)
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
