"""The publishing job's schedule and satellite picture choices (scripts/publish_static.py)."""

import importlib.util
import sys
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


def test_weather_waits_for_the_model_run_open_meteo_really_has(monkeypatch):
    # 12 UTC run not on Open-Meteo yet at 14:31: the 09 UTC run (there since 11:25) stays, no call.
    monkeypatch.setattr(publish, "MODEL_RUN", open_meteo.ModelRun(utc(23, 9), utc(23, 11, 25)))
    assert not publish.due(utc(23, 11, 35), utc(23, 14, 31), 3)
    # It came at 14:40: the 15:00 run loads it, and the forecast from 15:00 then stays.
    monkeypatch.setattr(publish, "MODEL_RUN", open_meteo.ModelRun(utc(23, 12), utc(23, 14, 40)))
    assert publish.due(utc(23, 11, 35), utc(23, 15, 0), 3)
    assert not publish.due(utc(23, 15, 0), utc(23, 15, 30), 3)
    # Clubs on the 6-hour plan take the 12 UTC run, not the 09 UTC one.
    assert publish.last_ready(utc(23, 15, 0), 6) == utc(23, 14, 40)
    monkeypatch.setattr(publish, "MODEL_RUN", open_meteo.ModelRun(utc(23, 9), utc(23, 11, 25)))
    assert publish.last_ready(utc(23, 12, 0), 6) == utc(23, 8, 25)


def test_newest_run_reads_open_meteos_meta_file():
    import asyncio

    import httpx

    def answer(request):
        assert request.url.path == "/data/dwd_icon_d2/static/meta.json"
        return httpx.Response(200, json={"last_run_initialisation_time": 1793268000,
                                         "last_run_availability_time": 1793276400})

    async def ask():
        async with httpx.AsyncClient(transport=httpx.MockTransport(answer)) as client:
            return await open_meteo.newest_run(client)

    run = asyncio.run(ask())
    assert run.started == datetime.fromtimestamp(1793268000, timezone.utc)
    assert run.available - run.started == timedelta(hours=2, minutes=20)


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
    for key in list(api.prepared.weather):
        if "@" in key:
            del api.prepared.weather[key]


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
    api.prepared.local_warnings.clear()
    publish.local_warnings(state, clubs, utc(25, 12))
    assert len(looked) == 20 and len(bulk) == 1
    assert set(api.prepared.local_warnings) == {c.id for c in clubs}
    publish.local_warnings(state, clubs, utc(25, 12, 30))
    assert len(looked) == 20, "cells are kept between runs"
    publish.local_warnings(state, clubs, utc(25, 12) + timedelta(days=publish.WARN_CELL_DAYS + 1))
    assert len(looked) == 40, "and looked up again after a while"
    api.prepared.local_warnings.clear()


def test_failed_bulk_warnings_leave_each_club_to_ask_itself(monkeypatch):
    from rowfrog import api, locations
    from rowfrog.sources import dwd_warnings

    async def fake_cell(client, lon, lat):
        return 809188139

    async def broken(client, cells):
        raise dwd_warnings.httpx.HTTPError("down")

    monkeypatch.setattr(dwd_warnings, "fetch_warn_cell", fake_cell)
    monkeypatch.setattr(dwd_warnings, "fetch_local_warnings_for_cells", broken)
    api.prepared.local_warnings.clear()
    publish.local_warnings(publish.State(None), list(locations.load().clubs.values())[:3], utc(25, 12))
    assert api.prepared.local_warnings == {}


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
    api.prepared.local_warnings.clear()
    publish.local_warnings(publish.State(None), clubs, utc(25, 12))
    assert len(looked) == 2
    assert set(api.prepared.local_warnings) == {c.id for c in clubs[:2]}
    api.prepared.local_warnings.clear()


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


def test_clubs_without_an_outline_get_a_place_around_their_launch_point():
    import dataclasses

    from rowfrog import locations

    clubs = locations.load().clubs.values()
    # A river club whose river has no section (no outline).
    river = dataclasses.replace(next(c for c in clubs if c.lake_id.startswith("river-")), lake_id="river-without-a-section")
    lake = next(c for c in clubs if c.lake_id == "starnberger-see")
    places = publish.club_places([river, lake])
    assert list(places) == [f"club-{river.id}"]
    (west, south, east, north), width, height = sentinel2.frame(places[f"club-{river.id}"][0])
    assert (width, height) == (400, 300)
    assert west < river.launch_point.lon < east and south < river.launch_point.lat < north


def test_big_lakes_nobody_uses_get_no_tiles(tmp_path, monkeypatch):
    monkeypatch.setattr(sentinel2, "jpeg", lambda client, bbox, w, h, day: b"jpg")
    monkeypatch.setattr(publish, "sharp_tiles_left", 1000)
    ring = [(11.0, 48.0), (11.4, 48.0), (11.4, 48.17), (11.0, 48.17)]
    day = sentinel2.Pass(date(2026, 10, 8), 0.05)
    used = publish._picture_meta(None, tmp_path, ring, {}, day, day)
    assert (tmp_path / "satellite-latest-tiles").exists()
    # No longer used: the tiles go, the pictures stay.
    body = publish._picture_meta(None, tmp_path, ring, used, None, None, sharp_ok=False)
    assert "sharp" not in body and "tiles" not in body["latest"] and body["latest"]["date"] == "2026-10-08"
    assert not (tmp_path / "satellite-latest-tiles").exists() and (tmp_path / "satellite-latest.jpg").exists()


def test_river_sections_get_a_picture_of_about_10_km_around_their_clubs():
    from rowfrog import locations

    box = (8.65, 50.05, 8.79, 50.14)
    section = locations.RiverSection("river-main", "Offenbach", "river", 14.5, None, None, box)
    lakes = {
        "river-main-offenbach": locations.Lake("river-main-offenbach", "Main", locations.Point(50.1, 8.72), None, None, None, False, "river", section=section),
        "starnberger-see": locations.load().lakes["starnberger-see"],
    }
    places = publish.river_places(lakes, ["river-main-offenbach", "starnberger-see"])
    assert list(places) == ["river-main-offenbach"]
    (west, south, east, north), width, height = sentinel2.frame(places["river-main-offenbach"][0])
    assert west <= 8.65 and east >= 8.79 and width < 1300


def test_new_used_clubs_per_day_can_be_capped(monkeypatch):
    from types import SimpleNamespace

    week = {"mrc-1880": 9, "real-new": 5, "fake-1": 1, "fake-2": 1}
    today = {"mrc-1880": 2, "real-new": 5, "fake-1": 1, "fake-2": 1}
    assert publish.capped(week, today, 1) == {"mrc-1880", "real-new"}
    assert publish.capped(week, today, 10) == set(week)

    counts = {7: SimpleNamespace(clubs=week, lakes={}), 1: SimpleNamespace(clubs=today, lakes={})}
    monkeypatch.setattr(publish, "usage", SimpleNamespace(used=lambda days: counts[days]))
    assert publish.NEW_USED_PER_DAY == 0, "off until the owner switches it on before launch"
    clubs, _, _ = publish.usage_now()
    assert clubs == set(week)
    monkeypatch.setattr(publish, "NEW_USED_PER_DAY", 1)
    clubs, _, _ = publish.usage_now()
    assert clubs == {"mrc-1880", "real-new"}


def test_the_publisher_uses_only_public_names_of_the_api():
    """The publisher hands its bulk loads over through api.prepared, never by
    filling api.py's private globals, so renaming one of those can't break
    publishing unnoticed (code review finding 4)."""
    import re

    source = (Path(__file__).resolve().parents[2] / "scripts" / "publish_static.py").read_text()
    assert re.findall(r"\bapi\._\w+", source) == []


def test_a_file_that_only_differs_in_build_time_is_left_as_published(tmp_path):
    path = tmp_path / "clubs" / "x" / "forecast"
    publish.write(path, {"clubId": "x", "generatedAt": "2026-11-06T15:00:00+00:00", "hours": [1.5, 2]})
    first = path.read_bytes()
    # Same content half an hour later: the published bytes stay, so the gateway answers 304.
    publish.write(path, {"clubId": "x", "generatedAt": "2026-11-06T15:30:00+00:00", "hours": [1.5, 2]})
    assert path.read_bytes() == first
    # A real change is written, with its new build time.
    publish.write(path, {"clubId": "x", "generatedAt": "2026-11-06T16:00:00+00:00", "hours": [3]})
    assert b"16:00:00" in path.read_bytes()
    # Lists and files without a build time are compared whole.
    other = tmp_path / "lakes" / "index"
    publish.write(other, [1, 2])
    publish.write(other, [1, 2, 3])
    assert other.read_text() == "[1,2,3]"


def test_nothing_is_handed_on_without_the_setting(monkeypatch, capsys):
    monkeypatch.delenv("PUBLISH_CLUBS_DONE", raising=False)
    publish.clubs_written()
    assert capsys.readouterr().out == ""


def test_the_club_forecasts_are_handed_on_once_written(monkeypatch, tmp_path, capsys):
    marker = tmp_path / "done"
    monkeypatch.setenv("PUBLISH_CLUBS_DONE", f"{sys.executable} -c 'open(\"{marker}\", \"w\").write(\"x\")'")
    publish.clubs_written()
    assert marker.read_text() == "x"
    assert "handed on early (exit 0)" in capsys.readouterr().out


def test_a_failing_hand_on_does_not_stop_the_run(monkeypatch, capsys):
    monkeypatch.setenv("PUBLISH_CLUBS_DONE", "/nonexistent/rclone copy a b")
    publish.clubs_written()
    assert "not handed on early" in capsys.readouterr().out
    monkeypatch.setenv("PUBLISH_CLUBS_DONE", f"{sys.executable} -c 'raise SystemExit(3)'")
    publish.clubs_written()
    assert "handed on early (exit 3)" in capsys.readouterr().out


def test_lake_views_built_on_several_cores_match_the_api(tmp_path, monkeypatch):
    # Pi speed-up, Nov 2026: the lake views are built in worker processes; the files must be the API's own answer.
    import asyncio
    import json
    from concurrent.futures.process import BrokenProcessPool

    from rowfrog import api

    now = datetime(2026, 11, 10, 9, tzinfo=timezone.utc)
    monkeypatch.setattr(api, "_now", lambda: now)

    async def no_water(client, station, now):
        return None, []

    async def no_warnings(client, club, now):
        return {"status": "ok", "lakeArea": None, "items": []}, []

    monkeypatch.setattr(api, "_water", no_water)
    monkeypatch.setattr(api, "_warnings", no_warnings)
    lake_ids = ["starnberger-see", "ammersee", "bodensee"]
    expected = {}
    for k, lake_id in enumerate(lake_ids):
        grid = api.lake_grid(lake_id, publish.outlines.load(lake_id))
        api.prepared.lake_weather[lake_id] = [
            [open_meteo.ForecastHour(now + timedelta(hours=h), 8.0, 2.0 + p + h % 7, 5.0 + h % 9, (40.0 * p + 25 * h + k) % 360,
                                     50.0, 10.0, 300.0 if h == 3 else 20_000.0, 0.0, 0.0, True) for h in range(12)]
            for p in range(len(grid.samples))
        ]
        expected[lake_id] = json.loads(json.dumps(publish.jsonable_encoder(asyncio.run(api.lake_view_forecast(lake_id)))))

    class BrokenPool:  # a worker that dies after the first view (out of memory, say)
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def map(self, fn, items, chunksize=1):
            yield fn(next(iter(items)))
            raise BrokenProcessPool("a worker died")

    try:
        assert publish.lake_views(tmp_path, lake_ids + ["no-such-lake"], workers=2) == 3
        for lake_id in lake_ids:
            assert json.loads((tmp_path / "lakes" / lake_id / "view").read_text()) == expected[lake_id]
        # When the worker processes fail, the views left are built one after another.
        monkeypatch.setattr(publish, "ProcessPoolExecutor", BrokenPool)
        broken = tmp_path / "broken"
        assert publish.lake_views(broken, lake_ids, workers=2) == 3
        for lake_id in lake_ids:
            assert json.loads((broken / "lakes" / lake_id / "view").read_text()) == expected[lake_id]
    finally:
        for lake_id in lake_ids:
            api.prepared.lake_weather.pop(lake_id, None)
            api._lake_view_cache.pop(lake_id, None)
