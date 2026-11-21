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


def test_pictures_are_saved_at_our_own_jpeg_quality():
    assert sentinel2.JPEG_QUALITY == 90
    # The Process API sends JPEGs at 90 whatever it is asked for, so pictures come as PNG.
    import io

    from PIL import Image

    png = io.BytesIO()
    Image.effect_noise((200, 150), 40).convert("RGB").save(png, "PNG")
    data = sentinel2.to_jpeg(png.getvalue())
    with Image.open(io.BytesIO(data)) as picture:
        assert picture.format == "JPEG"
        assert picture.size == (200, 150)
        assert picture.mode == "RGB"
    assert len(sentinel2.to_jpeg(png.getvalue(), quality=75)) < len(data)


def _png(alpha_right_from: int | None, size=(200, 150)) -> bytes:
    """A noisy picture; with `alpha_right_from`, the pass saw nothing right of that column."""
    import io

    from PIL import Image

    picture = Image.effect_noise(size, 40).convert("RGB")
    out = io.BytesIO()
    if alpha_right_from is None:
        picture.save(out, "PNG")
    else:
        alpha = Image.new("L", size, 255)
        alpha.paste(0, (alpha_right_from, 0, size[0], size[1]))
        picture.putalpha(alpha)
        picture.save(out, "PNG")
    return out.getvalue()


def test_parts_the_pass_did_not_see_are_grey_and_counted():
    import io

    from PIL import Image

    data, gap = sentinel2.picture_from_png(_png(150))
    assert gap == 0.25
    with Image.open(io.BytesIO(data)) as picture:
        assert picture.mode == "RGB" and picture.size == (200, 150)
        r, g, b = picture.getpixel((190, 75))
        # Grey stripes, never black (JPEG moves colours a little).
        assert all(abs(c - want) <= 12 for c, want in zip((r, g, b), sentinel2.GAP_COLOURS[0])) or all(
            abs(c - want) <= 12 for c, want in zip((r, g, b), sentinel2.GAP_COLOURS[1])
        )


def test_a_whole_picture_has_no_gap():
    assert sentinel2.picture_from_png(_png(None))[1] == 0.0
    assert sentinel2.picture_from_png(_png(200))[1] == 0.0  # alpha band, all seen
    # A few pixels at a corner are not worth a note.
    assert sentinel2.picture_from_png(_png(399, size=(400, 150)))[1] == 0.0


def test_the_picture_asks_for_the_data_mask():
    assert '"dataMask"' in sentinel2.PICTURE_SCRIPT and "bands: 4" in sentinel2.PICTURE_SCRIPT
