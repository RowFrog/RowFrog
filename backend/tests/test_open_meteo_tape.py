import asyncio

import httpx

from rowfrog.sources import open_meteo

PARAMS = {"latitude": "47.9", "longitude": "11.3", "hourly": "precipitation"}


def _ask(handler, params=PARAMS):
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await open_meteo._get(client, open_meteo.BASE_URL, params)

    return asyncio.run(run())


def _unreachable(request):
    raise httpx.ConnectTimeout("", request=request)


def test_a_recorded_answer_is_played_back_without_asking_open_meteo(tmp_path, monkeypatch):
    monkeypatch.setattr(open_meteo, "_failed_in_row", 0)
    monkeypatch.setattr(open_meteo, "_down_until", 0.0)
    monkeypatch.setenv("RW_OPEN_METEO_TAPE", str(tmp_path))
    monkeypatch.setenv("RW_OPEN_METEO_TAPE_MODE", "record")
    assert _ask(lambda request: httpx.Response(200, json={"hourly": [1.5]})) == {"hourly": [1.5]}
    assert len(list(tmp_path.iterdir())) == 1

    monkeypatch.setenv("RW_OPEN_METEO_TAPE_MODE", "replay")
    assert _ask(_unreachable) == {"hourly": [1.5]}


def test_a_call_not_on_the_tape_goes_out_live(tmp_path, monkeypatch):
    monkeypatch.setattr(open_meteo, "_failed_in_row", 0)
    monkeypatch.setattr(open_meteo, "_down_until", 0.0)
    monkeypatch.setenv("RW_OPEN_METEO_TAPE", str(tmp_path))
    asked = []

    def live(request):
        asked.append(request)
        return httpx.Response(200, json={"live": True})

    assert _ask(live, {**PARAMS, "latitude": "48.0"}) == {"live": True}
    assert len(asked) == 1
    # Played back only, never written in replay mode.
    assert not list(tmp_path.iterdir())


def test_without_a_tape_nothing_is_kept(tmp_path, monkeypatch):
    monkeypatch.delenv("RW_OPEN_METEO_TAPE", raising=False)
    assert open_meteo._tape_file(open_meteo.BASE_URL, PARAMS) is None
