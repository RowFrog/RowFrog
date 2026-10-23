"""The publishing job's schedule and satellite picture choices (scripts/publish_static.py)."""

import importlib.util
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from rowerweather.sources import open_meteo, sentinel2

_spec = importlib.util.spec_from_file_location(
    "publish_static", Path(__file__).resolve().parents[2] / "scripts" / "publish_static.py"
)
publish = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(publish)


def utc(day, hour, minute=0):
    return datetime(2026, 10, day, hour, minute, tzinfo=timezone.utc)


def test_weather_is_loaded_once_per_model_run():
    # The 09 UTC run is ready at 11:30; a forecast from 11:40 stays until the 12 UTC run is ready at 14:30.
    assert not publish.due(utc(23, 11, 40), utc(23, 14, 0), 3)
    assert publish.due(utc(23, 11, 40), utc(23, 14, 30), 3)
    assert publish.due(None, utc(23, 14, 0), 3)


def test_lakes_nobody_uses_load_at_four_and_sixteen():
    offset = publish.LAKE_OTHER_OFFSET
    assert publish.last_ready(utc(23, 15, 0), 12, offset) == utc(23, 4, 0)
    assert publish.last_ready(utc(23, 16, 0), 12, offset) == utc(23, 16, 0)
    assert publish.last_ready(utc(23, 2, 0), 12, offset) == utc(22, 16, 0)


def test_ice_map_is_looked_at_twice_a_day():
    assert publish.ice_map_due(utc(23, 5, 0), utc(23, 6, 30))
    assert not publish.ice_map_due(utc(23, 6, 30), utc(23, 17, 59))
    assert publish.ice_map_due(utc(23, 6, 30), utc(23, 18, 0))
    assert not publish.ice_map_due(utc(22, 18, 30), utc(23, 2, 0))


def test_latest_and_clearest_pass():
    passes = [
        sentinel2.Pass(date(2026, 10, 3), 0.05),
        sentinel2.Pass(date(2026, 10, 8), 0.3),
        sentinel2.Pass(date(2026, 10, 13), 0.95),  # lake hidden: no use even as the latest
    ]
    latest, clearest = sentinel2.choose(passes)
    assert latest.day == date(2026, 10, 8) and clearest.day == date(2026, 10, 3)
    assert sentinel2.choose([]) == (None, None)


def test_pictures_are_rendered_only_when_new(tmp_path, monkeypatch):
    rendered = []
    monkeypatch.setattr(sentinel2, "jpeg", lambda client, bbox, w, h, day: rendered.append(day) or b"jpg")
    ring = [(11.0, 48.0), (11.01, 48.0), (11.01, 48.005), (11.0, 48.005)]
    same = sentinel2.Pass(date(2026, 10, 8), 0.05)
    body = publish._picture_meta(None, tmp_path, ring, {}, same, same)
    assert rendered == [date(2026, 10, 8)], "one pass, one picture"
    assert body["latest"]["date"] == body["clearest"]["date"] == "2026-10-08"
    assert (tmp_path / "satellite-clearest.jpg").read_bytes() == b"jpg"
    # A newer cloudy pass: only the latest picture changes, the clear one stays.
    cloudy = sentinel2.Pass(date(2026, 10, 13), 0.4)
    body = publish._picture_meta(None, tmp_path, ring, body, cloudy, None)
    assert rendered == [date(2026, 10, 8), date(2026, 10, 13)]
    assert body["latest"]["lakeCloud"] == 0.4 and body["clearest"]["date"] == "2026-10-08"
    assert body["attribution"] == "Contains modified Copernicus Sentinel data 2026"


def test_club_requests_stay_small():
    # 12 variables count as 1.2 calls per club, a lake point as one.
    assert open_meteo.params_weight(open_meteo.request_params(48, 11, 60)) == 1.2
    assert open_meteo.call_weight(len(open_meteo.LAKE_HOURLY), 15) == 15


def test_dew_point_and_feels_like_are_worked_out():
    payload = {"hourly": {"time": ["2026-10-18T06:00"], "temperature_2m": [10.0], "relative_humidity_2m": [70], "wind_speed_10m": [3.0]}}
    hour = open_meteo.parse(payload)[0]
    assert hour.dew_point_c == 4.8
    assert hour.apparent_temperature_c == 6.7


def test_old_forecast_hours_are_left_out():
    from rowerweather import api

    payload = {"hourly": {"time": [f"2026-10-18T{h:02d}:00" for h in range(3, 9)]}}
    weather = open_meteo.parse(payload)
    kept = api._from_now(weather, utc(18, 5, 40))
    assert [h.time.hour for h in kept] == [5, 6, 7, 8]
