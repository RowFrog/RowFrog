"""Puts clubs the import left under "Water near <town>" on their real water.

The water comes from data/catalogs/water-fixes.json, checked by hand (the
importers apply it too, on every run). With --snap, each such club's launch
point, which the import could only place at town level, moves to the nearest
shore of that water in OpenStreetMap within SNAP_M; that needs Overpass, so it
runs as the "Fix unknown waters" workflow. Only the water near each club is
fetched (big rivers like the Rhein are huge relations), the catalog is saved
after every club, and a run stops after SNAP_BUDGET_S, so running it again
carries on with the clubs not yet snapped. Catalogs and clubs go in random
order and the server that answered last is asked first, so a busy server or a
club whose lookup keeps failing does not use up every run on the same clubs.

    python scripts/fix_unknown_waters.py [--snap]
"""

from __future__ import annotations

import json
import math
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from club_import import CATALOGS, WATER_FIXES, apply_water_fixes
from fetch_lake_outline import OVERPASS_SERVERS
from live_check import nearest_shore

FILES = ("de-drv", "de-osm", "at-oerv", "at-osm", "ch-swissrowing", "ch-osm")
SNAP_M = 6000.0
SNAP_BUDGET_S = 45 * 60


_servers = list(OVERPASS_SERVERS)


def overpass(q: str, timeout: float) -> dict:
    """Asks each server once, the one that answered last first."""
    data = urllib.parse.urlencode({"data": q}).encode()
    errors = []
    for url in list(_servers):
        req = urllib.request.Request(url, data=data, headers={"User-Agent": "RowFrog/0.1"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                result = json.load(resp)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            errors.append(f"{url}: {e}")
            continue
        _servers.remove(url)
        _servers.insert(0, url)
        return result
    raise OSError("all Overpass servers failed: " + "; ".join(errors))


def lines(e: dict) -> list[list[tuple[float, float]]]:
    """The element's geometry as (lon, lat) polylines; clipping leaves gaps (None)."""
    parts = [e.get("geometry") or []] if e["type"] == "way" else [m.get("geometry") or [] for m in e.get("members", [])]
    out = []
    for geometry in parts:
        line = []
        for p in geometry + [None]:
            if p:
                line.append((p["lon"], p["lat"]))
            elif line:
                out.append(line)
                line = []
    return out


def shore_of(name: str, lat: float, lon: float) -> tuple[float, float, float] | None:
    """(distance, lat, lon) of the nearest shore or river line called `name` within SNAP_M."""
    quoted = name.replace('"', '\\"')
    dlat = SNAP_M / 111_000 * 1.1
    dlon = dlat / max(0.2, math.cos(math.radians(lat)))
    result = overpass(
        f"""
        [out:json][timeout:90];
        (
          way(around:{SNAP_M:.0f},{lat},{lon})["natural"="water"]["name"="{quoted}"];
          rel(around:{SNAP_M:.0f},{lat},{lon})["natural"="water"]["name"="{quoted}"];
          way(around:{SNAP_M:.0f},{lat},{lon})["landuse"="reservoir"]["name"="{quoted}"];
          way(around:{SNAP_M:.0f},{lat},{lon})["waterway"~"^(river|canal)$"]["name"="{quoted}"];
        );
        out geom({lat - dlat:.5f},{lon - dlon:.5f},{lat + dlat:.5f},{lon + dlon:.5f});
        """,
        timeout=100,
    )
    if "remark" in result:  # Overpass reports timeouts here, with a partial result
        raise OSError(f"Overpass: {result['remark']}")
    elements = result["elements"]
    best = None
    for e in elements:
        for line in lines(e):
            # Each segment on its own, so an open line is not closed back on itself.
            for a, b in zip(line, line[1:] or line):
                d, slon, slat = nearest_shore(lon, lat, [[a, b]])
                if d <= SNAP_M and (best is None or d < best[0]):
                    best = (d, slat, slon)
    return best


def save(path, catalog) -> None:
    catalog["lakes"].sort(key=lambda l: l["name"])
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    snap = "--snap" in sys.argv
    fixes = json.loads(WATER_FIXES.read_text(encoding="utf-8"))
    deadline = time.monotonic() + SNAP_BUDGET_S
    out_of_time = False
    for name in random.sample(FILES, len(FILES)):
        path = CATALOGS / f"{name}.json"
        catalog = json.loads(path.read_text(encoding="utf-8"))
        country = name.split("-")[0]
        moved = apply_water_fixes(country, catalog["lakes"], catalog["clubs"])
        snapped = 0
        if snap:
            waters = {w["id"]: w for w in catalog["lakes"]}
            for club in random.sample(catalog["clubs"], len(catalog["clubs"])):
                point = club["launchPoint"]
                if club["id"] not in fixes.get(country, {}) or "checked by hand" not in point["precision"]:
                    continue
                if point["precision"].startswith("shore of"):
                    continue  # snapped by an earlier run
                if time.monotonic() > deadline:
                    out_of_time = True
                    break
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
                save(path, catalog)
                print(f"  {club['id']}: {water}, {d:.0f} m")
        save(path, catalog)
        left = sum(1 for w in catalog["lakes"] if w.get("kind") == "unknown")
        print(f"{name}: {moved} clubs moved to their water, {snapped} launch points snapped, {left} waters still unknown")
    if out_of_time:
        print(f"Stopped after {SNAP_BUDGET_S // 60} minutes; run the workflow again for the clubs not yet snapped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
