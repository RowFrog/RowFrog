#!/usr/bin/env python3
"""The river gauge (water level, discharge) for every river club, for the
Current tile: data/river-gauges.json.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/river_gauge_survey.py [--write]

PEGELONLINE (Wasserstraßen- und Schifffahrtsverwaltung des Bundes, DL-DE
Zero 2.0) lists the gauges on the federal waterways with their series (W
water level in cm, Q discharge in m³/s, VA flow speed in m/s) and their
characteristic values (MW mean water, MHW mean high water, HSW the level at
which shipping stops, MQ mean discharge ...). A gauge counts for a club when
it is on the club's river (by name) within MAX_KM of the launch point and has
a water level series; the nearest one wins. Swiss and Austrian clubs have no
gauge here yet.

With --write, data/river-gauges.json is rewritten; the "River gauges"
workflow commits it to the branch it runs on.
"""

from __future__ import annotations

import json
import math
import re
import sys
import unicodedata
from pathlib import Path

import httpx

from rowfrog import locations

PEGELONLINE = "https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations.json"
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; RowFrog/0.1; +https://github.com/RowFrog/RowFrog)"}
MAX_KM = 15.0
PATH = Path(__file__).resolve().parents[1] / "data" / "river-gauges.json"


def norm(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.upper().replace("ß", "SS")).encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Z0-9]+", " ", text).strip()


def same_river(water: str, gauge_water: str) -> bool:
    """"Main" and "MAIN", "Dortmund-Ems-Kanal" and "DORTMUND-EMS-KANAL", "Oder/Odra" and "ODER"."""
    a, b = norm(water), norm(gauge_water)
    if not a or not b:
        return False
    return a == b or a.split()[0] == b.split()[0]


def km(a: tuple[float, float], b: tuple[float, float]) -> float:
    dy = math.radians(b[0] - a[0]) * 6371
    dx = math.radians(b[1] - a[1]) * 6371 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)


def gauge_entry(s: dict, distance: float) -> dict:
    series = {t["shortname"]: t for t in s.get("timeseries", [])}
    values = {}
    for name, t in series.items():
        chars = {c["shortname"]: c["value"] for c in t.get("characteristicValues") or [] if c.get("value") is not None}
        if chars:
            values[name] = chars
    return {
        "network": "pegelonline",
        "id": s["uuid"],
        "name": s.get("longname", "").title(),
        "water": (s.get("water") or {}).get("longname", "").title(),
        "riverKm": s.get("km"),
        "lat": s["latitude"],
        "lon": s["longitude"],
        "distanceKm": round(distance, 1),
        "series": sorted(k for k in series if k in ("W", "Q", "VA")),
        "values": values,
    }


def main() -> int:
    write = "--write" in sys.argv
    resp = httpx.get(PEGELONLINE, params={"includeTimeseries": "true", "includeCharacteristicValues": "true"}, headers=HEADERS, timeout=120)
    resp.raise_for_status()
    stations = [s for s in resp.json() if s.get("latitude") and any(t["shortname"] == "W" for t in s.get("timeseries", []))]
    print(f"{len(stations)} PEGELONLINE gauges with a water level")
    locs = locations.load()
    found, missing = {}, []
    for club in sorted(locs.clubs.values(), key=lambda c: c.id):
        lake = locs.lakes[club.lake_id]
        if lake.kind != "river" or club.country != "de":
            continue
        water = lake.name
        at = (club.launch_point.lat, club.launch_point.lon)
        near = sorted(
            (km(at, (s["latitude"], s["longitude"])), s) for s in stations if same_river(water, (s.get("water") or {}).get("longname", ""))
        )
        near = [(d, s) for d, s in near if d <= MAX_KM]
        if not near:
            missing.append(f"{club.id} ({water})")
            continue
        d, s = near[0]
        found[club.id] = gauge_entry(s, d)
        e = found[club.id]
        print(f"  {club.id} ({water}): {e['name']} {e['distanceKm']} km, {e['series']}, HSW {e['values'].get('W', {}).get('HSW')}")
    with_q = sum("Q" in e["series"] for e in found.values())
    with_hsw = sum("HSW" in e["values"].get("W", {}) for e in found.values())
    print(f"{len(found)} river clubs with a gauge ({with_q} with discharge, {with_hsw} with HSW); {len(missing)} without:")
    for m in missing:
        print("  no gauge:", m)
    if write:
        PATH.write_text(json.dumps({
            "about": "River gauge per river club, written by scripts/river_gauge_survey.py --write: the nearest PEGELONLINE gauge "
                     f"with a water level on the club's river within {MAX_KM:g} km. values: the gauge's characteristic values per "
                     "series (W in cm, Q in m³/s). Data: WSV PEGELONLINE, DL-DE Zero 2.0.",
            "clubs": found,
        }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"wrote {PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
