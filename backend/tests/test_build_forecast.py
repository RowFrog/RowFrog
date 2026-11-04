"""build_club_forecast turns a club's inputs into its forecast JSON without any
network (api.py, code review finding 4): the same JSON the API serves."""

from datetime import datetime, timedelta, timezone

from rowfrog import api
from rowfrog.sources import open_meteo

NOW = datetime(2026, 10, 18, 6, tzinfo=timezone.utc)


def _hour(t: datetime) -> open_meteo.ForecastHour:
    return open_meteo.ForecastHour(
        time=t, temperature_c=12.0, wind_speed_ms=2.0, wind_gust_ms=4.0, wind_from_deg=240.0, cloud_cover_pct=40,
        cloud_cover_low_pct=10, visibility_m=25_000, precipitation_mm=0.0, cape_jkg=0, is_day=8 <= t.hour <= 16,
        weather_code=3, apparent_temperature_c=11.0, humidity_pct=70, dew_point_c=5.5, pressure_hpa=1016.0,
        cloud_cover_mid_pct=30, cloud_cover_high_pct=20,
    )


def test_a_forecast_is_built_from_given_inputs_alone(monkeypatch):
    def no_network(*args, **kwargs):
        raise AssertionError("build_club_forecast must not load anything")

    monkeypatch.setattr(api.httpx, "AsyncClient", no_network)
    club = api._locations.clubs["mrc-1880"]
    lake = api._locations.lakes[club.lake_id]
    inputs = api.ClubInputs(
        weather=[_hour(NOW + timedelta(hours=i)) for i in range(48)], outlook=None, station=None, water=None,
        water_history=[], warnings_block={"active": []}, warnings=[], estimate=None, water_model_c=13.5,
        ice_estimate=None, air_days=None, gauge=None, readings=None, level_lake=None, levels=None,
    )
    body = api.build_club_forecast(club, lake, inputs, None, NOW)
    assert body["clubId"] == "mrc-1880" and body["lakeId"] == club.lake_id
    assert body["generatedAt"] == "2026-10-18T06:00:00+00:00"
    assert len(body["hours"]) == 48 and body["outlook"] is None
    assert body["waterModelC"] == 13.5 and body["waterTemperature"] is None
