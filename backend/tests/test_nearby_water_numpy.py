"""nearby_water works out all hours at once with numpy; it must give exactly what the old
hour-by-hour loop (_nearby_water_loop) gives, None values and every float bit included."""

import random
from dataclasses import replace
from datetime import datetime, timedelta, timezone

import pytest

from rowfrog import api, lake_view
from rowfrog.sources import open_meteo

NOW = datetime(2026, 11, 22, 4, tzinfo=timezone.utc)


def _hour(t: datetime) -> open_meteo.ForecastHour:
    return open_meteo.ForecastHour(
        time=t, temperature_c=12.0, wind_speed_ms=2.0, wind_gust_ms=4.0, wind_from_deg=240.0, cloud_cover_pct=40,
        cloud_cover_low_pct=10, visibility_m=25_000, precipitation_mm=0.0, cape_jkg=0, is_day=8 <= t.hour <= 16,
        weather_code=3, apparent_temperature_c=11.0, humidity_pct=70, dew_point_c=5.5, pressure_hpa=1016.0,
        cloud_cover_mid_pct=30, cloud_cover_high_pct=20,
    )


def _weather(grid, seed: int) -> list:
    rnd = random.Random(seed)

    def maybe(value):
        return None if rnd.random() < 0.05 else value

    def hour(i: int):
        return replace(
            _hour(NOW + timedelta(hours=i)),
            wind_speed_ms=maybe(rnd.uniform(0, 12)),
            wind_gust_ms=maybe(rnd.uniform(0, 20)),
            wind_from_deg=maybe(rnd.uniform(0, 360)),
            visibility_m=maybe(rnd.choice([150, 900, 5000, 30000])),
            precipitation_mm=maybe(rnd.uniform(0, 4)),
            weather_code=rnd.choice([0, 3, 61, 95, 96]),
            cape_jkg=rnd.uniform(0, 1500),
        )

    return [[hour(i) for i in range(48)] for _ in grid.samples]


def _clubs(n: int) -> list:
    clubs = [c for c in api._locations.clubs.values() if api.outlines.load(c.lake_id)]
    return clubs[:: max(1, len(clubs) // n)][:n]


@pytest.mark.parametrize("club", _clubs(12), ids=lambda c: c.id)
def test_numpy_gives_exactly_what_the_loop_gives(club):
    pytest.importorskip("numpy")
    grid = api.lake_grid(club.lake_id, api.outlines.load(club.lake_id))
    weather = _weather(grid, sum(map(ord, club.id)))
    lat, lon = club.launch_point.lat, club.launch_point.lon
    for water_temp in (None, 8.0):
        assert lake_view.nearby_water(grid, weather, lat, lon, water_temp) == lake_view._nearby_water_loop(
            grid, weather, lat, lon, water_temp
        )


def test_without_numpy_the_loop_is_used(monkeypatch):
    club = _clubs(1)[0]
    grid = api.lake_grid(club.lake_id, api.outlines.load(club.lake_id))
    weather = _weather(grid, 3)
    lat, lon = club.launch_point.lat, club.launch_point.lon
    expected = lake_view._nearby_water_loop(grid, weather, lat, lon)
    monkeypatch.setattr(lake_view, "np", None)
    assert lake_view.nearby_water(grid, weather, lat, lon) == expected
