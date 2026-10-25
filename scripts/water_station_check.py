#!/usr/bin/env python3
"""Reads every station in data/water-stations.json once, the way the forecast
does (api._water), and prints its newest value, so a wrong id or a stopped
station shows up before the app reads nothing.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/water_station_check.py
"""

from __future__ import annotations

import asyncio
import statistics
import sys
from datetime import datetime, timezone

import httpx

from rowfrog import api, water_stations

# Further than this from the median of all stations is worth a look (and maybe
# an entry in water_station_survey.DOUBTFUL).
DOUBTFUL_C = 4.0


async def main() -> int:
    now = datetime.now(timezone.utc)
    stations = {s.key: s for s in water_stations._load().values()}
    users = {}
    for club, s in water_stations._load().items():
        users.setdefault(s.key, []).append(club)
    readings = {}
    async with httpx.AsyncClient() as client:
        for key, s in sorted(stations.items()):
            water, history = await api._water(client, s, now)
            if water is not None:
                readings[key] = water.celsius
            value = "no current value" if water is None else f"{water.celsius:.1f} °C at {water.time.isoformat()} ({len(history)} h of history)"
            print(f"{s.network}\t{s.name}\t{value}\t{', '.join(users[key])}", flush=True)
    print(f"\n{len(readings)} of {len(stations)} stations sent a current value.")
    # A station far off all the others is likely in a harbour or behind a warm inflow.
    if readings:
        middle = statistics.median(readings.values())
        odd = [f"{stations[k].name} {c:.1f} °C" for k, c in readings.items() if abs(c - middle) > DOUBTFUL_C]
        print(f"Median {middle:.1f} °C; more than {DOUBTFUL_C:.0f} °C off it: {', '.join(odd) or 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
