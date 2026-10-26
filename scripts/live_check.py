#!/usr/bin/env python3
"""Check the backend and the club list against live data.

Usage (from the repository root, after `pip install -e backend`):
    python3 scripts/live_check.py

For every club in data/locations.json it prints:
  - where the launch point sits relative to the OSM shoreline (in the water,
    on land, distance to the nearest shore point),
  - rowing-related OSM features within 1.5 km (boathouses tagged
    sport=rowing, slipways), as candidates for a better launch point,
  - a summary of the live forecast from GET /clubs/<id>/forecast,
  - a summary of the lake view from GET /lakes/<id>/view.

The report is printed and, on GitHub Actions, added to the job summary.
Nothing is written to the data files; corrections are made by hand.
"""

from __future__ import annotations

import json
import math
import os
import sys
import time
from pathlib import Path

from fastapi.testclient import TestClient

from rowfrog import locations, outlines
from rowfrog.api import app
from rowfrog.waves import EARTH_RADIUS_M, _to_local_m

from fetch_lake_outline import overpass


def nearest_shore(lon: float, lat: float, rings) -> tuple[float, float, float]:
    """Distance in metres to the nearest ring edge, and that point as (lon, lat)."""
    best = (math.inf, lon, lat)
    for ring in rings:
        pts = [_to_local_m(x, y, lon, lat) for x, y in ring]
        for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
            ex, ey = x2 - x1, y2 - y1
            length2 = ex * ex + ey * ey
            t = 0.0 if length2 == 0 else max(0.0, min(1.0, -(x1 * ex + y1 * ey) / length2))
            px, py = x1 + t * ex, y1 + t * ey
            d = math.hypot(px, py)
            if d < best[0]:
                plat = lat + math.degrees(py / EARTH_RADIUS_M)
                plon = lon + math.degrees(px / (EARTH_RADIUS_M * math.cos(math.radians(lat))))
                best = (d, plon, plat)
    return best


def in_water(lon: float, lat: float, rings) -> bool:
    """Even-odd rule over all rings, so a point on an island counts as land."""
    inside = False
    for ring in rings:
        for (x1, y1), (x2, y2) in zip(ring, list(ring[1:]) + [ring[0]]):
            if (y1 > lat) != (y2 > lat) and lon < x1 + (lat - y1) * (x2 - x1) / (y2 - y1):
                inside = not inside
    return inside


def rowing_features(lat: float, lon: float) -> list[dict]:
    q = f"""
    [out:json][timeout:60];
    (
      nwr["sport"="rowing"](around:1500,{lat},{lon});
      nwr["leisure"="slipway"](around:1500,{lat},{lon});
    );
    out center tags;
    """
    elements = overpass(q)["elements"]
    found = []
    for e in elements:
        c = e.get("center") or {"lat": e.get("lat"), "lon": e.get("lon")}
        if c["lat"] is None:
            continue
        x, y = _to_local_m(c["lon"], c["lat"], lon, lat)
        tags = e.get("tags", {})
        found.append(
            {
                "osm": f"{e['type']}/{e['id']}",
                "name": tags.get("name", ""),
                "kind": "slipway" if tags.get("leisure") == "slipway" else "rowing",
                "lat": round(c["lat"], 5),
                "lon": round(c["lon"], 5),
                "distanceM": round(math.hypot(x, y)),
            }
        )
    return sorted(found, key=lambda f: f["distanceM"])


def forecast_summary(client: TestClient, club_id: str) -> list[str]:
    try:
        resp = client.get(f"/clubs/{club_id}/forecast")
        if resp.status_code == 503:  # Open-Meteo sometimes refuses for a moment
            time.sleep(20)
            resp = client.get(f"/clubs/{club_id}/forecast")
    except Exception as e:  # the server's own exception, so the report says what broke
        return [f"forecast: HTTP 500 {type(e).__name__}: {e}"]
    if resp.status_code != 200:
        return [f"forecast: HTTP {resp.status_code} {resp.text[:200]}"]
    body = resp.json()
    hours = body["hours"]
    lines = [f"forecast: {len(hours)} hours, water temperature {body['waterTemperature']}"]
    ice = dict(body.get("ice") or {})
    lines.append(f"ice: {ice.pop('status', None)}, {ice.pop('days', [])[:3]} ..., {ice}")
    for h in hours[:24:3]:
        lines.append(
            f"  {h['time']}  {h['light']:6}  wind {h['windSpeedMs']} m/s gust {h['windGustMs']} "
            f"from {h['windFromDeg']}°  waves {h['waveHeightM']} m  fetch {h['fetchM']} m  "
            f"vis {h['visibilityM']} m  {h['temperatureC']} °C"
        )
    history = (body["waterTemperature"] or {}).get("history") or []
    lines.append(f"  water history: {len(history)} hours" + (f" from {history[0]['time']}" if history else ""))
    outlook = body.get("outlook")
    if outlook is None:
        lines.append("  outlook: missing")
    else:
        uv = [h["uvIndex"] for h in outlook if h.get("uvIndex") is not None]
        layers = sum(1 for h in outlook if h.get("cloudCoverHighPct") is not None)
        lines.append(
            f"  outlook: {len(outlook)} hours from {outlook[0]['time']} to {outlook[-1]['time']}, "
            f"UV in {len(uv)} hours (max {max(uv) if uv else None}), cloud layers in {layers} hours"
        )
    return lines


def lake_view_summary(client: TestClient, lake_id: str) -> list[str]:
    try:
        resp = client.get(f"/lakes/{lake_id}/view")
        if resp.status_code == 503:  # Open-Meteo sometimes refuses for a moment
            time.sleep(20)
            resp = client.get(f"/lakes/{lake_id}/view")
    except Exception as e:
        return [f"lake view: HTTP 500 {type(e).__name__}: {e}"]
    if resp.status_code != 200:
        return [f"lake view: HTTP {resp.status_code} {resp.text[:200]}"]
    body = resp.json()
    lines = [
        f"lake view: {len(body['grid']['cells'])} cells of {body['grid']['cellM']} m, "
        f"{len(body['points'])} forecast points, {len(body['hours'])} hours, zones {body['zones']}"
    ]
    for h in body["hours"][:24:3]:
        counts = {c: h["lights"].count(c) for c in "012"}
        winds = [w["speedMs"] for w in h["wind"] if w["speedMs"] is not None]
        lines.append(
            f"  {h['time']}  green/amber/red cells {counts['0']}/{counts['1']}/{counts['2']}  "
            f"waves up to {max(h['wavesCm'], default=0)} cm  wind {min(winds, default=None)}-{max(winds, default=None)} m/s  "
            f"lake wide {h['lakeWide']['light']}  zones {[z['light'] for z in h['zones']]}"
        )
    return lines


def main() -> int:
    locs = locations.load(catalog_paths=())  # the confirmed clubs; catalog clubs are unconfirmed by design
    client = TestClient(app)
    report: list[str] = []
    ok = True
    for club in locs.clubs.values():
        p = club.launch_point
        report.append(f"## {club.name} ({club.id})")
        report.append(f"launch point: {p.lat}, {p.lon}")
        rings = outlines.load(club.lake_id)
        if rings is None:
            report.append("outline: missing")
            ok = False
        else:
            d, slon, slat = nearest_shore(p.lon, p.lat, rings)
            where = "in the water" if in_water(p.lon, p.lat, rings) else "on land"
            report.append(f"shore: {where}, {d:.0f} m from the nearest shore point ({slat:.5f}, {slon:.5f})")
        try:
            for f in rowing_features(p.lat, p.lon):
                report.append(f"  osm {f['kind']}: {f['name'] or '(no name)'} {f['osm']} at {f['lat']}, {f['lon']} ({f['distanceM']} m)")
        except OSError as e:
            report.append(f"  osm features: lookup failed ({e})")
        lines = forecast_summary(client, club.id)
        ok = ok and lines[0].startswith("forecast: ") and "HTTP" not in lines[0]
        report.extend(lines)
        report.append("")
    for lake_id in sorted({c.lake_id for c in locs.clubs.values()}):
        report.append(f"## Lake view {lake_id}")
        lines = lake_view_summary(client, lake_id)
        ok = ok and "HTTP" not in lines[0]
        report.extend(lines)
        report.append("")
    text = "\n".join(report)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        Path(summary).write_text("```\n" + text + "\n```\n", encoding="utf-8")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
