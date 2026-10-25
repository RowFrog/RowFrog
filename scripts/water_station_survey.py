#!/usr/bin/env python3
"""Find the nearest water temperature station for every club's water.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/water_station_survey.py [OUT.json]

Station lists, all public and free:
  - GKD Bayern lake and river stations (www.gkd.bayern.de, CC BY 4.0), from
    the map data on the overview pages,
  - PEGELONLINE (Wasserstraßen- und Schifffahrtsverwaltung des Bundes, DL-DE
    Zero 2.0): gauges on federal waterways with a water temperature series (WT),
  - Swiss federal hydrology (BAFU / FOEN) stations with a water temperature,
    via api.existenz.ch, which mirrors the official hydrodaten.admin.ch feed.
A station counts for a club when it is on the same water (by name, or for a
lake inside its outline) and, of those, it is the nearest to the club's
launch point; a station further than MAX_KM away is still listed, marked
far. The report goes to the log and the job summary; with OUT.json the
matches are also written as JSON.
"""

from __future__ import annotations

import json
import math
import os
import re
import sys
import unicodedata
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone

import httpx

from rowfrog import locations, outlines

GKD = "https://www.gkd.bayern.de/de/{kind}/wassertemperatur/bayern"
PEGELONLINE = "https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations.json"
EXISTENZ = "https://api.existenz.ch/apiv1/hydro/locations"
EXISTENZ_LATEST = "https://api.existenz.ch/apiv1/hydro/latest"
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; RowFrog/0.1; +https://github.com/RowFrog/RowFrog)"}
# A station on the same river further than this from the launch point is listed as far.
MAX_KM = {"lake": 25.0, "river": 30.0, "unknown": 15.0}
# A station whose newest value is older than this has stopped (or is out for the winter) and is skipped.
STALE = timedelta(days=3)
# Without a name match, a station this close to the launch point is taken as on the same water.
NEAR_KM = 1.0

out: list[str] = []


def say(line: str = "") -> None:
    print(line, flush=True)
    out.append(line)


@dataclass(frozen=True)
class Station:
    network: str  # "gkd", "pegelonline", "bafu"
    id: str  # GKD page slug, PEGELONLINE uuid or BAFU number
    name: str
    water: str
    lat: float
    lon: float
    kind: str  # "lake" or "river"
    latest: str | None = None


def fresh(s: "Station", now: datetime) -> bool:
    """Whether the station's newest value is recent; unknown counts as recent."""
    if not s.latest:
        return True
    try:
        t = datetime.strptime(s.latest, "%d.%m.%Y %H:%M").replace(tzinfo=timezone(timedelta(hours=1)))
    except ValueError:
        try:
            t = datetime.fromisoformat(s.latest)
        except ValueError:
            return True
    return now - t <= STALE


def norm(name: str) -> str:
    """Water names compared without case, accents, articles and lake/river words."""
    s = unicodedata.normalize("NFKD", name.lower()).encode("ascii", "ignore").decode()
    s = s.replace("ß", "ss")
    s = re.sub(r"\b(der|die|das|lac|lago|de|du|le|la|grosser|kleiner|gr|kl)\b", " ", s)
    s = re.sub(r"(see|seen|sees|weiher|teich|stausee|speicher|kanal|canal|wasserstrasse)\b", "", s)
    s = re.sub(r"[^a-z]", "", s)
    return s


def km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    dy = math.radians(lat2 - lat1) * 6371
    dx = math.radians(lon2 - lon1) * 6371 * math.cos(math.radians(lat1))
    return math.hypot(dx, dy)


def gkd(client: httpx.Client) -> list[Station]:
    found = []
    for kind, path in (("lake", "seen"), ("river", "fluesse")):
        page = client.get(GKD.format(kind=path), timeout=60).text
        start = page.find('{"pointer":')
        if start < 0:
            say(f"GKD {path}: no map data")
            continue
        data, _ = json.JSONDecoder().raw_decode(page[start:])
        for p in data["pointer"]:
            slug = p["uri"].rstrip("/").split("/")[-2] if p["uri"].endswith("messwerte") else p["uri"].rstrip("/").split("/")[-1]
            found.append(Station("gkd", slug, p["n"], p.get("g") or p["n"], float(p["lat"]), float(p["lon"]), kind, p.get("d")))
    say(f"GKD Bayern: {len(found)} stations")
    return found


def pegelonline(client: httpx.Client) -> list[Station]:
    resp = client.get(PEGELONLINE, params={"includeTimeseries": "true", "includeCurrentMeasurement": "true"}, timeout=90)
    resp.raise_for_status()
    found = []
    for s in resp.json():
        series = [t for t in s.get("timeseries", []) if t.get("shortname") == "WT"]
        if not series or s.get("latitude") is None:
            continue
        current = series[0].get("currentMeasurement") or {}
        water = (s.get("water") or {}).get("longname", "")
        found.append(Station("pegelonline", s["uuid"], s["longname"], water, s["latitude"], s["longitude"], "river", current.get("timestamp")))
    say(f"PEGELONLINE: {len(found)} gauges with water temperature")
    return found


def bafu(client: httpx.Client) -> list[Station]:
    locs = client.get(EXISTENZ, params={"app": "rowfrog"}, timeout=60)
    locs.raise_for_status()
    places = locs.json().get("payload", {})
    latest = client.get(EXISTENZ_LATEST, params={"app": "rowfrog", "parameters": "temperature"}, timeout=60)
    latest.raise_for_status()
    found = []
    for v in latest.json().get("payload", []):
        if v.get("par") != "temperature":
            continue
        loc = places.get(str(v.get("loc")), {})
        details = loc.get("details", loc)
        if details.get("lat") is None:
            continue
        kind = "lake" if str(details.get("water-body-type", "")).lower() == "lake" else "river"
        when = datetime.fromtimestamp(v["timestamp"], timezone.utc).isoformat() if v.get("timestamp") else None
        found.append(Station("bafu", str(v["loc"]), details.get("name", ""), details.get("water-body-name", ""), float(details["lat"]), float(details["lon"]), kind, when))
    say(f"BAFU (Switzerland): {len(found)} stations with water temperature")
    return found


def main(path: str | None) -> int:
    data = locations.load()
    stations: list[Station] = []
    with httpx.Client(headers=HEADERS, follow_redirects=True) as client:
        for fetch in (gkd, pegelonline, bafu):
            try:
                stations += fetch(client)
            except Exception as e:  # noqa: BLE001 - one network failing still leaves the others
                say(f"{fetch.__name__}: {e!r}")
    now = datetime.now(timezone.utc)
    stale = [s for s in stations if not fresh(s, now)]
    say(f"Skipped as stopped (newest value older than {STALE.days} days): {len(stale)} — " + ", ".join(f"{s.network}:{s.name} ({s.latest})" for s in stale[:40]))
    stations = [s for s in stations if fresh(s, now)]
    rings = {lake_id: (outlines.load(lake_id) or [None])[0] for lake_id in data.lakes}

    rows = []
    for lake_id, lake in sorted(data.lakes.items(), key=lambda kv: (kv[1].country, kv[1].name)):
        clubs = data.clubs_on(lake_id)
        if not clubs:
            continue
        ring = rings.get(lake_id)
        key = norm(lake.name)
        on_water = []
        for s in stations:
            last_word = norm(re.split(r"[\s/-]+", s.water.strip())[-1]) if s.water.strip() else ""
            same_name = len(key) >= 4 and (
                norm(s.water) == key
                or last_word == key  # "Potsdamer Havel" is on the Havel
                or (s.kind == "lake" and norm(s.name).startswith(key))  # GKD lake stations named after the lake
            )
            inside = ring is not None and lake.kind == "lake" and _inside(s.lon, s.lat, ring)
            # A river station next to a lake measures the river, so nearness only counts for the same kind of water.
            near = lake.kind in (s.kind, "unknown") and any(km(c.launch_point.lat, c.launch_point.lon, s.lat, s.lon) <= NEAR_KM for c in clubs)
            if same_name or inside or near:
                on_water.append(s)
        for club in clubs:
            best = min(on_water, key=lambda s: km(club.launch_point.lat, club.launch_point.lon, s.lat, s.lon), default=None)
            d = None if best is None else round(km(club.launch_point.lat, club.launch_point.lon, best.lat, best.lon), 1)
            rows.append(
                {
                    "country": lake.country,
                    "water": lake.name,
                    "waterId": lake_id,
                    "kind": lake.kind,
                    "club": club.id,
                    "clubName": club.short_name or club.name,
                    "station": None if best is None else asdict(best),
                    "distanceKm": d,
                    "far": d is not None and d > MAX_KM.get(lake.kind, 15.0),
                    "inData": lake.gkd_water_temperature_station,
                }
            )

    waters = {}
    for r in rows:
        w = waters.setdefault(r["waterId"], {"country": r["country"], "water": r["water"], "kind": r["kind"], "clubs": 0, "with": 0, "stations": set()})
        w["clubs"] += 1
        if r["station"] and not r["far"]:
            w["with"] += 1
            w["stations"].add(f"{r['station']['network']}:{r['station']['name']}")
    say()
    say("## Waters with clubs")
    say("| Country | Water | Kind | Clubs | Clubs with a station | Stations used |")
    say("| --- | --- | --- | --- | --- | --- |")
    for w in waters.values():
        say(f"| {w['country']} | {w['water']} | {w['kind']} | {w['clubs']} | {w['with']} | {', '.join(sorted(w['stations']))} |")
    total = len(rows)
    covered = sum(1 for r in rows if r["station"] and not r["far"])
    say()
    say(f"Clubs with a station on their water: {covered} of {total}; waters: {sum(1 for w in waters.values() if w['with'])} of {len(waters)}")
    say()
    say("## Stations (TSV)")
    for st in stations:
        say("\t".join(str(x) for x in ("STATION", st.network, st.id, st.name, st.water, st.kind, st.lat, st.lon, st.latest)))
    say()
    say("## Per club (TSV)")
    for r in rows:
        s = r["station"] or {}
        say("\t".join(str(x) for x in ("CLUB", r["country"], r["waterId"], r["kind"], r["club"], s.get("network", "-"), s.get("id", "-"), s.get("name", "-"), s.get("water", "-"), r["distanceKm"], "far" if r["far"] else "", s.get("latest", ""))))
    if path:
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"stations": [asdict(s) for s in stations], "clubs": rows}, f, ensure_ascii=False, indent=1)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
    return 0


def _inside(x: float, y: float, ring: list[tuple[float, float]]) -> bool:
    hit = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else None))
