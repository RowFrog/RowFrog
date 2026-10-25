import asyncio
from datetime import date, datetime, timedelta, timezone

from rowfrog import api, ice
from rowfrog.forecast import rowing_forecast
from rowfrog.locations import Club, Lake, Point
from rowfrog.score import Light
from rowfrog.sources.open_meteo import ForecastHour

TODAY = date(2027, 1, 20)


def _temps(*spans: tuple[int, float], start: date = TODAY - timedelta(days=91)) -> list[ice.DayTemperature]:
    """Daily means from `start`: each span is (number of days, °C)."""
    out, day = [], start
    for days, celsius in spans:
        for _ in range(days):
            out.append(ice.DayTemperature(day, celsius))
            day += timedelta(days=1)
    return out


def test_shallow_lake_freezes_after_weeks_of_frost():
    # Mild autumn, then a month of -6 °C up to today and a cold forecast week.
    temps = _temps((62, 4.0), (37, -6.0))
    e = ice.simulate(temps, TODAY, mean_depth_m=4)
    assert e.status == ice.FROZEN
    assert e.basis == "model"
    assert 10 < e.thickness_cm < 30
    assert e.light == Light.RED
    assert [d.day for d in e.days][0] == TODAY and len(e.days) == 8


def test_deep_lake_stays_open_in_the_same_frost():
    temps = _temps((62, 4.0), (37, -6.0))
    assert ice.simulate(temps, TODAY, mean_depth_m=53.2).status in (ice.OPEN, ice.EDGES)
    assert ice.simulate(temps, TODAY, mean_depth_m=53.2).thickness_cm is None


def test_measured_warm_water_overrides_the_model():
    temps = _temps((62, 4.0), (37, -6.0))
    e = ice.simulate(temps, TODAY, mean_depth_m=4, measured_water_c=4.5)
    assert e.days[0].thickness_cm == 0
    assert e.basis == "measured"
    assert e.water_c == 4.5


def test_cold_lake_after_frosty_days_may_have_ice_at_the_edges():
    temps = _temps((88, 5.0), (3, -3.0), (8, -1.0))
    e = ice.simulate(temps, TODAY, mean_depth_m=53.2, measured_water_c=3.5)
    assert e.status == ice.EDGES
    assert e.light == Light.AMBER


def test_ice_melts_in_a_thaw():
    temps = _temps((50, 2.0), (30, -8.0), (19, 10.0))
    e = ice.simulate(temps, TODAY, mean_depth_m=3)
    assert e.status == ice.OPEN


def test_ice_forming_and_frozen_in_the_forecast_week():
    temps = _temps((90, 2.0), (9, -10.0))
    e = ice.simulate(temps, TODAY, mean_depth_m=2)
    statuses = [d.status for d in e.days]
    assert ice.FROZEN in statuses
    thickness = [d.thickness_cm for d in e.days]
    assert thickness == sorted(thickness)


def test_river_drift_ice_after_a_hard_week():
    temps = _temps((85, 3.0), (14, -7.0))
    assert ice.river(temps, TODAY).status == ice.DRIFT_ICE
    assert ice.river(_temps((99, -1.0)), TODAY).status == ice.OPEN


def test_out_of_season():
    assert ice.out_of_season(date(2026, 7, 1))
    assert not ice.out_of_season(date(2027, 1, 1))


def _hour(t: datetime) -> ForecastHour:
    return ForecastHour(t, -5.0, 1.0, 2.0, 0.0, 0.0, 0.0, 20000.0, 0.0, 0.0, True)


def test_ice_turns_the_hours_of_that_day_red():
    club = Club("c", "Club", "Club", "l", "", None, Point(47.99, 11.34), True)
    # 23:30 UTC on 19 January is already 20 January in Germany.
    hours = [_hour(datetime(2027, 1, 19, 22, tzinfo=timezone.utc)), _hour(datetime(2027, 1, 19, 23, tzinfo=timezone.utc))]
    rows = rowing_forecast(club, hours, None, ice_by_day={TODAY: Light.RED})
    assert ("ice", Light.RED) not in rows[0].assessment.reasons
    assert ("ice", Light.RED) in rows[1].assessment.reasons


LAKE = Lake("l", "Lake", Point(47.9, 11.3), None, None, None, False, mean_depth_m=3)


def test_api_skips_the_model_out_of_season_and_for_warm_water(monkeypatch):
    async def fail(*args):
        raise AssertionError("no air temperatures needed")

    monkeypatch.setattr(api.open_meteo, "fetch_daily_mean", fail)
    summer = datetime(2026, 7, 1, tzinfo=timezone.utc)
    assert asyncio.run(api._ice(None, LAKE, None, summer)).basis == "season"
    winter = datetime(2027, 1, 20, 10, tzinfo=timezone.utc)
    assert asyncio.run(api._ice(None, LAKE, 9.0, winter)).basis == "measured"


def test_api_ice_json(monkeypatch):
    api._ice_temps.clear()

    async def daily(client, lat, lon):
        return [(t.day, t.mean_c) for t in _temps((62, 4.0), (37, -6.0))]

    monkeypatch.setattr(api.open_meteo, "fetch_daily_mean", daily)
    e = asyncio.run(api._ice(None, LAKE, None, datetime(2027, 1, 20, 10, tzinfo=timezone.utc)))
    body = api._ice_json(e)
    assert body["status"] == "frozen" and body["light"] == "red"
    assert body["days"][0]["date"] == "2027-01-20"
    assert api._ice_json(None) == {"status": "unavailable", "light": None, "days": []}


def _pass(day, ice_px, water_px, pixels=1000):
    from rowfrog.sources.lake_ice_satellite import SatellitePass

    return SatellitePass(day, pixels, ice_px, water_px)


def test_satellite_open_water_overrules_a_frozen_model():
    frozen = ice.simulate(_temps((62, 4.0), (37, -6.0)), TODAY, mean_depth_m=4)
    e = ice.with_satellite(frozen, [_pass(TODAY - timedelta(days=1), 10, 690)], TODAY)
    assert e.status == ice.EDGES and e.basis == "satellite" and e.thickness_cm is None
    assert e.days[0].status == ice.EDGES and e.satellite.day == TODAY - timedelta(days=1)


def test_satellite_ice_on_a_cold_lake_means_freezing():
    cold = ice.IceEstimate(ice.OPEN, None, 2.0, "model", 3.0, [ice.IceDay(TODAY, ice.OPEN, 0.0, 2.0)])
    e = ice.with_satellite(cold, [_pass(TODAY, 600, 100)], TODAY)
    assert e.status == ice.FORMING and e.light == Light.RED


def test_satellite_ice_on_a_warm_lake_is_ignored():
    # Haze or low sun classed as ice, as on Starnberger See on 6 March 2026.
    warm = ice.IceEstimate(ice.OPEN, None, 4.6, "model", 0.0, [ice.IceDay(TODAY, ice.OPEN, 0.0, 4.6)])
    e = ice.with_satellite(warm, [_pass(TODAY, 452, 317)], TODAY)
    assert e.status == ice.OPEN and e.basis == "model" and e.satellite is not None


def test_cloudy_or_old_satellite_passes_are_not_used():
    frozen = ice.simulate(_temps((62, 4.0), (37, -6.0)), TODAY, mean_depth_m=4)
    cloudy = _pass(TODAY, 5, 100)  # 10 % of the lake seen
    old = _pass(TODAY - timedelta(days=5), 0, 700)
    assert ice.with_satellite(frozen, [old, cloudy], TODAY) == frozen


def test_satellite_pixel_count():
    from rowfrog.sources.lake_ice_satellite import count, inside

    p = count([0, 0, 1, 2, 3, 3, 3, 5], TODAY)
    assert (p.pixels, p.ice, p.water) == (8, 2, 3)
    assert round(p.ice_share, 2) == 0.4 and round(p.seen_share, 3) == 0.625
    square = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    assert inside(0.5, 0.5, square) and not inside(1.5, 0.5, square)
