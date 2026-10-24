#!/usr/bin/env python3
"""Store weather model forecasts and score them against DWD measurements.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/model_check.py DATA_DIR [--stage 1] [--archive-days 0] [--no-forecast]

DATA_DIR keeps the stored forecasts (forecasts/YYYY/MM/DD-HH.csv.gz) and gets
report.md and stations.json; the workflow keeps it on the model-check branch.
--archive-days N also loads N days of Open-Meteo's archived forecasts once,
so a first score exists without waiting weeks. See backend/rowerweather/model_check.py.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

from rowerweather import model_check as mc
from rowerweather import usage

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("data_dir", type=Path)
    parser.add_argument("--stage", type=int, default=1)
    parser.add_argument("--archive-days", type=int, default=0)
    parser.add_argument("--no-forecast", action="store_true")
    args = parser.parse_args()

    now = datetime.now(timezone.utc)
    points = mc.load_points(ROOT / "data" / "model-check" / "points.json", args.stage)
    models = mc.models_for(args.stage)
    print(f"{len(points)} points, {len(models)} models")

    with httpx.Client(headers={"User-Agent": "RowFrog model check (github.com/RowFrog)"}, follow_redirects=True) as client:
        calls = 0.0
        if not args.no_forecast:
            rows, log = mc.fetch_forecasts(client, points, models, now)
            calls += len(models) * usage.call_weight(len(mc.VARIABLES), locations=len(points))
            print("\n".join("  " + l for l in log))
            if rows:
                mc.write_rows(args.data_dir / "forecasts" / f"{now:%Y/%m/%d-%H}.csv.gz", rows)
        if args.archive_days:
            rows, log = mc.fetch_archive(client, points, models, args.archive_days, now.date())
            calls += len(models) * usage.call_weight(len(mc.VARIABLES), days=args.archive_days, locations=len(points))
            print("\n".join("  " + l for l in log))
            if rows:
                mc.write_rows(args.data_dir / "forecasts" / "archive" / f"{now:%Y-%m-%d}.csv.gz", rows)

        usage.report_calls("open-meteo", calls, "model-check", client)
        stored = mc.read_rows(args.data_dir)
        print(f"{len(stored)} stored forecast hours")
        since = now.date() - timedelta(days=3)
        obs, used, log = mc.observations(client, points, since)
        print("\n".join("  " + l for l in log))

    (args.data_dir / "stations.json").write_text(json.dumps(used, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    text = mc.report(points, stored, obs, used, now)
    (args.data_dir / "report.md").write_text(text + "\n", encoding="utf-8")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
