"""Lake water temperature from the Gewässerkundlicher Dienst Bayern (GKD).

GKD publishes 15-minute values per lake station on its "current values"
table page. There is no JSON API, so the page is read as text: every
"DD.MM.YYYY HH:MM  value" pair is one measurement. Times are taken as CET
(UTC+1) all year, which is how the Bavarian hydrological services publish
them.

Data: Gewässerkundlicher Dienst Bayern (Bayerisches Landesamt für Umwelt), CC BY 4.0.
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import httpx

PAGE_URL = "https://www.gkd.bayern.de/en/lakes/watertemperature/bayern/{station}/current-values/table"
CET = timezone(timedelta(hours=1))

_TAG = re.compile(r"<[^>]+>")
_ROW = re.compile(r"(\d{2})\.(\d{2})\.(\d{4})\s+(\d{2}):(\d{2})\s+(-?\d+(?:[.,]\d+)?)")


@dataclass(frozen=True)
class WaterTemperature:
    time: datetime
    celsius: float


def parse(page: str) -> list[WaterTemperature]:
    """All measurements on the page, newest first."""
    text = html.unescape(_TAG.sub(" ", page))
    values = {}
    for day, month, year, hour, minute, value in _ROW.findall(text):
        t = datetime(int(year), int(month), int(day), int(hour), int(minute), tzinfo=CET)
        values[t] = float(value.replace(",", "."))
    return [WaterTemperature(t, values[t]) for t in sorted(values, reverse=True)]


def latest(page: str, now: datetime, max_age: timedelta = timedelta(hours=6)) -> WaterTemperature | None:
    """The newest measurement, or None when the station has gone quiet."""
    readings = parse(page)
    if not readings or now - readings[0].time > max_age:
        return None
    return readings[0]


async def fetch_latest(client: httpx.AsyncClient, station: str, now: datetime) -> WaterTemperature | None:
    """`station` is the slug from the GKD page URL, e.g. "starnberg-16663002"."""
    resp = await client.get(PAGE_URL.format(station=station), timeout=20, follow_redirects=True)
    resp.raise_for_status()
    return latest(resp.text, now)
