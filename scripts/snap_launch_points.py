#!/usr/bin/env python3
"""Moves launch points that sit on the bank next to their own water onto its shore.

The imports place many launch points at the geocoded club address, a few
dozen metres inland of the water. For every catalog club whose launch point
lies outside its water's outline (data/outlines, river sections included) but
within SNAP_M of it, this moves the point to the nearest shore point. Points
further away are left alone: those are on the wrong water or need a look by
hand (the launch point audit, November 2026). Points checked by hand
(data/catalogs/hand-checked.json) are never moved. Needs no network.

    python3 scripts/snap_launch_points.py [--dry-run]

Run it after an import or a rebuild of the river sections; running it twice
changes nothing.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from live_check import in_water, nearest_shore
from rowfrog import locations, outlines

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ROOT / "data" / "catalogs"
FILES = ("de-drv", "de-osm", "at-oerv", "at-osm", "ch-osm", "ch-swissrowing")
SNAP_M = 150.0
# Closer than this counts as on the shore already.
ON_SHORE_M = 3.0


def main(dry_run: bool) -> int:
    loaded = locations.load()
    hand = json.loads((CATALOGS / "hand-checked.json").read_text(encoding="utf-8"))
    hand_ids = {i for cc, v in hand.items() if isinstance(v, dict) for i in v}
    rings_of: dict[str, list | None] = {}
    moved = far = 0
    for name in FILES:
        path = CATALOGS / f"{name}.json"
        catalog = json.loads(path.read_text(encoding="utf-8"))
        changed = False
        for club in catalog["clubs"]:
            loaded_club = loaded.clubs.get(club["id"])
            if loaded_club is None or club["id"] in hand_ids:
                continue  # left out as a duplicate, or checked by hand
            water = loaded_club.lake_id
            if water not in rings_of:
                rings_of[water] = outlines.load(water)
            rings = rings_of[water]
            if not rings:
                continue
            p = club["launchPoint"]
            if in_water(p["lon"], p["lat"], rings):
                continue
            d, lon, lat = nearest_shore(p["lon"], p["lat"], rings)
            if d <= ON_SHORE_M:
                continue
            if d > SNAP_M:
                far += 1
                print(f"left: {club['id']} is {d:.0f} m from {water}")
                continue
            water_name = loaded.lakes[water].name
            p.update({"lat": round(lat, 5), "lon": round(lon, 5),
                      "precision": f"shore of the {water_name} nearest the earlier point ({p['precision']}), {d:.0f} m away"})
            print(f"moved: {club['id']} {d:.0f} m onto {water}")
            moved += 1
            changed = True
        if changed and not dry_run:
            path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{moved} launch points moved onto their water's shore, {far} further than {SNAP_M:.0f} m left as they are")
    return 0


if __name__ == "__main__":
    sys.exit(main("--dry-run" in sys.argv))
