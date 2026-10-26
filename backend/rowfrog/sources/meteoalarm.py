"""Official MeteoSwiss weather warnings for places in Switzerland, via MeteoAlarm.

MeteoSwiss does not publish its warnings in its open data yet; it sends them
as CAP messages to MeteoAlarm (EUMETNET), whose free feed for a country
(feeds.meteoalarm.org/api/v1/warnings/feeds-switzerland) lists every
warning with one `info` block per language (de, fr, it, en, rm), each with
its warning regions as polygons. One answer serves every Swiss club, matched
by the region its launch point lies in.

The feed keeps expired warnings for days, so only those still running count.
Forest fire and avalanche warnings are left out: they say nothing about the
water. MeteoSwiss's lake storm warnings (the shore lights) are not in the feed.

The warnings become dwd_warnings.Warning objects so the rowing light treats
them like DWD's: the event is a German word the app already looks for and
MeteoAlarm's yellow, orange, red map to DWD's Minor, Moderate, Severe. The
texts are shown as MeteoSwiss wrote them, which its terms ask for.

Data: MeteoSwiss via MeteoAlarm; reuse on terms equivalent to CC BY 4.0
(credit "MeteoSwiss", "MeteoAlarm"), passed on unaltered.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

import httpx

from .dwd_warnings import EnglishText, Warning, distance_to_area_m

FEED_URL = "https://feeds.meteoalarm.org/api/v1/warnings/feeds-{country}"
# A launch point on the shore can sit just outside a region's simplified polygon.
REGION_TOLERANCE_M = 500.0

# MeteoAlarm awareness types: (German event as the app's word lists know it, English event).
EVENTS = {
    1: ("WIND", "wind"),
    2: ("SCHNEE", "snow and ice"),
    3: ("GEWITTER", "thunderstorms"),
    4: ("NEBEL", "fog"),
    5: ("HITZE", "heat"),
    6: ("KÄLTE", "cold"),
    10: ("REGEN", "rain"),
    12: ("HOCHWASSER", "flooding"),
    13: ("REGEN", "rain and flooding"),
}
# Not about the water: forest fire, avalanches.
SKIPPED_TYPES = {8, 9}
SEVERITIES = {"yellow": "Minor", "orange": "Moderate", "red": "Severe"}


@dataclass(frozen=True)
class Alert:
    warning: Warning
    english: EnglishText | None
    rings: list[list[tuple[float, float]]]  # (lon, lat)


def _parameter(info: dict, name: str) -> str:
    return next((p.get("value") or "" for p in info.get("parameter") or [] if p.get("valueName") == name), "")


def _ring(polygon) -> list[tuple[float, float]]:
    """One CAP polygon as (lon, lat): "lat,lon lat,lon ...", or a list of "lat,lon" or [lat, lon]."""
    if isinstance(polygon, str):
        pairs = [p.split(",") for p in polygon.split()]
    else:
        pairs = [p.split(",") if isinstance(p, str) else p for p in polygon]
    return [(float(p[1]), float(p[0])) for p in pairs if len(p) >= 2]


def _rings(areas: list[dict]) -> list[list[tuple[float, float]]]:
    """The areas' polygons as (lon, lat) rings."""
    rings = []
    for area in areas:
        polygons = area.get("polygon") or []
        # One polygon given as a list of points ("lat,lon" or [lat, lon]) rather than a list of polygons.
        if isinstance(polygons, list) and polygons:
            first = polygons[0]
            if (isinstance(first, str) and " " not in first.strip()) or (isinstance(first, list) and first and not isinstance(first[0], (list, str))):
                polygons = [polygons]
        for polygon in [polygons] if isinstance(polygons, str) else polygons:
            ring = _ring(polygon)
            if len(ring) >= 3:
                rings.append(ring)
    return rings


def _time(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None


def parse(feed: dict, now: datetime) -> list[Alert]:
    """The warnings still running at `now`, in German with MeteoSwiss's English beside them."""
    out = []
    for item in feed.get("warnings") or []:
        alert = item.get("alert") or {}
        if alert.get("status", "Actual") != "Actual" or alert.get("msgType") == "Cancel":
            continue
        infos = alert.get("info") or []
        by_lang = {(i.get("language") or "")[:2]: i for i in infos}
        german = by_lang.get("de") or (infos[0] if infos else None)
        if german is None:
            continue
        expires = _time(german.get("expires"))
        if expires is not None and expires <= now:
            continue
        kind = int((_parameter(german, "awareness_type").split(";")[0] or "0").strip() or 0)
        if kind in SKIPPED_TYPES:
            continue
        colour = (_parameter(german, "awareness_level").split(";") + ["", ""])[1].strip()
        event, event_en = EVENTS.get(kind, ("WARNUNG", "warning"))
        areas = german.get("area") or []
        identifier = f"meteoalarm-{alert.get('identifier') or item.get('uuid') or ''}"
        warning = Warning(
            kind="local",
            area=", ".join(a.get("areaDesc") or "" for a in areas if a.get("areaDesc")),
            event=event,
            severity=SEVERITIES.get(colour, german.get("severity") or "Minor"),
            headline=(german.get("headline") or german.get("event") or "").strip(),
            description=(german.get("description") or "").strip(),
            instruction=(german.get("instruction") or "").strip() or None,
            onset=_time(german.get("onset") or german.get("effective")),
            expires=expires,
            identifier=identifier,
            source="meteoswiss",
        )
        en = by_lang.get("en")
        english = None
        if en is not None:
            english = EnglishText(
                event=event_en,
                headline=(en.get("headline") or en.get("event") or "").strip(),
                description=(en.get("description") or "").strip() or None,
                instruction=(en.get("instruction") or "").strip() or None,
                official=True,
            )
        out.append(Alert(warning, english, _rings(areas)))
    return out


def for_point(alerts: list[Alert], lon: float, lat: float, tolerance_m: float = REGION_TOLERANCE_M) -> list[Alert]:
    """The warnings whose region holds the point (or lies within the tolerance of it)."""
    return [a for a in alerts if a.rings and distance_to_area_m(lon, lat, a.rings) <= tolerance_m]


async def fetch(client: httpx.AsyncClient, now: datetime, country: str = "switzerland") -> list[Alert]:
    resp = await client.get(FEED_URL.format(country=country), timeout=60)
    resp.raise_for_status()
    return parse(resp.json(), now)
