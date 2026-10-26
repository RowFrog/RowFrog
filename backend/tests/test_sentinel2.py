from fastapi.testclient import TestClient

from rowfrog import outlines
from rowfrog.api import app
from rowfrog.sources import sentinel2


def test_picture_frame_keeps_the_lake_shape_within_the_size_limit():
    (west, south, east, north), width, height = sentinel2.frame(outlines.load("starnberger-see")[0])
    assert west < 11.30 < east and south < 47.90 < north
    # Starnberger See is about 20 km long and 5 km wide: a tall picture, 1280 px high.
    assert height == sentinel2.MAX_PIXELS and 250 < width < 600


def test_small_lake_shows_at_least_four_by_three_km_at_ten_metres():
    ring = [(11.0, 48.0), (11.01, 48.0), (11.01, 48.005), (11.0, 48.005)]
    (west, south, east, north), width, height = sentinel2.frame(ring)
    assert (width, height) == (400, 300)
    assert abs((west + east) / 2 - 11.005) < 1e-9 and abs((south + north) / 2 - 48.0025) < 1e-9  # centred on the lake


def test_long_narrow_lake_widens_only_across():
    ring = [(11.0, 48.0), (11.01, 48.0), (11.01, 48.05), (11.0, 48.05)]  # about 750 m by 5.5 km, plus shore
    _, width, height = sentinel2.frame(ring)
    assert width == 400 and 630 < height < 650


def test_no_account_means_no_pictures(monkeypatch):
    monkeypatch.delenv("CDSE_CLIENT_ID", raising=False)
    assert sentinel2.client() is None


def test_lake_list_is_also_at_lakes_index():
    client = TestClient(app)
    assert client.get("/lakes/index").json() == client.get("/lakes").json()
