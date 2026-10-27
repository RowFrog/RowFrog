"""Rain at a launch point from DWD's radar: now and DWD's nowcast for the next
two hours, every 15 minutes, for the widget's radar line.

The app's rain radar card asks DWD itself every 5 minutes while it is open.
The widget can't refresh that often, so the publish job reads the radar for
the clubs people use on every run (every 30 minutes) and puts it into their
forecast file; the widget shows it while it still reaches ahead.

Source: WMS layer dwd:Niederschlagsradar (RV product, 1 km), read at the
launch point with GetFeatureInfo, as the app does (RainRadar.swift). No rain
comes back as a tiny negative value. One reading for the latest picture
gives the reference time, then one per 15 minutes from it: 10 requests a club.

Data: Deutscher Wetterdienst, CC BY 4.0 (credit "Deutscher Wetterdienst").
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta

import httpx

WMS_URL = "https://maps.dwd.de/geoserver/dwd/wms"
LAYER = "dwd:Niederschlagsradar"
STEP_MINUTES = 15
AHEAD_MINUTES = 120
# DWD's server is slow with many parallel requests.
PARALLEL = 4

requests_made = 0


def _params(lat: float, lon: float, time: datetime | None) -> dict[str, str]:
    d = 0.01
    params = {
        "SERVICE": "WMS",
        "VERSION": "1.3.0",
        "REQUEST": "GetFeatureInfo",
        "LAYERS": LAYER,
        "QUERY_LAYERS": LAYER,
        "CRS": "EPSG:4326",
        # WMS 1.3.0 with EPSG:4326 takes latitude first.
        "BBOX": f"{lat - d},{lon - d},{lat + d},{lon + d}",
        "WIDTH": "101",
        "HEIGHT": "101",
        "I": "50",
        "J": "50",
        "INFO_FORMAT": "application/json",
    }
    if time is not None:
        params["TIME"] = time.strftime("%Y-%m-%dT%H:%M:%SZ")
    return params


def _parse_time(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def parse_reading(body: dict) -> tuple[datetime, float, datetime]:
    """(time, mm per hour, reference time) from one GetFeatureInfo answer."""
    props = body["features"][0]["properties"]
    value = props.get("RV_ANALYSIS")
    return _parse_time(props["TIME"]), max(0.0, value or 0.0), _parse_time(props["REFERENCE_TIME"])


async def _reading(client: httpx.AsyncClient, lat: float, lon: float, time: datetime | None) -> tuple[datetime, float, datetime]:
    global requests_made
    requests_made += 1
    resp = await client.get(WMS_URL, params=_params(lat, lon, time), timeout=20)
    resp.raise_for_status()
    return parse_reading(resp.json())


async def nowcast(client: httpx.AsyncClient, lat: float, lon: float) -> dict:
    """The radar block of a forecast file: the reference time and a step per
    15 minutes from it, two hours ahead."""
    _, _, reference = await _reading(client, lat, lon, None)
    times = [reference + timedelta(minutes=m) for m in range(0, AHEAD_MINUTES + 1, STEP_MINUTES)]
    # Every reading finishes before an error is raised, so none is left running
    # to fail later outside the caller's handler.
    readings = await asyncio.gather(*(_reading(client, lat, lon, t) for t in times), return_exceptions=True)
    for reading in readings:
        if isinstance(reading, BaseException):
            raise reading
    steps = sorted((at, mm) for at, mm, _ in readings)
    return {
        "reference": reference.isoformat(),
        "steps": [{"time": at.isoformat(), "mmPerHour": round(mm, 2)} for at, mm in steps],
    }


async def nowcasts(points: dict[str, tuple[float, float]]) -> dict[str, dict]:
    """Radar blocks by club id; a club whose radar can't be read is left out."""
    limit = asyncio.Semaphore(PARALLEL)
    results: dict[str, dict] = {}
    async with httpx.AsyncClient() as client:

        async def one(club_id: str, lat: float, lon: float) -> None:
            async with limit:
                try:
                    results[club_id] = await nowcast(client, lat, lon)
                # OSError covers a connection the TLS layer drops (ssl.SSLError),
                # which httpx doesn't always wrap in an HTTPError.
                except (httpx.HTTPError, OSError, KeyError, IndexError, ValueError) as e:
                    print(f"  radar {club_id}: {type(e).__name__}: {e}")

        await asyncio.gather(*(one(i, lat, lon) for i, (lat, lon) in points.items()))
    return results
