#!/usr/bin/env python3
"""Research only: what river gauges and flow forecasts could tell a river club.

1. PEGELONLINE (WSV): for every German river club, the nearest federal gauge
   on its river within 15 km, which series it has (W water level, Q
   discharge, VA flow speed, WT temperature) and its characteristic values
   (MW, MQ, HSW = shipping stops), with the latest reading.
2. Open-Meteo Flood API (GloFAS): daily discharge forecast and its long-term
   mean at a few launch points.
3. BAFU via api.existenz.ch: latest flow and level for Swiss river clubs.

Nothing is stored.
"""

from __future__ import annotations

import json
import math
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PEGEL = "https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations.json?includeTimeseries=true&includeCurrentMeasurement=true&includeCharacteristicValues=true"
FLOOD = "https://flood-api.open-meteo.com/v1/flood?latitude={lat}&longitude={lon}&daily=river_discharge,river_discharge_mean,river_discharge_max&forecast_days=7"


def get(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "RowFrog/0.1 (research)"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def km(a, b) -> float:
    dy = math.radians(b[0] - a[0]) * 6371
    dx = math.radians(b[1] - a[1]) * 6371 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)


def river_clubs() -> list[tuple[str, str, str, float, float]]:
    out = []
    for f in sorted((ROOT / "data" / "catalogs").glob("*-*.json")):
        if f.name == "water-fixes.json":
            continue
        d = json.loads(f.read_text())
        names = {l["id"]: l["name"] for l in d["lakes"]}
        for c in d["clubs"]:
            if c["lakeId"].startswith("river-"):
                lp = c["launchPoint"]
                out.append((c["country"], c["id"], names.get(c["lakeId"], c["lakeId"]), lp["lat"], lp["lon"]))
    return out


def norm(s: str) -> str:
    return s.upper().replace("Ä", "AE").replace("Ö", "OE").replace("Ü", "UE").replace("ß", "SS").replace("-", " ")


def main() -> None:
    clubs = river_clubs()
    print(f"{len(clubs)} river clubs", flush=True)
    stations = get(PEGEL)
    print(f"{len(stations)} PEGELONLINE gauges", flush=True)
    counts = {"gauge": 0, "W": 0, "Q": 0, "VA": 0, "HSW": 0, "MQ": 0}
    de = [c for c in clubs if c[0] == "de"]
    examples = 0
    for _, cid, water, lat, lon in de:
        cands = [
            (km((lat, lon), (s["latitude"], s["longitude"])), s)
            for s in stations
            if s.get("latitude") and norm(water).split()[0] in norm(s.get("water", {}).get("longname", ""))
        ]
        cands = sorted([c for c in cands if c[0] <= 15], key=lambda c: c[0])
        if not cands:
            continue
        dist, s = cands[0]
        counts["gauge"] += 1
        series = {t["shortname"]: t for t in s.get("timeseries", [])}
        for k in ("W", "Q", "VA"):
            counts[k] += k in series
        chars = {c["shortname"]: c.get("value") for t in s.get("timeseries", []) for c in t.get("characteristicValues", []) or []}
        counts["HSW"] += "HSW" in chars
        counts["MQ"] += "MQ" in chars
        if examples < 25:
            examples += 1
            cur = {k: (series[k].get("currentMeasurement") or {}).get("value") for k in series}
            print(f"  {cid} ({water}): {s['longname']} {dist:.1f} km, series {sorted(series)}, now {cur}, values {chars}", flush=True)
    print(f"German river clubs: {len(de)}; with a federal gauge on their river within 15 km: {counts}", flush=True)

    for _, cid, water, lat, lon in [c for c in clubs if c[1] in (
        "frankfurter-rudergesellschaft-germania-1869", "heidelberger-ruderklub-1872", "giessener-rudergesellschaft-1877",
        "koelner-ruderverein-von-1877", "askoe-ruderverein-donau-linz", "ruderclub-baden", "passauer-ruderverein-von-1874")]:
        try:
            d = get(FLOOD.format(lat=lat, lon=lon))["daily"]
            print(f"  flood {cid} ({water}): Q {d['river_discharge']} mean {d['river_discharge_mean'][:2]} max {d['river_discharge_max'][:2]}", flush=True)
        except Exception as e:
            print(f"  flood {cid}: {e!r}", flush=True)

    ch = [c for c in clubs if c[0] == "ch"]
    try:
        locs = get("https://api.existenz.ch/apiv1/hydro/locations?app=rowfrog")["payload"]
        for _, cid, water, lat, lon in ch:
            near = sorted(
                (km((lat, lon), (v["details"]["lat"], v["details"]["lon"])), k, v["details"].get("name"), v["details"].get("water-body-name"))
                for k, v in locs.items()
                if v.get("details", {}).get("lat")
            )[:1]
            print(f"  CH {cid} ({water}): nearest BAFU {near}", flush=True)
        latest = get("https://api.existenz.ch/apiv1/hydro/latest?app=rowfrog&parameters=flow,height")["payload"]
        print(f"  BAFU latest flow/height values: {len(latest)}", flush=True)
    except Exception as e:
        print(f"  BAFU: {e!r}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
