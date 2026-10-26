"""Official GeoSphere Austria weather warnings for places in Austria.

GeoSphere Austria (formerly ZAMG) warns per municipality for wind, rain, snow,
black ice, thunderstorms, heat and cold, in yellow, orange and red, up to four
days ahead. Its Warn API (openapi.hub.geosphere.at/warnapi/v1) answers a
point with the municipality and its warnings, with full texts in German or
English (lang=de|en); outside Austria it answers 404. GeoSphere has no lake
warnings: the shore lights on Austrian lakes are switched by the Länder.

Each warning carries warntypid (1 wind ... 7 cold), warnstufeid (1 yellow,
2 orange, 3 red), rawinfo.start/end (Unix seconds) with begin/end as local
text for older answers, text (the headline), auswirkungen (impacts),
empfehlungen (advice) and meteotext (the forecaster's note).

The warnings become dwd_warnings.Warning objects so the rowing light and the
app treat them like DWD's: the event is a German word the app already looks
for (GEWITTER, REGEN, SCHNEE ...) and yellow, orange, red map to DWD's Minor,
Moderate, Severe.

Data: GeoSphere Austria, CC BY 4.0 (credit "GeoSphere Austria").
"""

from __future__ import annotations

from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import httpx

from .dwd_warnings import EnglishText, Warning

WARN_URL = "https://warnungen.zamg.at/wsapp/api/getWarningsForCoords"
VIENNA = ZoneInfo("Europe/Vienna")

# warntypid: (German event as the app's word lists know it, English event).
EVENTS = {
    1: ("WIND", "wind"),
    2: ("REGEN", "rain"),
    3: ("SCHNEE", "snow"),
    4: ("GLATTEIS", "black ice"),
    5: ("GEWITTER", "thunderstorms"),
    6: ("HITZE", "heat"),
    7: ("KÄLTE", "cold"),
}
# warnstufeid: yellow, orange, red, as DWD's severities with the same colours.
SEVERITIES = {1: "Minor", 2: "Moderate", 3: "Severe"}


def _time(raw: str | None, text: str | None) -> datetime | None:
    if raw:
        try:
            return datetime.fromtimestamp(int(raw), tz=timezone.utc)
        except ValueError:
            pass
    if not text:
        return None
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return datetime.strptime(text, "%d.%m.%Y %H:%M").replace(tzinfo=VIENNA)


def _description(p: dict) -> str:
    return "\n\n".join(part.strip() for part in (p.get("auswirkungen"), p.get("meteotext")) if part and part.strip())


def parse(answer: dict) -> list[tuple[int, Warning]]:
    """(warnid, warning) pairs from one getWarningsForCoords answer."""
    props = answer.get("properties") or {}
    place = ((props.get("location") or {}).get("properties") or {}).get("name") or ""
    out = []
    for item in props.get("warnings") or []:
        p = item.get("properties") or item
        raw = p.get("rawinfo") or {}
        kind = int(p.get("warntypid") or raw.get("wtype") or 0)
        level = int(p.get("warnstufeid") or raw.get("wlevel") or 1)
        warnid = int(p.get("warnid") or 0)
        out.append(
            (
                warnid,
                Warning(
                    kind="local",
                    area=place,
                    event=EVENTS.get(kind, ("WARNUNG", "warning"))[0],
                    severity=SEVERITIES.get(level, "Minor"),
                    headline=(p.get("text") or "").strip(),
                    description=_description(p),
                    instruction=(p.get("empfehlungen") or "").strip() or None,
                    onset=_time(raw.get("start"), p.get("begin")),
                    expires=_time(raw.get("end"), p.get("end")),
                    identifier=f"geosphere-{warnid}",
                    source="geosphere",
                ),
            )
        )
    return out


def english_texts(german: list[tuple[int, Warning]], english_answer: dict | None) -> dict[str, EnglishText]:
    """GeoSphere's own English texts for the warnings, by identifier."""
    english = dict(parse(english_answer)) if english_answer else {}
    texts = {}
    for warnid, w in german:
        e = english.get(warnid)
        event = next((en for de, en in EVENTS.values() if de == w.event), w.event.lower())
        if e is None:
            texts[w.identifier] = EnglishText(event=event, headline=f"Official warning: {event}", description=None, instruction=None, official=False)
        else:
            texts[w.identifier] = EnglishText(
                event=event, headline=e.headline, description=e.description or None, instruction=e.instruction, official=True
            )
    return texts


async def fetch(client: httpx.AsyncClient, lon: float, lat: float) -> tuple[list[Warning], dict[str, EnglishText]]:
    """The warnings for the municipality at the point, with their English texts.

    English is asked for only while a warning is out. Raises ValueError for a
    point outside Austria (GeoSphere answers 404 there).
    """
    resp = await client.get(WARN_URL, params={"lon": lon, "lat": lat, "lang": "de"}, timeout=30)
    if resp.status_code == 404:
        raise ValueError("no Austrian municipality at this point")
    resp.raise_for_status()
    german = parse(resp.json())
    if not german:
        return [], {}
    english_answer = None
    try:
        en = await client.get(WARN_URL, params={"lon": lon, "lat": lat, "lang": "en"}, timeout=30)
        en.raise_for_status()
        english_answer = en.json()
    except (httpx.HTTPError, ValueError):
        pass
    return [w for _, w in german], english_texts(german, english_answer)
