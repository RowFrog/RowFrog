"""Lake water temperature from the Gewässerkundlicher Dienst Bayern (GKD).

GKD publishes 15-minute values per lake station on its "current values"
table page. There is no JSON API, so the page is read as text: every
"DD.MM.YYYY HH:MM  value" pair is one measurement. Times are German local
time (CEST in summer): on 18.10.2026 at 11:31 UTC the newest row read 13:15.

The site's firewall answers requests without a real User-Agent (curl's or
httpx's default) with a 200 "Request Rejected" page, so fetches send one and
treat that page as an error.

Data: Gewässerkundlicher Dienst Bayern (Bayerisches Landesamt für Umwelt), CC BY 4.0.
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import httpx

PAGE_URL = "https://www.gkd.bayern.de/en/{kind}/watertemperature/bayern/{station}/current-values/table"
# Lake and river stations live under different pages.
KINDS = {"lake": "lakes", "river": "rivers"}
LOCAL = ZoneInfo("Europe/Berlin")
HEADERS = {"User-Agent": "RowFrog/0.1 (+https://github.com/RowFrog/RowFrog)"}
# A reading older than this means the station has gone quiet.
MAX_AGE = timedelta(hours=6)

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
        t = datetime(int(year), int(month), int(day), int(hour), int(minute), tzinfo=LOCAL)
        values[t] = float(value.replace(",", "."))
    return [WaterTemperature(t, values[t]) for t in sorted(values, reverse=True)]


def latest(page: str, now: datetime, max_age: timedelta = MAX_AGE) -> WaterTemperature | None:
    """The newest measurement, or None when the station has gone quiet."""
    readings = parse(page)
    if not readings or now - readings[0].time > max_age:
        return None
    return readings[0]


async def _page(client: httpx.AsyncClient, station: str, kind: str = "lake") -> str:
    resp = await client.get(PAGE_URL.format(kind=KINDS.get(kind, "lakes"), station=station), headers=HEADERS, timeout=20, follow_redirects=True)
    resp.raise_for_status()
    if "Request Rejected" in resp.text:
        raise httpx.HTTPError("GKD firewall rejected the request")
    return resp.text


async def fetch_latest(client: httpx.AsyncClient, station: str, now: datetime, kind: str = "lake") -> WaterTemperature | None:
    """`station` is the slug from the GKD page URL, e.g. "starnberg-16663002"."""
    return latest(await _page(client, station, kind), now)


def hourly(readings: list[WaterTemperature]) -> list[WaterTemperature]:
    """One reading per hour (the first of each hour), oldest first, for a chart."""
    by_hour: dict[datetime, WaterTemperature] = {}
    for r in sorted(readings, key=lambda r: r.time):
        by_hour.setdefault(r.time.replace(minute=0), r)
    return list(by_hour.values())


async def fetch_recent(
    client: httpx.AsyncClient, station: str, now: datetime, kind: str = "lake"
) -> tuple[WaterTemperature | None, list[WaterTemperature]]:
    """The newest measurement (as fetch_latest) and the page's history, hour by hour."""
    page = await _page(client, station, kind)
    return latest(page, now), hourly(parse(page))
