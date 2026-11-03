"""The satellite readers end to end with saved replies: Copernicus' catalogue,
sign-in and downloads (lake ice and lake temperature) and the Planetary
Computer's Landsat search, served by a fake web; the files are small tiffs
written here."""

import io
import json
import zipfile
from datetime import date, datetime, timezone

import httpx
import pytest

rasterio = pytest.importorskip("rasterio")
np = pytest.importorskip("numpy")
from rasterio.transform import from_origin  # noqa: E402

from rowfrog.sources import lake_ice_satellite as ice  # noqa: E402
from rowfrog.sources import lake_temperature_satellite as temp  # noqa: E402

TODAY = date(2026, 1, 20)
# A square lake of 0.1° and a pond of 0.01°, too small for a 250 m map.
LAKE = [(11.0, 48.0), (11.1, 48.0), (11.1, 48.1), (11.0, 48.1)]
POND = [(11.5, 48.5), (11.51, 48.5), (11.51, 48.51), (11.5, 48.51)]


def tif(data: "np.ndarray", west: float, north: float, step: float, crs: str = "EPSG:4326", **extra) -> bytes:
    buf = io.BytesIO()
    h, w = data.shape
    with rasterio.MemoryFile() as mem:
        with mem.open(driver="GTiff", width=w, height=h, count=1, dtype=data.dtype.name, crs=crs,
                      transform=from_origin(west, north, step, step)) as ds:
            for key, value in extra.items():
                setattr(ds, key, value)
            ds.write(data, 1)
        buf.write(mem.read())
    return buf.getvalue()


def zipped(files: dict[str, bytes]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, content in files.items():
            z.writestr(name, content)
    return buf.getvalue()


class FakeWeb:
    """Answers by URL; records every request."""

    def __init__(self, routes):
        self.routes = routes
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        for start, answer in self.routes.items():
            if str(request.url).startswith(start):
                return answer(request) if callable(answer) else answer
        return httpx.Response(404)


@pytest.fixture
def web(monkeypatch):
    def install(routes):
        fake = FakeWeb(routes)
        real = httpx.Client
        monkeypatch.setattr(httpx, "Client", lambda *a, **kw: real(*a, transport=httpx.MockTransport(fake), **kw))
        return fake

    monkeypatch.setenv("CDSE_CLIENT_ID", "id")
    monkeypatch.setenv("CDSE_CLIENT_SECRET", "secret")
    return install


TOKEN = {"https://identity.dataspace.copernicus.eu/": httpx.Response(200, json={"access_token": "tok"})}


# --- lake ice (Copernicus LIE250) ---------------------------------------------------------------


def ice_map(ice_rows: int) -> "np.ndarray":
    """A 250 m-like grid (48 pixels across the lake): the top rows ice, the rest open water, a cloudy corner."""
    data = np.full((48, 48), ice.OPEN_WATER, dtype="uint8")
    data[:ice_rows, :] = ice.CLEAR_ICE
    data[40:, 40:] = 0  # cloud
    return data


def test_ice_passes_from_the_catalogue_downloads(web):
    files = {"p1": tif(ice_map(10), 11.0, 48.1, 0.1 / 48), "p2": zipped({"LIE250.tif": tif(ice_map(20), 11.0, 48.1, 0.1 / 48)})}
    catalogue = {"value": [{"Id": "p1", "Name": "c_gls_LIE250_202601180000_CEURO_VIIRS_V1.0.0_cog", "ContentDate": {"Start": "2026-01-18T00:00:00.000Z"}},
                           {"Id": "p2", "Name": "c_gls_LIE250_202601190000_CEURO_VIIRS_V1.0.0_cog", "ContentDate": {"Start": "2026-01-19T00:00:00.000Z"}}]}
    fake = web({
        **TOKEN,
        ice.CATALOGUE: httpx.Response(200, json=catalogue),
        "https://download.dataspace.copernicus.eu/odata/v1/Products(p1)": httpx.Response(200, content=files["p1"]),
        "https://download.dataspace.copernicus.eu/odata/v1/Products(p2)": httpx.Response(200, content=files["p2"]),
    })
    passes = ice.fetch({"lake": LAKE, "pond": POND}, TODAY)

    assert set(passes) == {"lake"}  # the pond has too few pixels
    first, second = passes["lake"]
    assert (first.day, second.day) == (date(2026, 1, 18), date(2026, 1, 19))
    assert first.pixels == second.pixels > ice.MIN_PIXELS
    assert second.ice > first.ice > 0 and first.water > second.water > 0
    assert first.ice + first.water < first.pixels  # the cloudy corner was not seen
    assert ice.png(first)[:8] == b"\x89PNG\r\n\x1a\n"
    assert first.bbox[0] == pytest.approx(11.0, abs=0.01) and first.bbox[3] == pytest.approx(48.1, abs=0.01)

    query = fake.requests[0].url.params["$filter"]
    assert "LIE250" in query and "CEURO" in query and "2026-01-16T00:00:00.000Z" in query
    downloads = [r for r in fake.requests if "download" in r.url.host]
    assert [r.headers["authorization"] for r in downloads] == ["Bearer tok", "Bearer tok"]


def test_ice_is_quietly_missing_when_copernicus_fails(web, caplog):
    web({**TOKEN, ice.CATALOGUE: httpx.Response(503)})
    assert ice.fetch({"lake": LAKE}, TODAY) == {}
    assert "Satellite lake ice unavailable" in caplog.text


def test_ice_needs_the_account(web, monkeypatch):
    fake = web({})
    monkeypatch.delenv("CDSE_CLIENT_SECRET")
    assert ice.fetch({"lake": LAKE}, TODAY) == {}
    assert fake.requests == []


# --- lake temperature: Copernicus LSWT ---------------------------------------------------------


def lswt_zip(celsius: float) -> bytes:
    """One ten-day LSWT file: 1 km pixels (0.01°) over the lake, all good quality."""
    t = np.full((10, 10), int(round((celsius) / 0.01)), dtype="int16")
    q = np.full((10, 10), 5, dtype="int8")
    return zipped({
        "c_gls_LSWT/LSWT-LSWT_x.tif": tif(t, 11.0, 48.1, 0.01, scales=(0.01,), offsets=(273.15,), nodata=-32768),
        "c_gls_LSWT/LSWT-QLEVEL_x.tif": tif(q, 11.0, 48.1, 0.01),
    })


def lswt_product(pid: str, first: str) -> dict:
    return {"Id": pid, "Name": f"c_gls_LSWT_{first.replace('-', '')}0000_GLOBE_SLSTR_V2.0.0_cog", "ContentDate": {"Start": f"{first}T00:00:00.000Z"}}


def no_landsat(monkeypatch):
    monkeypatch.setattr(temp, "fetch_landsat", lambda *a, **k: {})


def test_lswt_reads_the_two_newest_files_once(web, monkeypatch):
    no_landsat(monkeypatch)
    products = [lswt_product("a", "2025-12-21"), lswt_product("b", "2026-01-01"), lswt_product("c", "2026-01-11")]
    fake = web({
        **TOKEN,
        temp.CATALOGUE: httpx.Response(200, json={"value": products}),
        "https://download.dataspace.copernicus.eu/odata/v1/Products(b)": httpx.Response(200, content=lswt_zip(3.0)),
        "https://download.dataspace.copernicus.eu/odata/v1/Products(c)": httpx.Response(200, content=lswt_zip(2.0)),
    })
    cache = {}
    readings = temp.fetch({"lake": LAKE}, TODAY, lswt_cache=cache)
    lake = readings["lake"]
    assert [(r.source, r.first, r.last, r.celsius) for r in lake] == [
        (temp.LSWT, date(2026, 1, 1), date(2026, 1, 10), 3.0),
        (temp.LSWT, date(2026, 1, 11), date(2026, 1, 20), 2.0),
    ]
    assert sorted(cache) == sorted(p["Name"] for p in products[1:])
    assert "LSWT" in fake.requests[0].url.params["$filter"]

    # The next run downloads nothing it has read before.
    fake.requests.clear()
    again = temp.fetch({"lake": LAKE}, TODAY, lswt_cache=cache)
    assert again == readings
    assert not [r for r in fake.requests if "download" in r.url.host]


def test_lswt_failure_leaves_landsat(web, monkeypatch, caplog):
    landsat = temp.Reading(temp.LANDSAT, date(2026, 1, 15), 4.2, 300, time=datetime(2026, 1, 15, 10, tzinfo=timezone.utc), platform="landsat-9")
    monkeypatch.setattr(temp, "fetch_landsat", lambda *a, **k: {"lake": [landsat]})
    web({**TOKEN, temp.CATALOGUE: httpx.Response(500)})
    assert temp.fetch({"lake": LAKE}, TODAY) == {"lake": [landsat]}
    assert "Copernicus lake temperature unavailable" in caplog.text


# --- lake temperature: Landsat ------------------------------------------------------------------

# Landsat's grid: UTM zone 32 north, 30 m pixels.
UTM = "EPSG:32632"


def landsat_files(tmp_path, celsius: float, cloudy_share: float):
    from rasterio.warp import transform as warp

    xs, ys = warp("EPSG:4326", UTM, [p[0] for p in LAKE], [p[1] for p in LAKE])
    west, north = min(xs) - 600, max(ys) + 600
    w, h = int((max(xs) - min(xs) + 1200) / 30), int((max(ys) - min(ys) + 1200) / 30)
    dn = int(round((celsius + 273.15 - 149.0) / 0.00341802))
    st = np.full((h, w), dn, dtype="uint16")
    qa = np.full((h, w), temp.LANDSAT_WATER_BIT, dtype="uint16")
    qa[: int(h * cloudy_share), :] = 0b1000  # cloud on the northern part
    paths = {}
    for name, data in (("st", st), ("qa", qa)):
        path = tmp_path / f"{name}.tif"
        path.write_bytes(tif(data, west, north, 30, crs=UTM))
        paths[name] = str(path)
    return paths


def scene(sid: str, when: str, paths: dict, bbox=(10.5, 47.5, 11.8, 48.6)) -> dict:
    return {"id": sid, "bbox": list(bbox), "properties": {"datetime": when, "platform": "landsat-9"},
            "assets": {"lwir11": {"href": paths["st"]}, "qa_pixel": {"href": paths["qa"]}}}


@pytest.fixture
def local_files(monkeypatch):
    """The Planetary Computer's signed links end in "?<token>"; here they are local files."""
    real = rasterio.open
    monkeypatch.setattr(rasterio, "open", lambda path, *a, **k: real(str(path).split("?")[0], *a, **k))


def test_landsat_keeps_clear_passes_newest_first_and_skips_cloudy_ones(web, tmp_path, local_files, monkeypatch):
    (tmp_path / "clear").mkdir()
    (tmp_path / "cloudy").mkdir()
    clear = landsat_files(tmp_path / "clear", 3.5, 0.0)
    cloudy = landsat_files(tmp_path / "cloudy", 9.0, 0.9)
    elsewhere = scene("far", "2026-01-12T10:05:00Z", clear, bbox=(5.0, 50.0, 6.0, 51.0))
    stac = {"features": [scene("cloudy", "2026-01-17T10:05:00Z", cloudy), scene("clear", "2026-01-09T10:05:00Z", clear), elsewhere]}
    fake = web({temp.STAC: httpx.Response(200, json=stac), temp.SAS_TOKEN: httpx.Response(200, json={"token": "sig"})})
    monkeypatch.setattr(temp, "configured", lambda: False)  # Landsat only
    monkeypatch.setattr(temp, "_sas", temp._Sas())

    found = temp.fetch({"lake": LAKE}, TODAY, landsat_days=16)
    [reading] = found["lake"]
    assert reading.source == temp.LANDSAT and reading.platform == "landsat-9"
    assert reading.day == date(2026, 1, 9) and reading.celsius == 3.5
    assert reading.pixels >= temp.LANDSAT_MIN_PIXELS

    search = json.loads(fake.requests[0].content)
    assert search["collections"] == ["landsat-c2-l2"]
    assert search["datetime"] == "2026-01-04T00:00:00Z/2026-01-20T23:59:59Z"
    # One read token for both scenes, none for the scene that cannot hold the lake.
    assert sum(1 for r in fake.requests if str(r.url).startswith(temp.SAS_TOKEN)) == 1


def test_a_landsat_scene_that_cannot_be_read_does_not_stop_the_rest(web, tmp_path, local_files, monkeypatch, caplog):
    (tmp_path / "ok").mkdir()
    good = landsat_files(tmp_path / "ok", 5.0, 0.0)
    broken = {"st": str(tmp_path / "missing.tif"), "qa": str(tmp_path / "missing.tif")}
    stac = {"features": [scene("ok", "2026-01-09T10:05:00Z", good), scene("broken", "2026-01-17T10:05:00Z", broken)]}
    web({temp.STAC: httpx.Response(200, json=stac), temp.SAS_TOKEN: httpx.Response(200, json={"token": "sig"})})
    monkeypatch.setattr(temp, "configured", lambda: False)
    monkeypatch.setattr(temp, "_sas", temp._Sas())
    found = temp.fetch({"lake": LAKE}, TODAY)
    assert [r.celsius for r in found["lake"]] == [5.0]
    assert "Landsat scene broken unreadable" in caplog.text
