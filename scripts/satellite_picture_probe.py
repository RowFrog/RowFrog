#!/usr/bin/env python3
"""Show each step of finding a Sentinel-2 picture for a few lakes (sources/sentinel2.py).

Usage: CDSE_CLIENT_ID=... CDSE_CLIENT_SECRET=... python3 scripts/satellite_picture_probe.py
"""

from __future__ import annotations

import logging
import sys
from datetime import datetime, timezone

from rowerweather import outlines
from rowerweather.sources import sentinel2

LAKES = ["starnberger-see", "ammersee"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="  %(message)s")
    client = sentinel2.client()
    if client is None:
        print("No Copernicus account in CDSE_CLIENT_ID / CDSE_CLIENT_SECRET, or sign-in failed.")
        return 0
    now = datetime.now(timezone.utc)
    for lake_id in LAKES:
        ring = outlines.load(lake_id)[0]
        bbox, width, height = sentinel2.frame(ring)
        print(f"## {lake_id}: box {bbox}, {width} x {height} px")
        try:
            passes = sentinel2._passes(client, bbox, now)
        except Exception as e:
            body = getattr(getattr(e, "response", None), "text", "")[:500]
            print(f"  catalogue failed: {e!r} {body}")
            continue
        print(f"  {len(passes)} passes: {[p.isoformat() for p in passes[:8]]}")
        for taken in passes[:2]:
            try:
                print(f"  {taken:%Y-%m-%d}: lake cloud {sentinel2._lake_cloud(client, ring, taken)}")
            except Exception as e:
                body = getattr(getattr(e, "response", None), "text", "")[:500]
                print(f"  {taken:%Y-%m-%d}: statistics failed {e!r} {body}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
