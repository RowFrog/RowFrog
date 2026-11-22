from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from rowfrog import api, lake_view
from rowfrog.score import Light
from rowfrog.sources import open_meteo
from rowfrog.sources.dwd_warnings import Warning
from rowfrog.sources.open_meteo import ForecastHour

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


def test_hail_and_heavy_rain_colour_the_cells():
    from dataclasses import replace

    grid = lake_view.build_grid(LAKE, target_cells=100)
    calm = hour(speed=1.0, gust=2.0)
    (h,) = lake_view.lake_hours(grid, [[replace(calm, weather_code=96)] for _ in grid.samples])
    assert set(h.lights) == {Light.RED} and set(h.point_other) == {Light.RED}
    (h,) = lake_view.lake_hours(grid, [[replace(calm, precipitation_mm=5.0)] for _ in grid.samples])
    assert set(h.lights) == {Light.AMBER} and set(h.point_other) == {Light.AMBER}


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
    assert all(w["visM"] is None or isinstance(w["visM"], int) for w in first["wind"])
    assert all(w["storm"] in (0, 1, 2) and isinstance(w["hail"], bool) for w in first["wind"])
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


def test_grid_of_a_narrow_river_section():
    # A 20 m wide, 6 km long river: the cells shrink until enough lie on the water.
    import math

    dlat = 10 / 111_195
    east = 11.0 + 6000 / (111_195 * math.cos(math.radians(48)))
    ring = [(11.0, 48.0 - dlat), (east, 48.0 - dlat), (east, 48.0 + dlat), (11.0, 48.0 + dlat)]
    grid = lake_view.build_grid([ring], target_cells=200, max_samples=lake_view.river_samples(6), narrow=True)
    assert len(grid.cells) >= 100
    assert grid.cell_m < lake_view.MIN_CELL_M
    assert len(grid.samples) == lake_view.river_samples(6) == 2
    # Wind along the river has fetch, wind across it hardly any.
    along = lake_view._interpolated_fetch(grid.fetch[len(grid.fetch) // 2], 90.0)
    across = lake_view._interpolated_fetch(grid.fetch[len(grid.fetch) // 2], 0.0)
    assert along > 1000 > 30 > across


def test_wider_lake_grids_are_unchanged_by_the_river_switch():
    assert lake_view.build_grid(LAKE, target_cells=200).cells == lake_view.build_grid(LAKE, target_cells=200, narrow=True).cells


def test_cells_blend_the_wind_of_the_points_around_them():
    # Owner's natural neighbour pick, 6 Nov 2026: no hard step between a calm and a windy point.
    grid = lake_view.build_grid(LAKE, target_cells=200)
    assert len(grid.samples) >= 2 and len(grid.weights) == len(grid.cells)
    for w in grid.weights:
        assert abs(sum(w.values()) - 1) < 1e-9 and all(v >= 0 for v in w.values())
    speeds = [2.0 + 6.0 * k / (len(grid.samples) - 1) for k in range(len(grid.samples))]
    at_points = [hour(speed=s, gust=s + 1, visibility=300.0 if k == 0 else 15_000.0) for k, s in enumerate(speeds)]
    blended = [lake_view.cell_weather(grid, i, at_points) for i in range(len(grid.cells))]
    # Never beyond the points, and more than just the points' own values.
    assert all(min(speeds) - 1e-9 <= b.wind_speed_ms <= max(speeds) + 1e-9 for b in blended)
    assert len({round(b.wind_speed_ms, 2) for b in blended}) > len(speeds)
    assert all(300.0 - 1e-6 <= b.visibility_m <= 15_000.0 + 1e-6 for b in blended)
    # Direction from the arrows: 350° and 10° make north, not south.
    turned = [hour(wind_from=350.0 if k % 2 else 10.0) for k in range(len(grid.samples))]
    for i in range(len(grid.cells)):
        d = lake_view.cell_weather(grid, i, turned).wind_from_deg
        assert min(d, 360 - d) <= 10.0 + 1e-6


def test_lake_hours_read_each_cell_as_cell_weather_does():
    # The faster per-hour columns (Pi speed-up, Nov 2026) must give exactly cell_weather's values,
    # also when a point lacks a value, two arrows cancel out, or thunderstorm clouds build.
    import random

    from rowfrog.forecast import _thunderstorm

    rnd = random.Random(7)
    grid = lake_view.build_grid(LAKE, target_cells=200)

    def maybe(x):
        return None if rnd.random() < 0.05 else x

    for _ in range(30):
        at_points = [
            ForecastHour(
                START, 12.0, maybe(rnd.choice([0.0, rnd.uniform(0, 14)])), maybe(rnd.uniform(0, 20)),
                maybe(rnd.choice([0.0, 180.0, 350.0, 10.0, rnd.uniform(0, 360)])), 50.0, 10.0,
                maybe(rnd.choice([80.0, 20_000.0, rnd.uniform(50, 30_000)])), maybe(rnd.choice([0.0, 1.5, 6.0])),
                maybe(rnd.uniform(0, 1500)), True,
                weather_code=rnd.choice([None, 3, 61, 96]),
            )
            for _ in grid.samples
        ]
        columns = lake_view._HourColumns(at_points)
        for i in range(len(grid.cells)):
            w = lake_view.cell_weather(grid, i, at_points)
            speed, gust, direction, visibility, rain, cape, code = columns.cell(grid, i)
            assert (speed, gust, direction, visibility, rain, code) == (
                w.wind_speed_ms, w.wind_gust_ms, w.wind_from_deg, w.visibility_m, w.precipitation_mm, w.weather_code
            )
            assert lake_view._storm_light(cape, rain) == _thunderstorm(w)


def test_lake_hours_with_numpy_are_the_plain_loop_bit_for_bit():
    # The numpy cells (Pi speed-up, 22 Nov 2026) must give exactly the loop's lights and waves:
    # also with missing values, arrows that cancel, light wind (fully developed waves), whole-number
    # values as Open-Meteo sends them, visibility right at the fog limits and cold water.
    import random

    import pytest

    if lake_view.np is None:
        pytest.skip("numpy is in the satellite extra")
    rnd = random.Random(22)

    def maybe(x):
        return None if rnd.random() < 0.05 else x

    for target, narrow in ((200, False), (60, False), (200, True)):
        grid = lake_view.build_grid(LAKE, target_cells=target, narrow=narrow)
        hours = 12
        weather = [
            [
                ForecastHour(
                    START + timedelta(hours=h), 12.0,
                    maybe(rnd.choice([0.0, 0, 3, 0.4, rnd.uniform(0, 1), rnd.uniform(0, 14)])),
                    maybe(rnd.choice([0, rnd.uniform(0, 20)])),
                    maybe(rnd.choice([0.0, 180.0, 350.0, 10.0, 360, 270, rnd.uniform(0, 360)])), 50.0, 10.0,
                    maybe(rnd.choice([80.0, 500.0, 1000.0, 1000, 999.9999, 1000.0001, 20_000.0, rnd.uniform(50, 30_000)])),
                    maybe(rnd.choice([0.0, 1.5, 4.0, 6.0])), maybe(rnd.choice([0, rnd.uniform(0, 1500)])), True,
                    weather_code=rnd.choice([None, 3, 61, 96, 99]),
                )
                for h in range(hours)
            ]
            for _ in grid.samples
        ]
        for water in (None, 8.0):
            fast = lake_view.lake_hours(grid, weather, water_temp_c=water)
            loop = lake_view._lake_hours_loop(grid, weather, water_temp_c=water)
            for a, b in zip(fast, loop, strict=True):
                assert repr((a.lights, a.waves_m, a.zone_lights, a.zone_max_wave_m)) == repr(
                    (b.lights, b.waves_m, b.zone_lights, b.zone_max_wave_m)
                )
                assert a == b


def test_lake_view_json_has_plain_json_types_only():
    # lake_view_json leaves FastAPI's jsonable_encoder out (Pi speed-up, 22 Nov 2026): the view
    # must already be what it would give, with no tuples, enums or dates left in it.
    from fastapi.encoders import jsonable_encoder

    grid = lake_view.build_grid(LAKE, target_cells=200)
    weather = [[hour(at=START + timedelta(hours=h), visibility=300.0 if h else 20_000.0) for h in range(3)] for _ in grid.samples]
    body, problem = api.lake_view_json(("starnberger-see", grid, weather, [], 8.0, START))
    assert problem is None

    def plain(x):
        if isinstance(x, dict):
            return all(type(k) is str and plain(v) for k, v in x.items())
        if type(x) is list:
            return all(plain(v) for v in x)
        return x is None or type(x) in (str, int, float, bool)

    assert plain(body) and jsonable_encoder(body) == body


def test_nearby_water_counts_only_the_water_near_the_launch_point():
    # Option C (owner, 6 Nov 2026): the launch point's light also counts the water within 1 km.
    grid = lake_view.build_grid(LAKE, target_cells=200)
    lats = [lat for _, lat in grid.points]
    lon_mid = sum(lon for lon, _ in grid.points) / len(grid.points)
    south = min(lats)
    calm = [[hour(speed=1.0, gust=2.0)] for _ in grid.samples]
    (n,) = lake_view.nearby_water(grid, calm, south, lon_mid).values()
    assert n.light == Light.GREEN and n.cause is None
    near = lake_view.nearby_cells(grid, south, lon_mid)
    assert near and all(lat < south + 0.0095 for _, lat in (grid.points[i] for i in near)), "about 1 km only"
    # Fog at the northern end only does not reach a launch point at the southern end.
    north_k = max(range(len(grid.samples)), key=lambda k: grid.samples[k][1])
    foggy_north = [[hour(speed=1.0, gust=2.0, visibility=300.0 if k == north_k else 20_000.0)] for k in range(len(grid.samples))]
    (n,) = lake_view.nearby_water(grid, foggy_north, south, lon_mid).values()
    assert n.light == Light.GREEN
    # A strong wind nearby is named with its worst value; fog alone sets `other`.
    windy = [[hour(speed=9.0, gust=11.0, visibility=20_000.0)] for _ in grid.samples]
    (n,) = lake_view.nearby_water(grid, windy, south, lon_mid).values()
    # Gusts and wind both red: the gusts come first (owner's order, 20 Nov 2026).
    assert n.light == Light.RED and n.cause == "gusts" and abs(n.value - 11.0) < 1e-6
    # With thick fog as well, the fog is named: it comes first among the reds (owner, 20 Nov 2026).
    foggy = [[hour(speed=9.0, gust=11.0, visibility=300.0)] for _ in grid.samples]
    (n,) = lake_view.nearby_water(grid, foggy, south, lon_mid).values()
    assert n.light == Light.RED and n.cause == "fog" and abs(n.value - 300.0) < 1e-6
    assert n.other == Light.RED and n.other_cause == "fog" and abs(n.vis_m - 300.0) < 1e-6


def test_grids_are_kept_between_runs_until_the_outline_or_code_changes(tmp_path, monkeypatch):
    # Owner's pick, 11 Nov 2026: keep the grids, but build them again with the newest outline or grid code.
    monkeypatch.setattr(lake_view, "GRID_CACHE_DIR", tmp_path)
    built = []
    real_build = lake_view.build_grid

    def counting_build(rings, *args, **kwargs):
        built.append(rings)
        return real_build(rings, *args, **kwargs)

    monkeypatch.setattr(lake_view, "build_grid", counting_build)

    def new_run():  # each publish run is a new process: nothing in memory
        lake_view._grid_cached.cache_clear()

    new_run()
    first = lake_view.grid_for("test-lake", LAKE)
    assert len(built) == 1 and (tmp_path / "test-lake.pickle").exists()
    new_run()
    assert lake_view.grid_for("test-lake", LAKE) == first and len(built) == 1  # kept, not built
    # A changed outline: built again from it, and kept in place of the old one.
    moved = [[(x + 0.001, y) for x, y in ring] for ring in LAKE]
    new_run()
    assert lake_view.grid_for("test-lake", moved) != first and len(built) == 2
    new_run()
    lake_view.grid_for("test-lake", moved)
    assert len(built) == 2
    # Other settings (fewer forecast points for a lake people use) are a different grid.
    new_run()
    lake_view.grid_for("test-lake", moved, max_samples=3)
    assert len(built) == 3
    # Changed grid code: every kept grid is built again.
    new_run()
    monkeypatch.setattr(lake_view, "_code_fingerprint", lambda: "other code")
    lake_view.grid_for("test-lake", moved, max_samples=3)
    assert len(built) == 4
    # A broken file is built again too, and no keeping at all without a folder.
    (tmp_path / "test-lake.pickle").write_bytes(b"not a pickle")
    new_run()
    assert lake_view.grid_for("test-lake", moved, max_samples=3).cells and len(built) == 5
    monkeypatch.setattr(lake_view, "GRID_CACHE_DIR", None)
    new_run()
    lake_view.grid_for("other-lake", LAKE)
    assert len(built) == 6 and not (tmp_path / "other-lake.pickle").exists()
    new_run()

