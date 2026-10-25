#!/usr/bin/env python3
"""Prints the master data of each GKD water temperature station named in
data/locations.json (name, position), for the app's station map.

Usage: python3 scripts/gkd_station_probe.py   (from the repository root)
"""

from __future__ import annotations

import json
import re
import sys

import httpx

URL = "https://www.gkd.bayern.de/en/lakes/watertemperature/bayern/{station}/master-data"


def main() -> int:
    lakes = json.load(open("data/locations.json"))["lakes"]
    with httpx.Client(headers={"User-Agent": "RowFrog/0.1 (+https://github.com/RowFrog/RowFrog)"}, follow_redirects=True) as client:
        for lake in lakes:
            station = lake.get("gkdWaterTemperatureStation")
            if not station:
                continue
            page = client.get(URL.format(station=station), timeout=30).text
            print(f"## {lake['id']} {station}: {len(page)} bytes")
            text = re.sub(r"<[^>]+>", " ", page)
            text = re.sub(r"\s+", " ", text)
            for word in ("Easting", "Northing", "East", "North", "Rechtswert", "Hochwert", "Latitude", "Longitude", "Coordinate", "Station name", "Water body", "Municipality"):
                for m in re.finditer(word, text):
                    print(f"  {text[max(0, m.start() - 40):m.end() + 120]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
