import math

import pytest

from rowerweather.waves import fetch_m, significant_wave_height

# A 10 km (north-south) by about 2 km rectangular lake around 11.30 E, 47.90 N.
LAT0, LON0 = 47.90, 11.30
DLAT_10KM = 10_000 / 111_195
DLON_2KM = 2_000 / (111_195 * math.cos(math.radians(LAT0)))
LAKE = [[
    (LON0, LAT0),
    (LON0 + DLON_2KM, LAT0),
    (LON0 + DLON_2KM, LAT0 + DLAT_10KM),
    (LON0, LAT0 + DLAT_10KM),
]]


def test_wave_height_matches_plan_example():
    # 10 m/s over 10 km gives about 0.5 m, over 2 km about 0.23 m.
    assert significant_wave_height(10, 10_000) == pytest.approx(0.51, abs=0.01)
    assert significant_wave_height(10, 2_000) == pytest.approx(0.23, abs=0.01)


def test_wave_height_zero_without_wind_or_fetch():
    assert significant_wave_height(0, 10_000) == 0
    assert significant_wave_height(10, 0) == 0


def test_wave_height_capped_when_fully_developed():
    assert significant_wave_height(2, 1e9) == pytest.approx(0.2433 * 4 / 9.81)


def test_fetch_from_inside_point_at_south_end():
    # 100 m north of the south shore, mid-width: north wind has ~9.9 km of water.
    lat = LAT0 + 100 / 111_195
    lon = LON0 + DLON_2KM / 2
    assert fetch_m(lon, lat, 0, LAKE) == pytest.approx(9_900, rel=0.01)
    # South wind blows off the nearby shore.
    assert fetch_m(lon, lat, 180, LAKE) == pytest.approx(100, rel=0.02)


def test_fetch_from_boathouse_just_on_land():
    # 50 m south of the shore: north wind still sees the whole lake length.
    lat = LAT0 - 50 / 111_195
    lon = LON0 + DLON_2KM / 2
    assert fetch_m(lon, lat, 0, LAKE) == pytest.approx(10_000, rel=0.01)
    # Wind from the south comes over land.
    assert fetch_m(lon, lat, 180, LAKE) == 0


def test_island_shortens_fetch():
    island_lat = LAT0 + 5_000 / 111_195
    island = [
        (LON0 + DLON_2KM * 0.4, island_lat),
        (LON0 + DLON_2KM * 0.6, island_lat),
        (LON0 + DLON_2KM * 0.6, island_lat + 200 / 111_195),
        (LON0 + DLON_2KM * 0.4, island_lat + 200 / 111_195),
    ]
    lat = LAT0 + 100 / 111_195
    lon = LON0 + DLON_2KM / 2
    assert fetch_m(lon, lat, 0, LAKE + [island]) == pytest.approx(4_900, rel=0.01)
