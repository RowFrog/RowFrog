"""The weather maps end to end: DWD's ICON-D2 files (saved replies made with
eccodes, served by a fake DWD) read, cut into tiles and written as the app
reads them."""

import bz2
import json
import zlib
from datetime import datetime, timezone

import httpx
import pytest

np = pytest.importorskip("numpy")
eccodes = pytest.importorskip("eccodes")

from rowfrog.sources import icon_d2_maps as maps  # noqa: E402

CLUB = (47.9, 11.3)  # Starnberger See
# A 0.1° grid from 8 to 15 °E and 45 to 55 °N, north row first as DWD sends it.
NI, NJ = 71, 101
MISSING = 9999.0


def grib(value: float, missing_corner: bool = False) -> bytes:
    gid = eccodes.codes_grib_new_from_samples("regular_ll_sfc_grib2")
    try:
        for key, v in [("Ni", NI), ("Nj", NJ), ("latitudeOfFirstGridPointInDegrees", 55.0),
                       ("latitudeOfLastGridPointInDegrees", 45.0), ("longitudeOfFirstGridPointInDegrees", 8.0),
                       ("longitudeOfLastGridPointInDegrees", 15.0), ("iDirectionIncrementInDegrees", 0.1),
                       ("jDirectionIncrementInDegrees", 0.1)]:
            eccodes.codes_set(gid, key, v)
        eccodes.codes_set(gid, "bitmapPresent", 1)
        eccodes.codes_set(gid, "missingValue", MISSING)
        values = np.full(NI * NJ, value)
        if missing_corner:
            values[0] = MISSING  # the north-west corner
        eccodes.codes_set_values(gid, values)
        return bz2.compress(eccodes.codes_get_message(gid))
    finally:
        eccodes.codes_release(gid)


# Each variable's value: 16 °C, wind from the north-east at 5 m/s, gusts 8 m/s,
# 80 % humidity, 1013 hPa, 30 km visibility and 0.5 mm of rain an hour.
VALUES = {"t_2m": 289.15, "u_10m": -3.0, "v_10m": -4.0, "vmax_10m": 8.0, "relhum_2m": 80.0,
          "pmsl": 101_300.0, "vis": 30_000.0}


@pytest.fixture
def dwd(monkeypatch):
    """A fake opendata.dwd.de: the 12 UTC run is not complete yet, the 09 UTC run is."""
    cache: dict[tuple[str, int], bytes] = {}
    asked = []

    def answer(request: httpx.Request) -> httpx.Response:
        asked.append((request.method, request.url.path))
        name = request.url.path.rsplit("/", 1)[-1]
        parts = name.split("_")
        stamp, step, var = parts[4], int(parts[5]), request.url.path.split("/")[-2]
        if stamp.endswith("12"):
            return httpx.Response(404)
        if request.method == "HEAD":
            return httpx.Response(200)
        if (var, step) not in cache:
            value = step * 0.5 if var == "tot_prec" else VALUES[var]
            cache[(var, step)] = grib(value, missing_corner=var == "t_2m")
        return httpx.Response(200, content=cache[(var, step)])

    real = httpx.Client
    monkeypatch.setattr(maps.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(answer), **kw))
    return asked


def layers(path, name):
    raw = zlib.decompress(path.read_bytes(), -15)
    return np.frombuffer(raw, dtype=np.uint8).reshape(len(maps.STEPS), maps.ROWS, maps.COLS) if name != "windDirection" else raw


def test_the_newest_complete_run_is_read_and_written_per_tile(tmp_path, dwd):
    now = datetime(2026, 11, 3, 13, 5, tzinfo=timezone.utc)
    run = maps.build(tmp_path, [CLUB], now)
    assert run == datetime(2026, 11, 3, 9, tzinfo=timezone.utc)
    # The 12 UTC run was asked for and passed over; every value of every step came from the 09 UTC run.
    assert any("2026110312" in path for _, path in dwd)
    gets = [path for method, path in dwd if method == "GET"]
    assert len(gets) == len(maps.SOURCES) * len(maps.STEPS)
    assert all("2026110309" in path for path in gets)

    index = json.loads((tmp_path / "maps" / "index").read_text())
    assert index["run"] == "2026-11-03T09:00:00Z"
    assert index["hours"][0] == "2026-11-03T09:00:00Z" and index["hours"][-1] == "2026-11-05T09:00:00Z"
    assert len(index["hours"]) == len(maps.STEPS)
    assert {t["id"] for t in index["tiles"]} == {t.id for t in maps.tiles_around([CLUB])}
    assert index["values"]["temperature"] == {"offset": -40, "scale": 0.4, "unit": "°C"}


def test_the_values_at_the_club_decode_to_the_models_numbers(tmp_path, dwd):
    maps.build(tmp_path, [CLUB], datetime(2026, 11, 3, 13, 5, tzinfo=timezone.utc))
    tile = maps.tile_for(*CLUB)
    folder = tmp_path / "maps" / tile.id
    row, col = maps.ROWS // 2, maps.COLS // 2  # the tile's middle, inside the fake grid
    expected = {"temperature": 140, "wind": 25, "gust": 40, "humidity": 160, "pressure": 146, "visibility": 254, "rain": 5}
    for name, byte in expected.items():
        data = layers(folder / name, name)
        assert data[1, row, col] == byte, name
    # The first hour has no gusts of its own (they are the past hour's) and no rain yet.
    assert layers(folder / "gust", "gust")[0, row, col] == 25
    assert layers(folder / "rain", "rain")[0, row, col] == 0
    # Every 3 hours later on: 1.5 mm in 3 hours is still 0.5 mm an hour.
    assert layers(folder / "rain", "rain")[-1, row, col] == 5
    # Feels like from the same formula as the forecasts.
    feels = maps.feels_like(np.array(16.0), np.array(80.0), np.array(5.0))
    assert layers(folder / "feelsLike", "feelsLike")[1, row, col] == round((float(feels) + 40) / 0.4)


def test_wind_direction_is_kept_only_where_the_app_draws_an_arrow(tmp_path, dwd):
    maps.build(tmp_path, [CLUB], datetime(2026, 11, 3, 13, 5, tzinfo=timezone.utc))
    raw = layers(tmp_path / "maps" / maps.tile_for(*CLUB).id / "windDirection", "windDirection")
    per_step = len(range(maps.ARROW_STEP // 2, maps.ROWS, maps.ARROW_STEP)) * len(range(maps.ARROW_STEP // 2, maps.COLS, maps.ARROW_STEP))
    assert len(raw) == per_step * len(maps.STEPS)
    # From the north-east: 36.9° clockwise from north, in steps of 1.5°.
    assert raw[per_step // 2] == 25


def test_outside_the_model_stays_missing(tmp_path, dwd):
    maps.build(tmp_path, [CLUB], datetime(2026, 11, 3, 13, 5, tzinfo=timezone.utc))
    # The tile to the west reaches past 8 °E, where the fake grid ends.
    west = maps.tile_for(CLUB[0], CLUB[1] - maps.STEP_LON)
    assert west.west < 8.0
    data = layers(tmp_path / "maps" / west.id / "temperature", "temperature")
    assert data[0, maps.ROWS // 2, 0] == maps.MISSING
    assert data[0, maps.ROWS // 2, -1] == 140


def test_nothing_is_written_when_no_newer_run_is_there(tmp_path, dwd):
    now = datetime(2026, 11, 3, 13, 5, tzinfo=timezone.utc)
    assert maps.build(tmp_path, [CLUB], now, last_run=datetime(2026, 11, 3, 9, tzinfo=timezone.utc)) is None
    assert not (tmp_path / "maps").exists()
    assert not [path for method, path in dwd if method == "GET"]


def test_a_url_names_the_run_step_and_value():
    run = datetime(2026, 11, 3, 9, tzinfo=timezone.utc)
    assert maps._url(run, "t_2m", 7) == (
        "https://opendata.dwd.de/weather/nwp/icon-d2/grib/09/t_2m/"
        "icon-d2_germany_regular-lat-lon_single-level_2026110309_007_2d_t_2m.grib2.bz2"
    )


def test_a_download_is_tried_three_times():
    calls = []

    def flaky(request):
        calls.append(request.url)
        return httpx.Response(503) if len(calls) < 3 else httpx.Response(200, content=b"ok")

    with httpx.Client(transport=httpx.MockTransport(flaky)) as client:
        assert maps._fetch(client, "https://example.org/x") == b"ok"
    calls.clear()
    with httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(503))) as client:
        with pytest.raises(httpx.HTTPError):
            maps._fetch(client, "https://example.org/x")
