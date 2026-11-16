"""The long-running water temperature log (rowfrog/water_log.py)."""

import csv
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from rowfrog import water_log
from rowfrog.sources import gkd
from rowfrog.sources import lake_temperature_satellite as sat

NOW = datetime(2026, 11, 17, 6, 5, tzinfo=timezone.utc)


def rows(path):
    with path.open(encoding="utf-8") as f:
        return list(csv.DictReader(f))


def test_satellite_rows_once_and_cloudy_passes_kept(tmp_path):
    lswt = sat.Reading(sat.LSWT, date(2026, 11, 5), 9.4, 30, first=date(2026, 11, 1), last=date(2026, 11, 10))
    landsat = sat.Reading(sat.LANDSAT, date(2026, 11, 14), 8.1, 400, time=datetime(2026, 11, 14, 10, 12, tzinfo=timezone.utc), platform="landsat-9")
    looks = [
        sat.LandsatLook("ammersee", landsat.time, "landsat-9", 0.8, 400, landsat),
        sat.LandsatLook("pilsensee", landsat.time, "landsat-9", 0.1, 0, None),
    ]
    logged = {}
    n = water_log.log_satellite(tmp_path, {"ammersee": [lswt, landsat]}, looks, logged, NOW)
    assert n == 3
    # The next day's look sees the same readings again: nothing new is written.
    assert water_log.log_satellite(tmp_path, {"ammersee": [lswt, landsat]}, looks, logged, NOW + timedelta(days=1)) == 0
    got = rows(tmp_path / "satellite-water-2026-11.csv")
    assert [(r["lake"], r["source"], r["celsius"], r["usable"]) for r in got] == [
        ("ammersee", sat.LSWT, "9.4", "1"),
        ("ammersee", sat.LANDSAT, "8.1", "1"),
        ("pilsensee", sat.LANDSAT, "", "0"),
    ]
    assert got[2]["seen_share"] == "0.1"


def test_old_keys_are_forgotten(tmp_path):
    logged = {"x|landsat|2026-08-01T10:00:00+00:00": "2026-08-01", "y|landsat|2026-11-10T10:00:00+00:00": "2026-11-10"}
    water_log.log_satellite(tmp_path, {}, [], logged, NOW)
    assert list(logged) == ["y|landsat|2026-11-10T10:00:00+00:00"]


def test_station_hours_written_once_in_utc(tmp_path):
    local = ZoneInfo("Europe/Berlin")
    hours = [gkd.WaterTemperature(datetime(2026, 11, 17, h, 0, tzinfo=local), 9.0 + h / 10) for h in (5, 6)]
    logged = {}
    args = ({"gkd:starnberg-16663002": hours}, {"gkd:starnberg-16663002": "Starnberg"}, {"gkd:starnberg-16663002": ["starnberger-see"]})
    assert water_log.log_stations(tmp_path, *args, logged, NOW) == 2
    more = hours + [gkd.WaterTemperature(datetime(2026, 11, 17, 7, 0, tzinfo=local), 9.7)]
    assert water_log.log_stations(tmp_path, {"gkd:starnberg-16663002": more}, *args[1:], logged, NOW) == 1
    got = rows(tmp_path / "station-water-2026-11.csv")
    assert [r["time"] for r in got] == ["2026-11-17T04:00+00:00", "2026-11-17T05:00+00:00", "2026-11-17T06:00+00:00"]
    assert got[0]["lakes"] == "starnberger-see" and got[0]["name"] == "Starnberg"


def test_station_lakes_are_not_club_lakes():
    from rowfrog import locations

    lakes = locations.load().lakes
    assert all(s.id not in lakes for s in water_log.STATION_LAKES)
    ring = water_log.circle(11.19, 48.03, 350)
    assert len(ring) == 48 and abs(max(x for x, _ in ring) - 11.19) > 0.004


def test_archive_goes_next_to_v1_in_the_same_bucket(monkeypatch):
    import importlib.util
    from pathlib import Path

    spec = importlib.util.spec_from_file_location("publish_static_archive", Path(__file__).resolve().parents[2] / "scripts" / "publish_static.py")
    ps = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ps)
    monkeypatch.delenv("WATER_LOG_ARCHIVE", raising=False)
    monkeypatch.setenv("PUBLISH_UPLOAD", "rclone copy /home/rowfrog/site/v1 r2:rowfrog-api/v1 --files-from-raw {files}")
    assert ps.water_log_archive() == "r2:rowfrog-api/archive/water-log"
    monkeypatch.setenv("WATER_LOG_ARCHIVE", "r2:other/log")
    assert ps.water_log_archive() == "r2:other/log"
    monkeypatch.delenv("WATER_LOG_ARCHIVE")
    monkeypatch.delenv("PUBLISH_UPLOAD")
    assert ps.water_log_archive() is None
