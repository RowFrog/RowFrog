#!/usr/bin/env python3
"""Show each step of finding a Sentinel-2 picture for a few lakes (sources/sentinel2.py).

Usage: CDSE_CLIENT_ID=... CDSE_CLIENT_SECRET=... python3 scripts/satellite_picture_probe.py
"""

from __future__ import annotations

import logging
import sys
from datetime import datetime, timedelta, timezone

from rowerweather import outlines
from rowerweather.sources import sentinel2

LAKES = ["starnberger-see", "ammersee"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="  %(message)s")
    client = sentinel2.client()
    if client is None:
        print("No Copernicus account in CDSE_CLIENT_ID / CDSE_CLIENT_SECRET, or sign-in failed.")
        return 0
    today = datetime.now(timezone.utc).date()
    for lake_id in LAKES:
        ring = outlines.load(lake_id)[0]
        bbox, width, height = sentinel2.frame(ring)
        print(f"## {lake_id}: box {bbox}, {width} x {height} px")
        for days in (sentinel2.SEARCH_DAYS, sentinel2.FIRST_SEARCH_DAYS):
            try:
                passes = sentinel2.cloud_by_day(client, ring, today - timedelta(days=days), today)
            except Exception as e:
                body = getattr(getattr(e, "response", None), "text", "")[:500]
                print(f"  {days} days: statistics failed {e!r} {body}")
                continue
            latest, mostly_clear, clearest = sentinel2.choose(passes)
            print(f"  {days} days: {len(passes)} passes, latest {latest}, mostly clear {mostly_clear}, clearest {clearest}")
            print("   ", ", ".join(f"{p.day:%m-%d} {p.lake_cloud:.0%}" for p in passes[-12:]))
    print(f"Requests: {sentinel2.requests_made}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
