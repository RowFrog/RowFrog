import asyncio

import httpx
from fastapi.testclient import TestClient

from rowerweather import api, locations
from rowerweather.forecast import rowing_forecast
from rowerweather.score import Light
from rowerweather.sources import open_meteo

from .test_waves import LAKE

PAYLOAD = {
    "hourly": {
        "time": ["2026-10-18T06:00", "2026-10-18T07:00"],
        "temperature_2m": [6.1, 7.0],
        "wind_speed_10m": [1.5, 9.0],
        "wind_gusts_10m": [3.0, 14.0],
        "wind_direction_10m": [0, 0],
        "cloud_cover": [100, 80],
        "cloud_cover_low": [100, 60],
        "visibility": [400, 20_000],
        "precipitation": [0, 0],
        "cape": [0, 0],
        "is_day": [1, 1],
    }
}


def test_parse_open_meteo_payload():
    hours = open_meteo.parse(PAYLOAD)
    assert len(hours) == 2
    assert hours[0].time.isoformat() == "2026-10-18T06:00:00+00:00"
    assert hours[1].wind_gust_ms == 14.0


def test_parse_tolerates_missing_variables():
    payload = {"hourly": {"time": ["2026-10-18T06:00"], "wind_speed_10m": [2.0]}}
    (hour,) = open_meteo.parse(payload)
    assert hour.visibility_m is None
    assert hour.is_day is None


def test_fetch_retries_one_connect_timeout():
    calls = []

    def handler(request):
        calls.append(request)
        if len(calls) == 1:
            raise httpx.ConnectTimeout("timed out", request=request)
        return httpx.Response(200, json=PAYLOAD)

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await open_meteo.fetch(client, 47.9, 11.3)

    assert len(asyncio.run(run())) == 2
    assert len(calls) == 2


def test_rowing_forecast_combines_fog_and_waves():
    club = locations.Club(
        id="test",
        name="Test RC",
        lake_id="test-lake",
        address="",
        website=None,
        launch_point=locations.Point(lat=47.90 + 100 / 111_195, lon=LAKE[0][0][0] + 0.0134),
        launch_point_verified=False,
    )
    fog_hour, windy_hour = rowing_forecast(club, open_meteo.parse(PAYLOAD), LAKE)
    assert fog_hour.assessment.light == Light.RED
    assert ("fog", Light.RED) in fog_hour.assessment.reasons
    assert windy_hour.wave_height_m > 0.30
    assert windy_hour.assessment.light == Light.RED


def test_lakes_endpoint_lists_starnberger_see_clubs():
    body = TestClient(api.app).get("/lakes").json()
    starnberg = next(l for l in body if l["id"] == "starnberger-see")
    assert {c["id"] for c in starnberg["clubs"]} == {"mrc-1880", "mrsv-bayern", "tutzinger-rv"}


def test_unknown_club_is_404():
    assert TestClient(api.app).get("/clubs/nope/forecast").status_code == 404
