#!/usr/bin/env python3
"""Run the ice estimate over past winters, to check it against what rowers remember.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/ice_backtest.py [first winter, default 2005]

For each lake with confirmed clubs, plus a few catalog lakes near Munich, it
loads daily mean air temperatures from Open-Meteo's archive (ERA5) for every
winter (1 October to 30 April) and prints, per winter, how many days the model
says "edges", "forming" and "frozen", the thickest ice and the frozen dates.
No water temperature is used, so this is the model alone. The table is printed
and, on GitHub Actions, added to the job summary.
"""

from __future__ import annotations

import asyncio
import os
import sys
from datetime import date

import httpx

from rowfrog import ice, locations
from rowfrog.sources import open_meteo

EXTRA_LAKES = ["ammersee", "regattastrecke-oberschleissheim"]


async def winter(client: httpx.AsyncClient, lake: locations.Lake, year: int) -> str:
    start, end = date(year, 10, 1), date(year + 1, 4, 30)
    end = min(end, date.today())
    daily = await open_meteo.fetch_archive_daily_mean(client, lake.center.lat, lake.center.lon, start, end)
    temps = [ice.DayTemperature(d, t) for d, t in daily]
    days = ice.simulate(temps, start, lake.mean_depth_m).days
    count = {s: sum(d.status == s for d in days) for s in (ice.EDGES, ice.FORMING, ice.FROZEN)}
    frozen = [d.day for d in days if d.status == ice.FROZEN]
    thickest = max((d.thickness_cm for d in days), default=0)
    coldest = min((t.mean_c for t in temps), default=float("nan"))
    span = f"{frozen[0]:%d.%m.}–{frozen[-1]:%d.%m.%Y}" if frozen else ""
    return (
        f"{year}/{(year + 1) % 100:02d}  edges {count[ice.EDGES]:3d}  forming {count[ice.FORMING]:3d}  "
        f"frozen {count[ice.FROZEN]:3d}  max {thickest:4.1f} cm  coldest day {coldest:5.1f} °C  {span}"
    )


async def main(first: int) -> int:
    locs = locations.load()
    lake_ids = list(dict.fromkeys([c.lake_id for c in locations.load(catalog_paths=()).clubs.values()] + EXTRA_LAKES))
    last = date.today().year - (1 if date.today().month < 10 else 0)
    report = []
    async with httpx.AsyncClient() as client:
        for lake_id in lake_ids:
            lake = locs.lakes.get(lake_id)
            if lake is None:
                continue
            depth = f"{lake.mean_depth_m} m" if lake.mean_depth_m else f"unknown, taken as {ice.DEFAULT_DEPTH_M} m"
            report.append(f"## {lake.name} (mean depth {depth})")
            for year in range(first, last):
                try:
                    report.append(await winter(client, lake, year))
                except httpx.HTTPError as e:
                    report.append(f"{year}: archive unavailable ({e!r})")
            report.append("")
    text = "\n".join(report)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### Ice model on past winters\n```\n" + text + "\n```\n")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main(int(sys.argv[1]) if len(sys.argv) > 1 else 2005)))
