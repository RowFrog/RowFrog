"""River water temperature from the Swiss Federal Office for the Environment
(BAFU / FOEN, hydrodaten.admin.ch).

BAFU has no simple public API, so the values are read from api.existenz.ch,
a free mirror of the official feed run privately (existenz.ch). Each value
is {"timestamp": Unix seconds, "loc": station number, "par": "temperature",
"val": °C}. Its "latest" endpoint gives the newest 10-minute value; the
"daterange" one only daily means (checked 25 Oct 2026), so there is no
hourly history. If the mirror stops, the clubs that use it simply show no
measured value.

Data: Bundesamt für Umwelt BAFU (source must be named), via api.existenz.ch.
"""

from __future__ import annotations

from datetime import datetime, timezone

import httpx

from .gkd import HEADERS, MAX_AGE, WaterTemperature, hourly

URL = "https://api.existenz.ch/apiv1/hydro/latest"


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
    than gkd.MAX_AGE) and, as the history, just that value."""
    params = {"locations": station, "parameters": "temperature", "app": "rowfrog"}
    resp = await client.get(URL, params=params, headers=HEADERS, timeout=20, follow_redirects=True)
    resp.raise_for_status()
    readings = parse(resp.json().get("payload") or [])
    newest = readings[0] if readings and now - readings[0].time <= MAX_AGE else None
    return newest, hourly(readings)
