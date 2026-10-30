"""The sample API files in testdata/api/v1 that the app and the website read in
their own tests.

The backend writes them here from made-up weather, a water reading, a radar
line and the sample warnings, through the same code that publishes the real
files. The app's and the website's tests decode the very same files, so a field
renamed or dropped here fails their tests, not the rower's screen.

A change to the backend's output fails this test until the files are written
again: `UPDATE_SAMPLES=1 pytest tests/test_sample_files.py`, then commit them.
"""

import asyncio
import json
import math
import os
import sys
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from rowfrog import api
from rowfrog.sources import dwd_radar, dwd_warnings, gkd, open_meteo

ROOT = Path(__file__).resolve().parents[2]
SAMPLES = ROOT / "testdata" / "api" / "v1"
sys.path.insert(0, str(ROOT / "scripts"))
import publish_static  # noqa: E402  (the publish run's own file writer and refresh block)

NOW = datetime(2026, 10, 18, 6, tzinfo=timezone.utc)  # conftest's fixed clock
CLUB = "mrc-1880"


def _hours(start: datetime, count: int) -> list[open_meteo.ForecastHour]:
    """Weather that changes through the day: calm and misty in the morning, a
    windy, showery afternoon, a thunderstorm hour, then calm again."""
    hours = []
    for i in range(count):
        t = start + timedelta(hours=i)
        local = (t.hour + 2) % 24
        day = 7 <= local <= 18
        windy = 13 <= local <= 16
        hours.append(
            open_meteo.ForecastHour(
                time=t,
                temperature_c=round(8 + 6 * math.sin((local - 9) / 24 * 2 * math.pi), 1),
                wind_speed_ms=7.5 if windy else 2.0 + (i % 3) * 0.5,
                wind_gust_ms=13.0 if windy else 4.0,
                wind_from_deg=float((240 + i * 7) % 360),
                cloud_cover_pct=90 if local < 10 else 40,
                cloud_cover_low_pct=80 if local < 10 else 10,
                visibility_m=600 if local in (7, 8) else 25_000,
                precipitation_mm=1.4 if local in (15, 16) else 0.0,
                cape_jkg=900 if local == 16 else 0,
                is_day=day,
                weather_code=96 if local == 16 else 61 if local == 15 else 45 if local in (7, 8) else 3,
                apparent_temperature_c=round(6 + 6 * math.sin((local - 9) / 24 * 2 * math.pi), 1),
                humidity_pct=92 if local < 10 else 70,
                dew_point_c=5.5,
                pressure_hpa=round(1016 - i * 0.2, 1),
                cloud_cover_mid_pct=30,
                cloud_cover_high_pct=20,
            )
        )
    return hours


def _radar_answer(time: datetime, reference: datetime) -> dict:
    mm = 1.2 if time >= reference + timedelta(minutes=45) else -0.0003
    return {
        "features": [
            {
                "properties": {
                    "RV_ANALYSIS": mm,
                    "TIME": time.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
                    "REFERENCE_TIME": reference.strftime("%Y-%m-%dT%H:%M:%SZ"),
                }
            }
        ]
    }


def _radar() -> dict:
    reference = NOW - timedelta(minutes=10)

    def handler(request: httpx.Request) -> httpx.Response:
        time = request.url.params.get("TIME")
        at = datetime.fromisoformat(time.replace("Z", "+00:00")) if time else reference
        return httpx.Response(200, json=_radar_answer(at, reference))

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await dwd_radar.nowcast(client, 47.99, 11.35)

    return asyncio.run(run())


@pytest.fixture
def made_up_sources(monkeypatch):
    async def fetch(client, lat, lon, hours=48, models=None):
        return _hours(NOW, 48)

    async def fetch_outlook(client, lat, lon):
        # Yesterday and three days ahead (the real file has seven), to keep the file small.
        hours = _hours(NOW - timedelta(hours=24), 24 + 72)
        return [replace(h, uv_index=2.0 if h.is_day else 0.0) for h in hours]

    async def fetch_daily_mean(client, lat, lon):
        today = NOW.date()
        return [(today + timedelta(days=d), 9.0 + d * 0.1) for d in range(-92, 8)]

    async def fetch_recent(client, station, now, kind="lake"):
        history = [gkd.WaterTemperature(NOW - timedelta(hours=h), 12.6 + h * 0.05) for h in range(3, 0, -1)]
        return gkd.WaterTemperature(NOW - timedelta(minutes=15), 12.5), history

    async def lake_area(client, club):
        return dwd_warnings.LakeArea(warncell_id=0, name="Starnberger See", rings=[])

    async def no_lake_warnings(client):
        return []

    async def no_local_warnings(client, club):
        return [], {}

    async def no_english(client):
        return {}

    monkeypatch.setattr(open_meteo, "fetch", fetch)
    monkeypatch.setattr(open_meteo, "fetch_outlook", fetch_outlook)
    monkeypatch.setattr(open_meteo, "fetch_daily_mean", fetch_daily_mean)
    monkeypatch.setattr(api.gkd, "fetch_recent", fetch_recent)
    monkeypatch.setattr(api, "_lake_area", lake_area)
    monkeypatch.setattr(api, "_all_lake_warnings", no_lake_warnings)
    monkeypatch.setattr(api, "_local_warnings", no_local_warnings)
    monkeypatch.setattr(api, "_english_texts", no_english)
    # The made-up storm and frost warnings that screenshots use, so the files carry both kinds.
    monkeypatch.setattr(api, "SAMPLE_WARNING_CLUBS", {CLUB})
    monkeypatch.setattr(api, "SAMPLE_FROST_CLUBS", {CLUB})
    for cache in (api._cache, api._warnings_cache, api._ice_temps):
        cache.clear()
    yield
    for cache in (api._cache, api._warnings_cache, api._ice_temps):
        cache.clear()


def _sample_files() -> dict[str, object]:
    client = TestClient(api.app)
    forecast = client.get(f"/clubs/{CLUB}/forecast")
    assert forecast.status_code == 200, forecast.text
    body = forecast.json()
    # What the publish run adds to each file (scripts/publish_static.py).
    body["radar"] = _radar()
    body["refresh"] = publish_static.refresh_block(True)
    starnberg = next(l for l in client.get("/lakes").json() if l["id"] == "starnberger-see")
    return {
        f"clubs/{CLUB}/forecast": body,
        # Just the sample club's lake, so the file stays small; the app reads the same shape.
        "lakes/index": [starnberg],
    }


def _text(body) -> str:
    # Pretty-printed so a change shows up line by line in a review.
    return json.dumps(body, ensure_ascii=False, indent=1, sort_keys=True) + "\n"


def test_sample_files_match_what_the_backend_writes(made_up_sources):
    files = _sample_files()
    if os.environ.get("UPDATE_SAMPLES"):
        for path, body in files.items():
            (SAMPLES / path).parent.mkdir(parents=True, exist_ok=True)
            (SAMPLES / path).write_text(_text(body), encoding="utf-8")
    for path, body in files.items():
        saved = SAMPLES / path
        assert saved.exists(), f"{saved} is missing: run UPDATE_SAMPLES=1 pytest tests/test_sample_files.py"
        assert saved.read_text(encoding="utf-8") == _text(body), (
            f"The backend now writes {path} differently. If that is meant, run "
            "UPDATE_SAMPLES=1 pytest tests/test_sample_files.py and check the app and website tests still pass."
        )


def test_sample_forecast_fills_every_block_the_app_shows():
    """A block left empty in the sample would go untested in the app and website."""
    body = json.loads((SAMPLES / f"clubs/{CLUB}/forecast").read_text(encoding="utf-8"))
    for key in ("waterTemperature", "warnings", "ice", "forecastSource", "daylight", "hours", "outlook", "radar",
                "refresh", "waterForecast"):
        assert body.get(key), f"the sample forecast has no {key}"
    kinds = {w["event"] for w in body["warnings"]["items"]}
    assert {"STURM", "FROST"} <= kinds
    lights = {h["light"] for h in body["hours"]}
    assert {"green", "red"} <= lights, lights
