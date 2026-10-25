from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from rowerweather import api, lake_view
from rowerweather.score import Light
from rowerweather.sources import open_meteo
from rowerweather.sources.dwd_warnings import Warning
from rowerweather.sources.open_meteo import ForecastHour

from .test_forecast import PAYLOAD
from .test_waves import LAKE

START = datetime(2026, 10, 18, 10, tzinfo=timezone.utc)


def hour(wind_from=180.0, speed=6.0, gust=7.0, at=START, visibility=20_000.0):
    return ForecastHour(at, 12.0, speed, gust, wind_from, 50.0, 10.0, visibility, 0.0, 0.0, True)


def test_grid_covers_the_lake_with_about_the_target_number_of_cells():
    grid = lake_view.build_grid(LAKE, target_cells=200)
    assert 150 <= len(grid.cells) <= 250
    assert len(grid.points) == len(grid.fetch) == len(grid.nearest) == len(grid.zone_of)
    # A 2 x 10 km lake running north-south has a north, a middle and a south part.
    assert grid.zones == ["north", "middle", "south"]
    assert 1 <= len(grid.samples) <= lake_view.MAX_SAMPLES


def test_grid_of_a_lake_in_two_parts():
    # A MultiPolygon: a small part first, then a bigger one beside it (as OSM has Geschirrwasser).
    (x0, y0), (x1, _), (_, y1), _ = LAKE[0]
    small = [(x0, y0), (x0 + (x1 - x0) / 2, y0), (x0 + (x1 - x0) / 2, y0 + (y1 - y0) / 5), (x0, y0 + (y1 - y0) / 5)]
    big = [(x + 2 * (x1 - x0), y) for x, y in LAKE[0]]
    grid = lake_view.build_grid([small, big], target_cells=200)
    lons = [lon for lon, _ in grid.points]
    assert min(lons) < x1 < 2 * x1 - x0 < max(lons)  # cells in both parts


def test_waves_build_downwind():
    grid = lake_view.build_grid(LAKE, target_cells=200)
    (h,) = lake_view.lake_hours(grid, [[hour(wind_from=180.0)] for _ in grid.samples])
    north, _, south = h.zone_max_wave_m
    assert north > 1.5 * south, "a south wind has the whole lake to build waves at the north end"
    assert h.zone_lights[0] > h.zone_lights[2]
    assert h.lake_wide == []


def test_lake_wide_conditions_are_reported_once_not_per_cell():
    grid = lake_view.build_grid(LAKE, target_cells=100)
    storm = Warning(
        kind="lake", area="Test", event="STURM", severity="Severe", headline="", description="", instruction="",
        onset=START - timedelta(hours=1), expires=START + timedelta(hours=2),
    )
    (h,) = lake_view.lake_hours(grid, [[hour(speed=1.0, gust=2.0)] for _ in grid.samples], [storm])
    assert h.lake_wide_light == Light.RED
    assert ("lake_warning", Light.RED) in h.lake_wide
    assert set(h.lights) == {Light.GREEN}, "cells show the water, the banner shows the warning"


def test_fog_colours_the_cells():
    grid = lake_view.build_grid(LAKE, target_cells=100)
    (h,) = lake_view.lake_hours(grid, [[hour(speed=1.0, gust=2.0, visibility=300.0)] for _ in grid.samples])
    assert set(h.lights) == {Light.RED}
    assert set(h.point_other) == {Light.RED}, "the app needs fog per point to colour cells for other boats"


def test_simplify_keeps_a_square():
    square = [(0.0, 0.0), (100.0, 0.0), (100.0, 50.0), (100.0, 100.0), (0.0, 100.0)]
    assert len(lake_view._simplify(square, 1.0)) == 4


def test_lake_view_endpoint(monkeypatch):
    async def fake_fetch_many(client, points, hours=48, hourly=None):
        return [open_meteo.parse(PAYLOAD) for _ in points]

    async def no_water(*args, **kwargs):
        return None

    async def no_warnings(client, club, now):
        return {"status": "ok", "lakeArea": None, "items": []}, []

    monkeypatch.setattr(open_meteo, "fetch_many", fake_fetch_many)
    monkeypatch.setattr(api.gkd, "fetch_latest", no_water)
    monkeypatch.setattr(api, "_warnings", no_warnings)
    api._lake_view_cache.clear()
    body = TestClient(api.app).get("/lakes/starnberger-see/view").json()
    api._lake_view_cache.clear()
    cells = body["grid"]["cells"]
    assert len(body["hours"]) == 2
    first = body["hours"][0]
    assert len(first["lights"]) == len(first["wavesCm"]) == len(cells) == len(body["grid"]["cellPoint"])
    assert set(first["lights"]) <= {"0", "1", "2"}
    assert len(first["wind"]) == len(body["points"])
    assert {w["other"] for w in first["wind"]} <= {0, 1, 2}
    assert body["zones"] == ["north", "middle", "south"]
    assert len(first["zones"]) == 3
    assert body["sample"] is False
    # 400 m visibility in the first hour is fog everywhere.
    assert set(first["lights"]) == {"2"}


def test_lake_view_without_outline_is_404():
    assert TestClient(api.app).get("/lakes/nope/view").status_code == 404


def test_lakes_say_whether_the_lake_view_is_available():
    body = TestClient(api.app).get("/lakes").json()
    assert next(l for l in body if l["id"] == "starnberger-see")["hasOutline"] is True
