from datetime import date, datetime, timedelta, timezone

import pytest

from rowfrog import api, ice, water_estimate
from rowfrog.sources import lake_temperature_satellite as sat

DAY = date(2026, 10, 9)


def _air(days: int, celsius: float, start: date = DAY) -> list[ice.DayTemperature]:
    return [ice.DayTemperature(start + timedelta(days=i), celsius) for i in range(days + 1)]


def _landsat(day: date, celsius: float) -> sat.Reading:
    when = datetime.combine(day, datetime.min.time(), tzinfo=timezone.utc).replace(hour=10)
    return sat.Reading(sat.LANDSAT, day, celsius, 800, time=when, platform="landsat-9")


def test_carry_moves_the_reading_towards_the_air():
    warm = water_estimate.carry(DAY, 17.7, _air(10, 8.0), DAY + timedelta(days=10))
    assert 8.0 < warm < 17.7
    # A deeper layer changes more slowly.
    assert water_estimate.carry(DAY, 17.7, _air(10, 8.0), DAY + timedelta(days=10), layer_m=30) > warm
    # The reading's own day and days after `until` do not count.
    assert water_estimate.carry(DAY, 17.7, _air(10, 8.0), DAY) == 17.7


def test_carry_never_goes_below_freezing():
    assert water_estimate.carry(DAY, 1.0, _air(20, -10.0), DAY + timedelta(days=20)) == 0.0


def test_estimate_uses_the_newest_recent_reading():
    readings = [_landsat(DAY - timedelta(days=8), 19.0), _landsat(DAY, 17.7)]
    e = water_estimate.estimate(readings, _air(3, 17.7), DAY + timedelta(days=3))
    assert e.reading.day == DAY
    assert e.celsius == 17.7
    assert water_estimate.estimate(readings, [], DAY + timedelta(days=water_estimate.MAX_AGE_DAYS + 1)) is None
    assert water_estimate.estimate([], [], DAY) is None


def test_lswt_periods_are_thirds_of_a_month():
    assert sat.lswt_period(date(2026, 10, 1)) == (date(2026, 10, 1), date(2026, 10, 10))
    assert sat.lswt_period(date(2026, 10, 11)) == (date(2026, 10, 11), date(2026, 10, 20))
    assert sat.lswt_period(date(2026, 10, 21)) == (date(2026, 10, 21), date(2026, 10, 31))
    assert sat.lswt_period(date(2026, 2, 21)) == (date(2026, 2, 21), date(2026, 2, 28))


def test_merge_drops_doubles_and_old_readings():
    today = DAY + timedelta(days=5)
    old = {"simssee": [_landsat(DAY - timedelta(days=40), 21.0), _landsat(DAY, 17.6)]}
    new = {"simssee": [_landsat(DAY, 17.6), _landsat(DAY + timedelta(days=1), 17.2)], "forggensee": [_landsat(DAY, 14.5)]}
    merged = sat.merge(old, new, today, 30)
    assert [r.day for r in merged["simssee"]] == [DAY, DAY + timedelta(days=1)]
    assert set(merged) == {"simssee", "forggensee"}


def test_read_lswt_keeps_good_pixels_away_from_the_shore(tmp_path):
    rasterio = pytest.importorskip("rasterio")
    import numpy as np
    from rasterio.transform import from_origin

    # A 1 km grid (0.01°) over a square lake of 0.1°; the shore row and column are much warmer.
    step = 0.01
    transform = from_origin(11.0, 48.1, step, step)
    temperature = np.full((10, 10), int(16.0 / 0.01), dtype="int16")
    temperature[0, :] = temperature[:, 0] = int(25.0 / 0.01)
    quality = np.full((10, 10), 5, dtype="int8")
    quality[5, 5] = 2  # a bad pixel in the middle
    temperature[5, 5] = int(30.0 / 0.01)
    for name, data, dtype in (("t.tif", temperature, "int16"), ("q.tif", quality, "int8")):
        with rasterio.open(
            tmp_path / name, "w", driver="GTiff", width=10, height=10, count=1, dtype=dtype, crs="EPSG:4326", transform=transform
        ) as ds:
            if name == "t.tif":
                ds.scales, ds.offsets = (0.01,), (273.15,)
                ds.nodata = -32768
            ds.write(data, 1)
    ring = [(11.0, 48.0), (11.1, 48.0), (11.1, 48.1), (11.0, 48.1)]
    found = sat.read_lswt(str(tmp_path / "t.tif"), str(tmp_path / "q.tif"), date(2026, 10, 11), {"square": ring})
    r = found["square"]
    assert r.source == sat.LSWT
    assert r.celsius == 16.0
    assert (r.first, r.last, r.day) == (date(2026, 10, 11), date(2026, 10, 20), date(2026, 10, 15))


def test_forecast_json_carries_the_satellite_estimate():
    e = water_estimate.WaterEstimate(16.9, _landsat(DAY, 17.7))
    block = api._water_estimate_json(e)
    assert block["celsius"] == 16.9 and block["basis"] == "satellite"
    assert block["reading"] == {
        "source": "landsat",
        "platform": "landsat-9",
        "date": "2026-10-09",
        "from": None,
        "to": None,
        "celsius": 17.7,
    }
    assert api._water_estimate_json(None) is None


def test_club_forecast_without_station_gets_the_satellite_estimate(monkeypatch):
    import httpx
    from fastapi.testclient import TestClient

    from rowfrog.sources import open_meteo
    from tests.test_dwd_warnings import PAYLOAD, _reset, _serve

    async def fake_fetch(client, lat, lon, hours=48, models="icon_seamless"):
        return open_meteo.parse(PAYLOAD)

    async def no_outlook(*args, **kwargs):
        return None

    async def daily(client, lat, lon):
        return [(date(2026, 10, 10) + timedelta(days=i), 10.0) for i in range(16)]

    monkeypatch.setattr(open_meteo, "fetch", fake_fetch)
    monkeypatch.setattr(open_meteo, "fetch_outlook", no_outlook)
    monkeypatch.setattr(open_meteo, "fetch_daily_mean", daily)
    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(lambda request: httpx.Response(200, json={"features": []})))
    _reset()
    api._ice_temps.clear()
    club = api._locations.clubs_on("simssee")[0]
    monkeypatch.setitem(api._satellite_water, "simssee", [_landsat(date(2026, 10, 15), 15.0)])
    body = TestClient(api.app).get(f"/clubs/{club.id}/forecast").json()
    assert body["waterTemperature"] is None
    assert 10.0 < body["waterEstimate"]["celsius"] < 15.0
    assert body["waterEstimate"]["reading"]["date"] == "2026-10-15"
    assert body["attribution"][-1] == api.SATELLITE_WATER_CREDIT["landsat"]
    # A lake without readings has no estimate and no extra credit.
    other = TestClient(api.app).get("/clubs/mrc-1880/forecast").json()
    assert other["waterEstimate"] is None
    _reset()
