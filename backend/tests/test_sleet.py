"""Schneeregen from Open-Meteo's rain and snowfall, asked only in the cold band (rowfrog/sleet.py)."""

import importlib.util
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from rowfrog import sleet
from rowfrog.sources import open_meteo

_spec = importlib.util.spec_from_file_location(
    "publish_static_sleet", Path(__file__).resolve().parents[2] / "scripts" / "publish_static.py"
)
publish = importlib.util.module_from_spec(_spec)
sys.modules["publish_static_sleet"] = publish
_spec.loader.exec_module(publish)

NOW = datetime(2026, 11, 15, 12, tzinfo=timezone.utc)


def _hour(offset: int, temp: float | None, mm: float = 0.0, code: int = 3) -> open_meteo.ForecastHour:
    return open_meteo.ForecastHour(
        time=NOW + timedelta(hours=offset), temperature_c=temp, wind_speed_ms=2, wind_gust_ms=4, wind_from_deg=180,
        cloud_cover_pct=100, cloud_cover_low_pct=None, visibility_m=20000, precipitation_mm=mm, cape_jkg=0,
        is_day=True, weather_code=code,
    )


def test_the_cold_band_needs_wet_hours_near_freezing_within_two_days(monkeypatch):
    monkeypatch.delenv("RW_SLEET", raising=False)
    monkeypatch.delenv("RW_SLEET_MIN_C", raising=False)
    monkeypatch.delenv("RW_SLEET_MAX_C", raising=False)
    assert sleet.in_cold_band([_hour(5, 1.5, 0.4, 61)], NOW)
    assert sleet.in_cold_band([_hour(5, -1.0, 0.0, 71)], NOW)  # snow by code alone
    assert not sleet.in_cold_band([_hour(5, 1.5)], NOW)  # dry
    assert not sleet.in_cold_band([_hour(5, 9.0, 2.0, 63)], NOW)  # too warm
    assert not sleet.in_cold_band([_hour(5, -8.0, 1.0, 73)], NOW)  # too cold for rain
    assert not sleet.in_cold_band([_hour(60, 1.0, 1.0, 61)], NOW)  # beyond two days
    # No forecast yet: the cold months only.
    assert sleet.in_cold_band(None, NOW)
    assert not sleet.in_cold_band(None, NOW.replace(month=7))


def test_the_pi_settings_switch_it_off_and_move_the_band(monkeypatch):
    monkeypatch.setenv("RW_SLEET", "off")
    assert not sleet.enabled()
    assert not sleet.in_cold_band([_hour(5, 1.5, 0.4, 61)], NOW)
    assert not sleet.in_cold_band(None, NOW)
    monkeypatch.setenv("RW_SLEET", "on")
    monkeypatch.setenv("RW_SLEET_MAX_C", "1")
    assert not sleet.in_cold_band([_hour(5, 1.5, 0.4, 61)], NOW)
    assert sleet.band() == (-2.0, 1.0)


def test_rain_and_snow_in_one_hour_is_68_or_69():
    assert sleet.mixed_code(61, 0.6, 0.3, 0.2) == 68
    assert sleet.mixed_code(73, 3.0, 1.5, 1.1) == 69
    assert sleet.mixed_code(61, 0.6, 0.6, 0.0) == 61  # rain only
    assert sleet.mixed_code(71, 0.4, 0.0, 0.3) == 71  # snow only
    assert sleet.mixed_code(66, 0.6, 0.3, 0.2) == 66  # freezing rain stays
    assert sleet.mixed_code(96, 5.0, 3.0, 1.0) == 96  # hail stays
    assert sleet.mixed_code(61, 0.6, None, None) == 61


def test_parse_marks_mixed_hours_only_when_rain_and_snowfall_were_asked():
    hourly = {
        "time": ["2026-11-15T12:00", "2026-11-15T13:00", "2026-11-15T14:00"],
        "temperature_2m": [1.0, 1.2, 1.1],
        "precipitation": [0.0, 0.8, 0.5],
        "weather_code": [3, 61, 61],
    }
    # Each row's rain fell in the hour before it, so the 12:00 hour gets the 13:00 row (decision 0043).
    assert [h.weather_code for h in open_meteo.parse({"hourly": hourly})] == [61, 61, None]
    asked = {**hourly, "rain": [0.0, 0.5, 0.5], "snowfall": [0.0, 0.21, 0.0]}
    assert [h.weather_code for h in open_meteo.parse({"hourly": asked})] == [68, 61, None]


def test_the_extra_cost_is_counted_per_club(monkeypatch):
    publish.RUN = publish.RunCounts()
    monkeypatch.setattr(publish, "RUN", publish.RUN)

    class Club:
        def __init__(self, i):
            self.id = i

    publish.count_sleet([Club("a"), Club("b")], publish.FETCH_HOURS)
    # 14 variables count 1.4 calls a point, 16 count 1.6: 0.2 more for each club.
    assert round(publish.RUN.sleet_calls, 2) == 0.4
    assert publish.RUN.sleet_clubs == {"a", "b"}
    monkeypatch.delenv("RW_SLEET", raising=False)
    assert "2 clubs in the cold band" in publish.sleet_line()
