"""River water temperature from PEGELONLINE, the gauges of the federal
waterways (Wasserstraßen- und Schifffahrtsverwaltung des Bundes, WSV).

The REST API gives each gauge's measurements per time series; water
temperature is the series "WT", in °C, mostly every 15 minutes, with times
in German local time and an offset ("2026-10-25T12:00:00+01:00").

Data: Wasserstraßen- und Schifffahrtsverwaltung des Bundes (WSV), DL-DE Zero 2.0.
"""

from __future__ import annotations

from datetime import datetime

import httpx

from .gkd import HEADERS, MAX_AGE, WaterTemperature, hourly

URL = "https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations/{station}/WT/measurements.json"


def parse(rows: list[dict]) -> list[WaterTemperature]:
    """The measurements, newest first."""
    found = {}
    for r in rows:
        if r.get("value") is None or not r.get("timestamp"):
            continue
        found[datetime.fromisoformat(r["timestamp"])] = float(r["value"])
    return [WaterTemperature(t, found[t]) for t in sorted(found, reverse=True)]


async def fetch_recent(client: httpx.AsyncClient, station: str, now: datetime) -> tuple[WaterTemperature | None, list[WaterTemperature]]:
    """`station` is the gauge's uuid. The newest measurement (None when older
    than gkd.MAX_AGE) and the last two days, hour by hour, like gkd.fetch_recent."""
    resp = await client.get(URL.format(station=station), params={"start": "P2D"}, headers=HEADERS, timeout=20, follow_redirects=True)
    resp.raise_for_status()
    readings = parse(resp.json())
    newest = readings[0] if readings and now - readings[0].time <= MAX_AGE else None
    return newest, hourly(readings)
