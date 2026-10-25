#!/usr/bin/env python3
"""Reads every station in data/water-stations.json once, the way the forecast
does (api._water), and prints its newest value, so a wrong id or a stopped
station shows up before the app reads nothing.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/water_station_check.py
"""

from __future__ import annotations

import asyncio
import sys
from datetime import datetime, timezone

import httpx

from rowfrog import api, water_stations


async def main() -> int:
    now = datetime.now(timezone.utc)
    stations = {s.key: s for s in water_stations._load().values()}
    users = {}
    for club, s in water_stations._load().items():
        users.setdefault(s.key, []).append(club)
    quiet = 0
    async with httpx.AsyncClient() as client:
        for key, s in sorted(stations.items()):
            water, history = await api._water(client, s, now)
            if water is None:
                quiet += 1
            value = "no current value" if water is None else f"{water.celsius:.1f} °C at {water.time.isoformat()} ({len(history)} h of history)"
            print(f"{s.network}\t{s.name}\t{value}\t{', '.join(users[key])}", flush=True)
    print(f"\n{len(stations) - quiet} of {len(stations)} stations sent a current value.")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
