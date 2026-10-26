"""The publishing job's schedule and satellite picture choices (scripts/publish_static.py)."""

import importlib.util
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from rowfrog.sources import open_meteo, sentinel2

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
        sentinel2.Pass(date(2026, 10, 13), 0.95),  # the latest, however cloudy
    ]
    latest, mostly_clear, clearest = sentinel2.choose(passes)
    assert latest.day == date(2026, 10, 13) and clearest.day == date(2026, 10, 3)
    assert mostly_clear.day == date(2026, 10, 8)
    assert sentinel2.choose([]) == (None, None, None)


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
    assert "mostlyClear" not in body


def test_mostly_clear_picture_only_when_it_adds_something(tmp_path, monkeypatch):
    monkeypatch.setattr(sentinel2, "jpeg", lambda client, bbox, w, h, day: b"jpg")
    ring = [(11.0, 48.0), (11.01, 48.0), (11.01, 48.005), (11.0, 48.005)]
    clear = sentinel2.Pass(date(2026, 10, 3), 0.05)
    mostly = sentinel2.Pass(date(2026, 10, 8), 0.25)
    cloudy = sentinel2.Pass(date(2026, 10, 13), 0.9)
    body = publish._picture_meta(None, tmp_path, ring, {}, cloudy, clear, mostly)
    assert body["mostlyClear"]["date"] == "2026-10-08"
    # The latest pass itself is mostly clear: no third picture.
    body = publish._picture_meta(None, tmp_path, ring, {}, mostly, clear, mostly)
    assert "mostlyClear" not in body


def test_club_requests_stay_small():
    # 14 variables count as 1.4 calls per club, a lake point as one.
    assert open_meteo.params_weight(open_meteo.request_params(48, 11, 60)) == 1.4
    assert open_meteo.call_weight(len(open_meteo.LAKE_HOURLY), 15) == 15


def test_dew_point_and_feels_like_are_worked_out():
    payload = {"hourly": {"time": ["2026-10-18T06:00"], "temperature_2m": [10.0], "relative_humidity_2m": [70], "wind_speed_10m": [3.0]}}
    hour = open_meteo.parse(payload)[0]
    assert hour.dew_point_c == 4.8
    assert hour.apparent_temperature_c == 6.7


def test_old_forecast_hours_are_left_out():
    from rowfrog import api

    payload = {"hourly": {"time": [f"2026-10-18T{h:02d}:00" for h in range(3, 9)]}}
    weather = open_meteo.parse(payload)
    kept = api._from_now(weather, utc(18, 5, 40))
    assert [h.time.hour for h in kept] == [5, 6, 7, 8]


def test_only_clubs_people_load_count_as_used(monkeypatch):
    from types import SimpleNamespace

    from rowfrog import locations

    monkeypatch.setattr(publish, "usage", None)
    clubs, _, counted = publish.usage_now()
    assert not counted and clubs == set(locations.load(catalog_paths=()).clubs)

    loaded = SimpleNamespace(used=lambda days: SimpleNamespace(clubs={"mrc-1880": 4}, lakes={"ammersee": 1}))
    monkeypatch.setattr(publish, "usage", loaded)
    clubs, lakes, counted = publish.usage_now()
    assert counted and clubs == {"mrc-1880"}
    assert lakes == {"starnberger-see", "ammersee"}


def test_other_models_load_only_for_confirmed_clubs_once_per_run(monkeypatch):
    from rowfrog import api, locations

    asked = []

    async def fake_many(client, points, hours=48, hourly=open_meteo.HOURLY, models="icon_seamless"):
        asked.append((models, len(points)))
        return [[] for _ in points]

    monkeypatch.setattr(open_meteo, "fetch_many", fake_many)
    every = list(locations.load().clubs.values())
    confirmed = [c for c in every if c.source is None]
    others = [c for c in every if c.source is not None][:5]
    state = publish.State(None)
    pairs = publish.model_weather(state, confirmed + others, utc(23, 14, 30))
    assert len(asked) == 3, "one request per model"
    assert all(n == len(confirmed) for _, n in asked)
    assert {club.id for club, _ in pairs} == {c.id for c in confirmed}
    asked.clear()
    publish.model_weather(state, confirmed, utc(23, 15, 0))
    assert asked == [], "nothing new until the next model run"
    for key in list(api._primed_weather):
        if "@" in key:
            del api._primed_weather[key]


def test_warn_cells_are_looked_up_once_and_warnings_read_in_bulk(monkeypatch):
    from rowfrog import api, locations
    from rowfrog.sources import dwd_warnings

    looked, bulk = [], []

    async def fake_cell(client, lon, lat):
        looked.append((lon, lat))
        return None if lat < 47.5 else 800000000 + len(looked) % 3

    async def fake_bulk(client, cells):
        bulk.append(sorted(cells))
        return {c: [] for c in cells}

    monkeypatch.setattr(dwd_warnings, "fetch_warn_cell", fake_cell)
    monkeypatch.setattr(dwd_warnings, "fetch_local_warnings_for_cells", fake_bulk)
    clubs = [c for c in locations.load().clubs.values() if c.country == "de"][:20]
    state = publish.State(None)
    api._primed_local_warnings.clear()
    publish.local_warnings(state, clubs, utc(25, 12))
    assert len(looked) == 20 and len(bulk) == 1
    assert set(api._primed_local_warnings) == {c.id for c in clubs}
    publish.local_warnings(state, clubs, utc(25, 12, 30))
    assert len(looked) == 20, "cells are kept between runs"
    publish.local_warnings(state, clubs, utc(25, 12) + timedelta(days=publish.WARN_CELL_DAYS + 1))
    assert len(looked) == 40, "and looked up again after a while"
    api._primed_local_warnings.clear()


def test_failed_bulk_warnings_leave_each_club_to_ask_itself(monkeypatch):
    from rowfrog import api, locations
    from rowfrog.sources import dwd_warnings

    async def fake_cell(client, lon, lat):
        return 809188139

    async def broken(client, cells):
        raise dwd_warnings.httpx.HTTPError("down")

    monkeypatch.setattr(dwd_warnings, "fetch_warn_cell", fake_cell)
    monkeypatch.setattr(dwd_warnings, "fetch_local_warnings_for_cells", broken)
    api._primed_local_warnings.clear()
    publish.local_warnings(publish.State(None), list(locations.load().clubs.values())[:3], utc(25, 12))
    assert api._primed_local_warnings == {}


def test_refresh_block_tells_the_app_how_often_a_club_is_renewed():
    assert publish.refresh_block(True) == {"used": True, "fileEveryHours": 0.5, "weatherEveryHours": 3}
    slow = publish.refresh_block(False)
    assert slow["used"] is False and slow["fileEveryHours"] == 6 and slow["weatherEveryHours"] == 12


def test_local_warnings_skip_clubs_outside_germany(monkeypatch):
    from rowfrog import api, locations
    from rowfrog.sources import dwd_warnings

    looked = []

    async def fake_cell(client, lon, lat):
        looked.append((lon, lat))
        return 809188139

    async def fake_bulk(client, cells):
        return {c: [] for c in cells}

    monkeypatch.setattr(dwd_warnings, "fetch_warn_cell", fake_cell)
    monkeypatch.setattr(dwd_warnings, "fetch_local_warnings_for_cells", fake_bulk)
    every = locations.load().clubs.values()
    clubs = [c for c in every if c.country == "de"][:2] + [c for c in every if c.country != "de"][:3]
    api._primed_local_warnings.clear()
    publish.local_warnings(publish.State(None), clubs, utc(25, 12))
    assert len(looked) == 2
    assert set(api._primed_local_warnings) == {c.id for c in clubs[:2]}
    api._primed_local_warnings.clear()


def test_big_lakes_get_sharp_tiles_once_per_pass(tmp_path, monkeypatch):
    rendered = []
    monkeypatch.setattr(sentinel2, "jpeg", lambda client, bbox, w, h, day: rendered.append((w, h)) or b"jpg")
    monkeypatch.setattr(publish, "sharp_tiles_left", 1000)
    # About 30 x 20 km: 1280 px wide in the card, about 3300 px at 10 m, so tiles but no overview.
    ring = [(11.0, 48.0), (11.4, 48.0), (11.4, 48.17), (11.0, 48.17)]
    day = sentinel2.Pass(date(2026, 10, 8), 0.05)
    body = publish._picture_meta(None, tmp_path, ring, {}, day, day)
    sharp = body["sharp"]
    assert 3000 < sharp["width"] < 4000 and sharp["columns"] == 4 and sharp["rows"] == 3
    tiles = sharp["rows"] * sharp["columns"]
    assert len(rendered) == 1 + tiles, "the card's picture and the tiles of the latest; the clearest copies them"
    assert body["latest"]["tiles"] == "satellite-latest-tiles" and "overview" not in body["latest"]
    assert len(list((tmp_path / "satellite-clearest-tiles").iterdir())) == tiles
    # Nothing new: nothing rendered again.
    body = publish._picture_meta(None, tmp_path, ring, body, None, None)
    assert len(rendered) == 1 + tiles and body["clearest"]["tiles"] == "satellite-clearest-tiles"


def test_tiles_line_up_with_the_picture():
    box = (11.0, 48.0, 11.3, 48.1)
    grid = sentinel2.tiles(box, 2500, 1100)
    assert len(grid) == 3 * 2
    assert grid[0][2][0] == 11.0 and grid[0][2][3] == 48.1  # top left
    assert abs(grid[-1][2][2] - 11.3) < 1e-9 and abs(grid[-1][2][1] - 48.0) < 1e-9  # bottom right
    assert (grid[-1][3], grid[-1][4]) == (2500 - 2048, 1100 - 1024)


def test_only_the_biggest_lakes_get_an_overview():
    assert sentinel2.overview_size(3600, 2900) is None
    assert sentinel2.overview_size(7800, 4350) == (2500, 1394)


def test_tiles_wait_for_a_later_run_when_the_run_has_used_its_share(tmp_path, monkeypatch):
    monkeypatch.setattr(sentinel2, "jpeg", lambda client, bbox, w, h, day: b"jpg")
    monkeypatch.setattr(publish, "sharp_tiles_left", 3)
    ring = [(11.0, 48.0), (11.4, 48.0), (11.4, 48.17), (11.0, 48.17)]
    day = sentinel2.Pass(date(2026, 10, 8), 0.05)
    body = publish._picture_meta(None, tmp_path, ring, {}, day, day)
    assert "tiles" not in body["latest"] and publish._lacks_sharp(body, ring)
    monkeypatch.setattr(publish, "sharp_tiles_left", 100)
    body = publish._picture_meta(None, tmp_path, ring, body, day, day)
    assert body["latest"]["tiles"] and not publish._lacks_sharp(body, ring)


def test_small_lakes_get_no_sharp_files(tmp_path, monkeypatch):
    monkeypatch.setattr(sentinel2, "jpeg", lambda client, bbox, w, h, day: b"jpg")
    ring = [(11.0, 48.0), (11.01, 48.0), (11.01, 48.005), (11.0, 48.005)]
    day = sentinel2.Pass(date(2026, 10, 8), 0.05)
    body = publish._picture_meta(None, tmp_path, ring, {}, day, day)
    assert "sharp" not in body and "tiles" not in body["latest"] and not publish._lacks_sharp(body, ring)
