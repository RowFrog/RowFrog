"""River water temperature from the Swiss Federal Office for the Environment
(BAFU / FOEN, hydrodaten.admin.ch).

BAFU has no simple public API, so the values are read from api.existenz.ch,
a free mirror of the official feed run privately (existenz.ch). Each value
is {"timestamp": Unix seconds, "loc": station number, "par": "temperature",
"val": °C}, mostly every 10 minutes. If the mirror stops, the clubs that use
it simply show no measured value.

Data: Bundesamt für Umwelt BAFU (source must be named), via api.existenz.ch.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import httpx

from .gkd import HEADERS, MAX_AGE, WaterTemperature, hourly

URL = "https://api.existenz.ch/apiv1/hydro/daterange"


def parse(payload: list[dict]) -> list[WaterTemperature]:
    """The temperatures, newest first."""
    found = {}
    for v in payload:
        if v.get("par") != "temperature" or v.get("val") is None or v.get("timestamp") is None:
            continue
        found[datetime.fromtimestamp(v["timestamp"], timezone.utc)] = float(v["val"])
    return [WaterTemperature(t, found[t]) for t in sorted(found, reverse=True)]


async def fetch_recent(client: httpx.AsyncClient, station: str, now: datetime) -> tuple[WaterTemperature | None, list[WaterTemperature]]:
    """`station` is the BAFU station number. The newest value (None when older
    than gkd.MAX_AGE) and the last two days, hour by hour, like gkd.fetch_recent."""
    params = {
        "locations": station,
        "parameters": "temperature",
        "startdate": (now - timedelta(days=2)).date().isoformat(),
        "enddate": now.date().isoformat(),
        "app": "rowfrog",
    }
    resp = await client.get(URL, params=params, headers=HEADERS, timeout=20, follow_redirects=True)
    resp.raise_for_status()
    readings = parse(resp.json().get("payload") or [])
    newest = readings[0] if readings and now - readings[0].time <= MAX_AGE else None
    return newest, hourly(readings)
