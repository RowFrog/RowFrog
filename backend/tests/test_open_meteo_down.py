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
