#!/usr/bin/env python3
"""Check what DWD's rain radar layer offers at our launch points.

Usage: python3 scripts/radar_probe.py   (from the repository root)

Prints the TIME dimension of the WMS layer dwd:Niederschlagsradar (RV
product: radar now and nowcast up to 2 hours, every 5 minutes, mm/h) and a
GetFeatureInfo answer at each confirmed launch point for a few of those times,
to see whether the app can ask DWD for rain at a point directly.
"""

from __future__ import annotations

import os
import re
import sys

import httpx

sys.path.insert(0, "backend")
from rowerweather import locations  # noqa: E402

WMS = "https://maps.dwd.de/geoserver/dwd/wms"
LAYER = "dwd:Niederschlagsradar"
report: list[str] = []


def say(line: str = "") -> None:
    print(line, flush=True)
    report.append(line)


def feature_info(client: httpx.Client, lat: float, lon: float, when: str | None, fmt: str) -> str:
    d = 0.01
    params = {
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
        "INFO_FORMAT": fmt,
    }
    if when:
        params["TIME"] = when
    resp = client.get(WMS, params=params, timeout=30)
    return f"HTTP {resp.status_code} {resp.headers.get('content-type')} {resp.text[:600]!r}"


def main() -> int:
    with httpx.Client(headers={"User-Agent": "RowerWeather/0.1 (+https://github.com/RowerWeatherFrog/RowerWeather)"}) as client:
        caps = client.get(WMS, params={"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetCapabilities"}, timeout=60).text
        block = caps[caps.find(f"<Name>{LAYER}</Name>") - 200 :]
        block = block[: block.find("</Layer>")]
        start = caps.find(f"<Name>{LAYER}</Name>")
        queryable = re.findall(r'queryable="(\d)"', caps[max(0, start - 400) : start])
        say(f"layer found: {start >= 0}  queryable: {queryable[-1:] or '?'}")
        dims = re.findall(r"<Dimension[^>]*>([^<]*)</Dimension>", block)
        for d in dims:
            say(f"time dimension: {d[:300]} ... {d[-300:]}")
        times = dims[0].split(",") if dims else []
        if len(times) == 1 and "/" in times[0]:
            say(f"time is a range: {times[0]}")
        sample = [times[0], times[len(times) // 2], times[-1]] if len(times) > 2 else [None]
        for club in locations.load(catalog_paths=()).clubs.values():
            p = club.launch_point
            say(f"## {club.short_name}")
            for when in [None] + sample:
                for fmt in ("application/json", "text/plain"):
                    say(f"  TIME={when} {fmt}: {feature_info(client, p.lat, p.lon, when, fmt)}")
            break
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### DWD rain radar\n```\n" + "\n".join(report) + "\n```\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
