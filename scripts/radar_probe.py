#!/usr/bin/env python3
"""Check what DWD's rain radar layer offers at our launch points.

Usage: python3 scripts/radar_probe.py   (from the repository root)

Prints the TIME dimension of the WMS layer dwd:Niederschlagsradar (RV
product: radar now and nowcast up to 2 hours, every 5 minutes, mm/h) and a
GetFeatureInfo answer at each confirmed launch point for a few of those times,
to see whether the app can ask DWD for rain at a point directly.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone

import httpx

sys.path.insert(0, "backend")
from rowfrog import locations  # noqa: E402

WMS = "https://maps.dwd.de/geoserver/dwd/wms"
LAYER = "dwd:Niederschlagsradar"
report: list[str] = []


class RetryClient(httpx.Client):
    """Asks once more when DWD's server is slow or drops the connection, so one
    slow answer does not turn the whole check red."""

    def get(self, *args, **kwargs):  # type: ignore[override]
        try:
            return super().get(*args, **kwargs)
        except httpx.TransportError as e:
            print(f"  (retrying after {type(e).__name__})", flush=True)
            time.sleep(10)
            return super().get(*args, **kwargs)


def say(line: str = "") -> None:
    print(line, flush=True)
    report.append(line)


def params(lat: float, lon: float, when: str | None) -> dict[str, str]:
    d = 0.01
    out = {
        "SERVICE": "WMS",
        "VERSION": "1.3.0",
        "REQUEST": "GetFeatureInfo",
        "LAYERS": LAYER,
        "QUERY_LAYERS": LAYER,
        "CRS": "EPSG:4326",
        "BBOX": f"{lat - d},{lon - d},{lat + d},{lon + d}",
        "WIDTH": "101",
        "HEIGHT": "101",
        "I": "50",
        "J": "50",
        "INFO_FORMAT": "application/json",
    }
    if when:
        out["TIME"] = when
    return out


def main() -> int:
    with RetryClient(headers={"User-Agent": "RowFrog/0.1 (+https://github.com/RowFrog/RowFrog)"}) as client:
        caps = client.get(WMS, params={"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetCapabilities"}, timeout=60).text
        at = caps.find("<Name>Niederschlagsradar</Name>")
        block = caps[at : caps.find("</Layer>", at)] if at >= 0 else ""
        say(f"layer in capabilities: {at >= 0}")
        dimensions = re.findall(r"<Dimension[^>]*>([^<]*)</Dimension>", block)
        for d in dimensions:
            say(f"time dimension: {d[:200]} ... {d[-200:]}")
        # DWD's servers do not all list the same times: on 2026-11-03 some still
        # listed times up to 2026-10-28 while the readings were current. So the
        # list is only noted; the reading's own time decides.
        listed = layer_stale(at >= 0, dimensions)
        if listed:
            say(f"note: capabilities look old ({listed}); the reading below decides")
        club = next(iter(locations.load(catalog_paths=()).clubs.values()))
        p = club.launch_point
        say(f"## {club.short_name}")
        first = reading(client, p.lat, p.lon)
        if first is None:
            # Three tries over about 45 s without a reading: more than DWD's
            # occasional empty reply (2026-11-03).
            say("RADAR GIVES NO READING")
            write_summary()
            return 1
        props = first["features"][0]["properties"]
        say(f"  now: {props}")
        ref = datetime.fromisoformat(props["REFERENCE_TIME"].replace("Z", "+00:00"))
        stale = ref < datetime.now(timezone.utc) - timedelta(hours=1)
        if stale:
            say(f"RADAR LOOKS STOPPED: newest reading {ref:%Y-%m-%d %H:%M} UTC")
        for minutes in range(0, 135, 15):
            when = (ref + timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")
            resp = client.get(WMS, params=params(p.lat, p.lon, when), timeout=30)
            say(f"  +{minutes:3d} min {when}: HTTP {resp.status_code} {resp.text[:300]!r}")
        legend_and_region(client, p.lat, p.lon, ref)
    write_summary()
    return 1 if stale else 0


def layer_stale(listed: bool, dimensions: list[str]) -> str | None:
    """Why the capabilities look old, or None: the layer missing, or its newest
    time (radar plus 2 hours of nowcast) more than an hour ago."""
    if not listed:
        return "not in the capabilities"
    ends = [m for d in dimensions for m in re.findall(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d", d)]
    if not ends:
        return "no time dimension"
    newest = max(datetime.fromisoformat(e + "+00:00") for e in ends)
    if newest < datetime.now(timezone.utc) - timedelta(hours=1):
        return f"newest time {newest:%Y-%m-%d %H:%M} UTC"
    return None


def reading(client: RetryClient, lat: float, lon: float) -> dict | None:
    """The answer for now at a point, asked up to three times; None when DWD
    sends no JSON with a reading."""
    for attempt in range(1, 4):
        resp = client.get(WMS, params=params(lat, lon, None), timeout=30)
        try:
            body = json.loads(resp.text)
            body["features"][0]["properties"]["REFERENCE_TIME"]
            return body
        except (ValueError, KeyError, IndexError, TypeError):
            say(f"  no reading (attempt {attempt}): HTTP {resp.status_code} {resp.text[:300]!r}")
            time.sleep(15)
    return None


def write_summary() -> None:
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### DWD rain radar\n```\n" + "\n".join(report) + "\n```\n")


def legend_and_region(client: RetryClient, lat: float, lon: float, ref: datetime) -> None:
    """The layer's colours (for the app's legend) and how long one picture
    of the region the app's radar map loads per frame takes."""
    import math

    resp = client.get(WMS, params={"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetLegendGraphic",
                                   "LAYER": LAYER, "FORMAT": "application/json"}, timeout=30)
    say(f"## legend: HTTP {resp.status_code}")
    try:
        for legend in resp.json().get("Legend", []):
            for rule in legend.get("rules", []):
                for sym in rule.get("symbolizers", []):
                    raster = sym.get("Raster", {})
                    for entry in raster.get("colormap", {}).get("entries", []):
                        say(f"  colour {entry.get('color')} quantity {entry.get('quantity')} label {entry.get('label')} opacity {entry.get('opacity')}")
    except ValueError:
        say(f"  {resp.text[:1500]!r}")
    r = 6378137.0
    x = math.radians(lon) * r
    y = math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * r
    half = 300_000.0
    for minutes in (-60, 0, 60, 120):
        when = (ref + timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")
        started = time.monotonic()
        resp = client.get(WMS, params={
            "SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap", "LAYERS": LAYER, "STYLES": "",
            "CRS": "EPSG:3857", "BBOX": f"{x - half},{y - half},{x + half},{y + half}",
            "WIDTH": "1024", "HEIGHT": "1024", "FORMAT": "image/png", "TRANSPARENT": "TRUE", "TIME": when,
        }, timeout=60)
        say(f"  region {minutes:+4d} min: HTTP {resp.status_code} {resp.headers.get('content-type')} "
            f"{len(resp.content)} bytes in {time.monotonic() - started:.1f} s")


if __name__ == "__main__":
    sys.exit(main())
