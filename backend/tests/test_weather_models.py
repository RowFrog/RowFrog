from rowerweather import weather_models as wm
from rowerweather.sources import open_meteo


def test_the_backend_asks_open_meteo_for_the_chain_it_names():
    assert open_meteo.request_params(47.9, 11.3)["models"] == wm.chain_for(47.9, 11.3).open_meteo


def test_source_lists_only_the_models_a_48_hour_forecast_uses():
    src = wm.source_json(wm.GERMANY, 48)
    assert src["region"] == "germany"
    assert src["parts"] == [
        {"model": "ICON-D2", "provider": "Deutscher Wetterdienst (DWD)", "resolutionKm": 2.2, "fromHour": 0, "toHour": 48}
    ]
    assert [p["model"] for p in wm.source_json(wm.GERMANY, 72)["parts"]] == ["ICON-D2", "ICON-EU"]
    assert wm.source_json(wm.GERMANY, 72)["parts"][1]["toHour"] == 72


def test_a_picked_model_comes_first_and_the_chain_fills_the_rest():
    ch1 = wm.choice(47.9, 11.3, "meteoswiss_icon_ch1")
    src = wm.picked_source_json(wm.GERMANY, ch1, 48)
    assert src["picked"] == "meteoswiss_icon_ch1"
    assert [(p["model"], p["fromHour"], p["toHour"]) for p in src["parts"]] == [("ICON-CH1", 0, 33), ("ICON-D2", 33, 48)]
    ifs = wm.choice(47.9, 11.3, "ecmwf_ifs025")
    assert [p["model"] for p in wm.picked_source_json(wm.GERMANY, ifs, 48)["parts"]] == ["IFS"]
    assert wm.choice(47.9, 11.3, "icon_seamless") is None, "the automatic chain is not a choice"


def test_filled_takes_missing_values_from_the_automatic_chain():
    from datetime import datetime, timedelta, timezone

    from rowerweather import api

    t0 = datetime(2026, 10, 24, tzinfo=timezone.utc)

    def hour(i, wind, temp):
        return open_meteo.ForecastHour(t0 + timedelta(hours=i), temp, wind, wind, 180, 50, 10, 20000, 0, 0, True)

    auto = [hour(0, 3.0, 10.0), hour(1, 3.0, 10.0)]
    picked = [hour(0, 5.0, None)]  # one hour only, without a temperature
    out = api._filled(picked, auto)
    assert [(h.wind_speed_ms, h.temperature_c) for h in out] == [(5.0, 10.0), (3.0, 10.0)]


def test_only_confirmed_clubs_offer_other_models(monkeypatch):
    from fastapi.testclient import TestClient

    from rowerweather import api
    from tests.test_dwd_warnings import PAYLOAD, _reset, _serve

    asked = []

    async def fake_fetch(client, lat, lon, hours=48, models="icon_seamless"):
        asked.append(models)
        return open_meteo.parse(PAYLOAD)

    async def no_water(*args, **kwargs):
        return None, []

    async def no_outlook(*args, **kwargs):
        return None

    import httpx

    monkeypatch.setattr(open_meteo, "fetch", fake_fetch)
    monkeypatch.setattr(open_meteo, "fetch_outlook", no_outlook)
    monkeypatch.setattr(api.gkd, "fetch_recent", no_water)
    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(lambda request: httpx.Response(200, json={"features": []})))
    _reset()
    client = TestClient(api.app)
    auto = client.get("/clubs/mrc-1880/forecast").json()
    assert [c["id"] for c in auto["modelChoices"]] == ["meteoswiss_icon_ch1", "geosphere_arome_austria", "ecmwf_ifs025"]
    assert "picked" not in auto["forecastSource"]
    picked = client.get("/clubs/mrc-1880/models/geosphere_arome_austria/forecast").json()
    assert picked["forecastSource"]["picked"] == "geosphere_arome_austria"
    assert picked["forecastSource"]["parts"][0]["model"] == "AROME"
    assert "geosphere_arome_austria" in asked
    assert client.get("/clubs/mrc-1880/models/icon_seamless/forecast").status_code == 404
    unconfirmed = next(c for c in api._locations.clubs.values() if c.source is not None)
    assert client.get(f"/clubs/{unconfirmed.id}/models/ecmwf_ifs025/forecast").status_code == 404
    _reset()
