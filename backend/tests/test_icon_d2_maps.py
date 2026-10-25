import pytest

np = pytest.importorskip("numpy")

from rowfrog.sources import icon_d2_maps as maps  # noqa: E402


def test_a_club_is_well_inside_its_tile():
    for lat, lon in [(47.99, 11.35), (47.37, 8.54), (52.5, 13.4), (48.2, 16.4), (46.0, 9.0)]:
        tile = maps.tile_for(lat, lon)
        assert tile.west + 1.5 <= lon <= tile.east - 1.5
        assert tile.south + 1.0 <= lat <= tile.north - 1.0


def test_tiles_are_shared_by_nearby_clubs():
    assert maps.tile_for(47.99, 11.35) == maps.tile_for(47.85, 11.15)


def test_values_fit_a_byte_and_missing_stays_missing():
    enc = maps.VALUES["temperature"]
    out = maps._encode(np.array([-50.0, -40.0, 0.0, 20.2, 80.0, np.nan]), enc)
    assert out.tolist() == [0, 0, 100, 150, 254, maps.MISSING]


def test_feels_like_matches_the_forecasts_formula():
    from rowfrog.sources.open_meteo import apparent_temperature

    got = maps.feels_like(np.array([10.0]), np.array([80.0]), np.array([5.0]))[0]
    assert got == pytest.approx(apparent_temperature(10.0, 80.0, 5.0), abs=0.06)


def test_rain_is_the_hourly_rate_between_steps():
    total = np.array([0.0, 3.0, 6.0, np.nan])
    assert maps.rain_rate(total, None, 0).tolist()[:3] == [0, 0, 0]
    got = maps.rain_rate(total, np.array([0.0, 1.5, 6.5, 1.0]), 3)
    assert got[:3].tolist() == pytest.approx([0.0, 0.5, 0.0])
    assert np.isnan(got[3])
