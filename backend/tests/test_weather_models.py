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
