"""Puts clubs the import left under "Water near <town>" on their real water.

The water comes from data/catalogs/water-fixes.json, checked by hand (the
importers apply it too, on every run). With --snap, each such club's launch
point, which the import could only place at town level, moves to the nearest
shore of that water in OpenStreetMap within SNAP_M; that needs Overpass, so it
runs as the "Fix unknown waters" workflow.

    python scripts/fix_unknown_waters.py [--snap]
"""

from __future__ import annotations

import json
import sys
import time

from club_import import CATALOGS, WATER_FIXES, apply_water_fixes
from discover_clubs import _run, water_rings
from live_check import nearest_shore

FILES = ("de-drv", "de-osm", "at-oerv", "at-osm", "ch-swissrowing", "ch-osm")
SNAP_M = 6000.0


def shore_of(name: str, lat: float, lon: float) -> tuple[float, float, float] | None:
    """(distance, lat, lon) of the nearest shore or river line called `name` within SNAP_M."""
    quoted = name.replace('"', '\\"')
    elements = _run(
        f"""
        [out:json][timeout:120];
        (
          way(around:{SNAP_M:.0f},{lat},{lon})["natural"="water"]["name"="{quoted}"];
          rel(around:{SNAP_M:.0f},{lat},{lon})["natural"="water"]["name"="{quoted}"];
          way(around:{SNAP_M:.0f},{lat},{lon})["landuse"="reservoir"]["name"="{quoted}"];
          way(around:{SNAP_M:.0f},{lat},{lon})["waterway"~"^(river|canal)$"]["name"="{quoted}"];
        );
        out geom;
        """
    )
    best = None
    for e in elements:
        if "waterway" in e.get("tags", {}):
            rings = [[(p["lon"], p["lat"]) for p in e.get("geometry", [])]]
        else:
            try:
                rings = water_rings(e)
            except (ValueError, KeyError):
                continue
        d, slon, slat = nearest_shore(lon, lat, rings)
        if d <= SNAP_M and (best is None or d < best[0]):
            best = (d, slat, slon)
    return best


def main() -> int:
    snap = "--snap" in sys.argv
    fixes = json.loads(WATER_FIXES.read_text(encoding="utf-8"))
    for name in FILES:
        path = CATALOGS / f"{name}.json"
        catalog = json.loads(path.read_text(encoding="utf-8"))
        country = name.split("-")[0]
        moved = apply_water_fixes(country, catalog["lakes"], catalog["clubs"])
        snapped = 0
        if snap:
            waters = {w["id"]: w for w in catalog["lakes"]}
            for club in catalog["clubs"]:
                point = club["launchPoint"]
                if club["id"] not in fixes.get(country, {}) or "checked by hand" not in point["precision"]:
                    continue
                water = waters[club["lakeId"]]["name"]
                try:
                    found = shore_of(water, point["lat"], point["lon"])
                except OSError as err:
                    print(f"  {club['id']}: Overpass failed ({err}), kept")
                    continue
                time.sleep(2)
                if found is None:
                    print(f"  {club['id']}: no {water} within {SNAP_M:.0f} m, kept")
                    continue
                d, lat, lon = found
                club["launchPoint"] = {
                    "lat": round(lat, 5), "lon": round(lon, 5),
                    "precision": f"shore of the {water} nearest the town-level address, {d:.0f} m away (water checked by hand)",
                    "verified": False,
                }
                snapped += 1
                print(f"  {club['id']}: {water}, {d:.0f} m")
        catalog["lakes"].sort(key=lambda l: l["name"])
        path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        left = sum(1 for w in catalog["lakes"] if w.get("kind") == "unknown")
        print(f"{name}: {moved} clubs moved to their water, {snapped} launch points snapped, {left} waters still unknown")
    return 0


if __name__ == "__main__":
    sys.exit(main())
