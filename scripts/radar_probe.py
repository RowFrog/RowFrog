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
from datetime import datetime, timedelta

import httpx

sys.path.insert(0, "backend")
from rowfrog import locations  # noqa: E402

WMS = "https://maps.dwd.de/geoserver/dwd/wms"
LAYER = "dwd:Niederschlagsradar"
report: list[str] = []


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
    with httpx.Client(headers={"User-Agent": "RowFrog/0.1 (+https://github.com/RowFrog/RowFrog)"}) as client:
        caps = client.get(WMS, params={"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetCapabilities"}, timeout=60).text
        at = caps.find("<Name>Niederschlagsradar</Name>")
        block = caps[at : caps.find("</Layer>", at)] if at >= 0 else ""
        say(f"layer in capabilities: {at >= 0}")
        for d in re.findall(r"<Dimension[^>]*>([^<]*)</Dimension>", block):
            say(f"time dimension: {d[:200]} ... {d[-200:]}")
        club = next(iter(locations.load(catalog_paths=()).clubs.values()))
        p = club.launch_point
        say(f"## {club.short_name}")
        first = json.loads(client.get(WMS, params=params(p.lat, p.lon, None)).text)
        props = first["features"][0]["properties"]
        say(f"  now: {props}")
        ref = datetime.fromisoformat(props["REFERENCE_TIME"].replace("Z", "+00:00"))
        for minutes in range(0, 135, 15):
            when = (ref + timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")
            resp = client.get(WMS, params=params(p.lat, p.lon, when), timeout=30)
            say(f"  +{minutes:3d} min {when}: HTTP {resp.status_code} {resp.text[:300]!r}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### DWD rain radar\n```\n" + "\n".join(report) + "\n```\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
