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


def test_the_water_near_the_launch_point_sets_the_light(monkeypatch):
    # Option C (owner, 6 Nov 2026): fog on the water within 1 km turns the launch point's hour red.
    from dataclasses import replace

    club = api._locations.clubs["mrc-1880"]
    lake = api._locations.lakes[club.lake_id]
    grid = api.lake_grid(club.lake_id, api.outlines.load(club.lake_id))
    hours = [_hour(NOW + timedelta(hours=i)) for i in range(48)]
    foggy = [[replace(h, visibility_m=300.0) for h in hours] for _ in grid.samples]
    inputs = api.ClubInputs(
        weather=hours, outlook=None, station=None, water=None, water_history=[], warnings_block={"active": []},
        warnings=[], estimate=None, water_model_c=16.0, ice_estimate=None, air_days=None, gauge=None, readings=None,
        level_lake=None, levels=None, lake_weather=foggy,
    )
    body = api.build_club_forecast(club, lake, inputs, None, NOW)
    noon = next(h for h in body["hours"] if h["time"].startswith("2026-10-18T11"))
    assert noon["light"] == "red"
    assert noon["reasons"][0] == {"condition": "nearby_water", "light": "red", "topic": "fog", "value": 300.0}
    assert noon["nearby"]["visM"] == 300 and noon["nearby"]["other"] == "red" and noon["nearby"]["otherCause"] == "fog"
    # Without the lake view's forecast the hour is the launch point's alone.
    plain = api.build_club_forecast(club, lake, replace(inputs, lake_weather=None), None, NOW)
    noon = next(h for h in plain["hours"] if h["time"].startswith("2026-10-18T11"))
    assert "nearby" not in noon and all(r["condition"] != "nearby_water" for r in noon["reasons"])


def _inputs(hours):
    return api.ClubInputs(
        weather=hours, outlook=None, station=None, water=None, water_history=[], warnings_block={"active": []},
        warnings=[], estimate=None, water_model_c=13.5, ice_estimate=None, air_days=None, gauge=None, readings=None,
        level_lake=None, levels=None,
    )


def test_the_table_finishes_the_night_it_ends_in():
    # Owner's option B (12 Nov 2026): 48 hours from 19:00 end at 19:00 two days later, in the
    # dark; the table then goes on to the hour the sun rises in, from the coarser model's hours.
    club = api._locations.clubs["mrc-1880"]
    lake = api._locations.lakes[club.lake_id]
    now = datetime(2026, 10, 18, 17, tzinfo=timezone.utc)
    weather = [_hour(now + timedelta(hours=i)) for i in range(api.FETCH_HOURS)]
    body = api.build_club_forecast(club, lake, _inputs(weather), None, now)
    times = [datetime.fromisoformat(h["time"]) for h in body["hours"]]
    assert len(times) > 48
    sunrise = next(
        d.sunrise for d in api.sun_days(now, now + timedelta(days=3), club.launch_point.lat, club.launch_point.lon)
        if d.sunrise > times[47]
    )
    # The last hour ends before sunrise, and the next one would hold it.
    assert times[-1] + timedelta(hours=1) <= sunrise < times[-1] + timedelta(hours=2)
    # The source line names the coarser model for those hours.
    assert [p["model"] for p in body["forecastSource"]["parts"]] == ["ICON-D2", "ICON-EU"]
    assert body["forecastSource"]["parts"][1]["fromHour"] == 48


def test_a_table_ending_by_day_stays_48_hours():
    club = api._locations.clubs["mrc-1880"]
    lake = api._locations.lakes[club.lake_id]
    weather = [_hour(NOW + timedelta(hours=i)) for i in range(api.FETCH_HOURS)]
    body = api.build_club_forecast(club, lake, _inputs(weather), None, NOW + timedelta(hours=4))
    assert len(body["hours"]) == 48
    assert [p["model"] for p in body["forecastSource"]["parts"]] == ["ICON-D2"]
