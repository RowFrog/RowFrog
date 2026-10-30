"""Lists DWD's lake warning areas, the clubs in each, and whether data/shore-lights.json knows them.

DWD runs a lake warning for 23 areas (30.10.2026), but only some of those
lakes have flashing storm lights on the shore. The app explains the lights
only where data/shore-lights.json says so; an area missing from that file
counts as "no lights". Run this by hand from the Actions tab ("Lake lights
check") to see whether DWD added or renamed an area. Nothing is stored.
"""

from __future__ import annotations

import asyncio
import json
import sys
from collections import defaultdict
from pathlib import Path

import httpx

sys.path.insert(0, "backend")
from rowfrog import locations  # noqa: E402
from rowfrog.sources import dwd_warnings  # noqa: E402

UA = {"User-Agent": "RowFrog lake lights check (github.com/RowFrog/RowFrog)"}


async def main() -> int:
    known = {a["warncellId"]: a for a in json.loads(Path("data/shore-lights.json").read_text(encoding="utf-8"))["areas"]}
    async with httpx.AsyncClient(headers=UA, follow_redirects=True) as client:
        areas = await dwd_warnings.fetch_lake_areas(client)
    locs = locations.load()
    by_area: dict[int, list[str]] = defaultdict(list)
    for club in locs.clubs.values():
        area = dwd_warnings.lake_area_for(club.launch_point.lon, club.launch_point.lat, areas)
        if area:
            by_area[area.warncell_id].append(club.name)
    print(f"== {len(areas)} DWD lake warning areas ==")
    missing = []
    for a in sorted(areas, key=lambda a: a.name):
        entry = known.get(a.warncell_id)
        lights = "MISSING" if entry is None else ("lights" if entry["lights"] else "no lights")
        if entry is None:
            missing.append(a)
        print(f"{a.warncell_id}\t{a.name}\t{lights}\tclubs={len(by_area[a.warncell_id])}")
        for name in sorted(by_area[a.warncell_id]):
            print(f"    - {name}")
    gone = set(known) - {a.warncell_id for a in areas}
    for cell in sorted(gone):
        print(f"In data/shore-lights.json but no longer at DWD: {cell} {known[cell]['name']}")
    if missing:
        print("New DWD areas: find out whether they have storm lights and add them to data/shore-lights.json.")
    return 1 if missing or gone else 0


sys.exit(asyncio.run(main()))
