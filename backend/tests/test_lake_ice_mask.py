"""The fast lake mask (numpy) must give exactly what the pixel-by-pixel loop gives."""

import random

import pytest

np = pytest.importorskip("numpy")
affine = pytest.importorskip("affine")

from rowfrog.sources import lake_ice_satellite as ice  # noqa: E402

# The Copernicus LIE250 grid: 0.0025° pixels from 11° W, 72° N.
GRID = affine.Affine(0.0025, 0.0, -11.00125, 0.0, -0.0025, 72.00125)


def window_over(ring, grid=GRID):
    xs, ys = zip(*ring)
    col0, row0 = ~grid @ (min(xs), max(ys))
    col1, row1 = ~grid @ (max(xs), min(ys))
    col0, row0 = int(col0) - 2, int(row0) - 2
    cols, rows = int(col1) - col0 + 4, int(row1) - row0 + 4
    return grid @ affine.Affine.translation(col0, row0), rows, cols


def both(data, t, ring):
    fast = ice._lake_pixels(data, t, ring)
    slow = ice._lake_pixels_loop(data, t, ring)
    return fast, slow


def wobbly_lake(rng, lon, lat, size, points):
    ring = []
    for k in range(points):
        a = 2 * np.pi * k / points
        r = size * (0.5 + rng.random())
        ring.append((lon + r * np.cos(a), lat + 0.6 * r * np.sin(a)))
    return ring


def test_random_lakes_match_the_loop_exactly():
    rng = random.Random(7)
    for _ in range(30):
        ring = wobbly_lake(rng, 9 + rng.random() * 4, 46 + rng.random() * 2, 0.02 + rng.random() * 0.08, rng.randint(3, 120))
        t, rows, cols = window_over(ring)
        data = np.array([[rng.choice([0, 1, 2, 3]) for _ in range(cols)] for _ in range(rows)], dtype=np.int16)
        fast, slow = both(data, t, ring)
        assert fast == slow


def test_an_outline_along_pixel_centres_matches_the_loop():
    # Corners and edges exactly on pixel centres, where < and > decide.
    x0, y0 = GRID @ (8800.5, 10400.5)
    x1, y1 = GRID @ (8830.5, 10420.5)
    ring = [(x0, y0), (x1, y0), (x1, y1), ((x0 + x1) / 2, (y0 + y1) / 2), (x0, y1)]
    t, rows, cols = window_over(ring)
    data = np.full((rows, cols), 3, dtype=np.int16)
    fast, slow = both(data, t, ring)
    assert fast == slow
    assert len(fast[0]) > 100


def test_a_ring_with_flat_edges_and_a_closing_point_matches_the_loop():
    ring = [(11.0, 47.9), (11.1, 47.9), (11.1, 47.9), (11.1, 48.0), (11.05, 47.95), (11.0, 48.0), (11.0, 47.9)]
    t, rows, cols = window_over(ring)
    data = np.ones((rows, cols), dtype=np.int16)
    fast, slow = both(data, t, ring)
    assert fast == slow


def test_a_lake_outside_the_window_has_no_pixels():
    t, rows, cols = window_over([(11.0, 47.9), (11.1, 47.9), (11.1, 48.0)])
    far = [(20.0, 40.0), (20.1, 40.0), (20.1, 40.1)]
    values, classes = ice._lake_pixels(np.ones((rows, cols), dtype=np.int16), t, far)
    assert values == [] and classes == bytearray(rows * cols)


def test_a_value_beyond_a_byte_is_refused_like_the_loop():
    ring = [(11.0, 47.9), (11.1, 47.9), (11.1, 48.0), (11.0, 48.0)]
    t, rows, cols = window_over(ring)
    data = np.full((rows, cols), 300, dtype=np.int16)
    with pytest.raises(ValueError):
        ice._lake_pixels_loop(data, t, ring)
    with pytest.raises(ValueError):
        ice._lake_pixels(data, t, ring)


def test_the_loop_can_be_switched_back_on(monkeypatch):
    calls = []
    monkeypatch.setattr(ice, "_lake_pixels_loop", lambda *a: calls.append("loop") or ([], bytearray()))
    monkeypatch.setattr(ice, "_lake_pixels", lambda *a: calls.append("fast") or ([], bytearray()))
    rasterio = pytest.importorskip("rasterio")
    from rasterio.transform import from_origin

    import tempfile, os

    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "lie.tif")
        with rasterio.open(path, "w", driver="GTiff", width=40, height=40, count=1, dtype="int16", crs="EPSG:4326",
                           transform=from_origin(10.95, 48.05, 0.0025, 0.0025)) as ds:
            ds.write(np.ones((1, 40, 40), dtype=np.int16))
        shores = {"lake": [(11.0, 47.99), (11.03, 47.99), (11.03, 48.02)]}
        ice._read(path, None, shores)
        monkeypatch.setenv("ROWFROG_ICE_MASK", "loop")
        ice._read(path, None, shores)
    assert calls == ["fast", "loop"]
