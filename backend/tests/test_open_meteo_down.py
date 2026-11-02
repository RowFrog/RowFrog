import asyncio

import httpx

from rowfrog.sources import open_meteo


def _client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def test_open_meteo_counts_as_down_after_calls_in_a_row_fail(monkeypatch):
    monkeypatch.setattr(open_meteo, "_failed_in_row", 0)
    monkeypatch.setattr(open_meteo, "_down_until", 0.0)
    asked = []

    def unreachable(request):
        asked.append(request)
        raise httpx.ConnectTimeout("", request=request)

    async def run():
        async with _client(unreachable) as client:
            for _ in range(open_meteo.DOWN_AFTER + 3):
                try:
                    await open_meteo._get(client, open_meteo.BASE_URL, {"latitude": "48", "longitude": "11"})
                except httpx.HTTPError:
                    pass

    asyncio.run(run())
    # Each failing call is tried twice; after DOWN_AFTER of them nothing more is asked.
    assert len(asked) == 2 * open_meteo.DOWN_AFTER


def test_an_answer_resets_the_count(monkeypatch):
    monkeypatch.setattr(open_meteo, "_failed_in_row", open_meteo.DOWN_AFTER - 1)
    monkeypatch.setattr(open_meteo, "_down_until", 0.0)

    async def run():
        async with _client(lambda request: httpx.Response(200, json={})) as client:
            return await open_meteo._get(client, open_meteo.BASE_URL, {"latitude": "48", "longitude": "11"})

    assert asyncio.run(run()) == {}
    assert open_meteo._failed_in_row == 0


def test_daily_air_temperatures_pause_after_two_lakes_fail(monkeypatch):
    from datetime import date
    from types import SimpleNamespace

    from rowfrog import api

    monkeypatch.setattr(api, "_ice_temps", {})
    monkeypatch.setattr(api, "_air_days_failed", 0)
    monkeypatch.setattr(api, "_air_days_paused_until", 0.0)
    asked = []

    async def unreachable(client, lat, lon):
        asked.append((lat, lon))
        raise httpx.ConnectTimeout("")

    monkeypatch.setattr(open_meteo, "fetch_daily_mean", unreachable)
    lakes = [SimpleNamespace(id=f"lake-{i}", center=SimpleNamespace(lat=48.0 + i, lon=11.0)) for i in range(5)]

    async def run():
        return [await api._air_days(None, lake, date(2026, 11, 1)) for lake in lakes]

    assert asyncio.run(run()) == [None] * 5
    assert len(asked) == 2
