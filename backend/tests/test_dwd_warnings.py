import asyncio
import io
import zipfile
from datetime import datetime, timezone

import httpx
from fastapi.testclient import TestClient

from rowerweather import api, locations
from rowerweather.forecast import rowing_forecast
from rowerweather.score import Light
from rowerweather.sources import dwd_warnings, open_meteo

from .test_forecast import PAYLOAD

# Shapes as DWD's GeoServer returns them (18.10.2026): lake areas in lon/lat,
# warnings without geometry.
SQUARE = [[[11.30, 47.90], [11.40, 47.90], [11.40, 48.00], [11.30, 48.00], [11.30, 47.90]]]
AREAS = {
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "geometry": {"type": "MultiPolygon", "coordinates": [SQUARE]},
            "properties": {"WARNCELLID": 209904000, "NAME": "Starnberger See"},
        }
    ],
}


def _warning(cell, event, severity, onset="2026-10-18T06:00:00Z", expires="2026-10-18T07:00:00Z", **extra):
    props = {
        "WARNCELLID": cell,
        "STATUS": "Actual",
        "MSGTYPE": "Alert",
        "EVENT": event,
        "SEVERITY": severity,
        "HEADLINE": f"Amtliche WARNUNG vor {event}",
        "DESCRIPTION": "Es treten Windböen auf.",
        "INSTRUCTION": None,
        "ONSET": onset,
        "EXPIRES": expires,
    }
    props.update(extra)
    return {"type": "Feature", "geometry": None, "properties": props}


def test_lake_area_found_inside_and_just_off_the_polygon():
    areas = dwd_warnings.parse_lake_areas(AREAS)
    assert dwd_warnings.lake_area_for(11.35, 47.95, areas).name == "Starnberger See"
    # 500 m west of the edge: a boathouse on the shore still belongs to the lake.
    assert dwd_warnings.lake_area_for(11.30 - 0.0067, 47.95, areas) is not None
    assert dwd_warnings.lake_area_for(11.20, 47.95, areas) is None


def test_geometry_in_lat_lon_order_is_normalised():
    flipped = [[[lat, lon] for lon, lat in ring] for ring in SQUARE]
    areas = dwd_warnings.parse_lake_areas(
        {"features": [{"geometry": {"type": "Polygon", "coordinates": flipped}, "properties": {"WARNCELLID": 1, "NAME": "x"}}]}
    )
    assert dwd_warnings.lake_area_for(11.35, 47.95, areas) is not None


def test_parse_warnings_drops_tests_and_cancels():
    parsed = dwd_warnings.parse_warnings(
        {
            "features": [
                _warning(1, "STURM", "Severe"),
                _warning(1, "STURM", "Severe", STATUS="Test"),
                _warning(1, "STURM", "Severe", MSGTYPE="Cancel"),
            ]
        },
        "lake",
    )
    assert len(parsed) == 1
    cell, w = parsed[0]
    assert cell == 1 and w.level == 2
    assert w.onset == datetime(2026, 10, 18, 6, tzinfo=timezone.utc)


def _club():
    return locations.Club(
        id="t", name="T", short_name="T", lake_id="l", address="", website=None,
        launch_point=locations.Point(lat=47.95, lon=11.35), launch_point_verified=True,
    )


def test_lake_storm_warning_turns_its_hours_red():
    (_, storm), = dwd_warnings.parse_warnings({"features": [_warning(1, "STURM", "Severe")]}, "lake")
    calm, windy = rowing_forecast(_club(), open_meteo.parse(PAYLOAD), None, None, [storm])
    assert ("lake_warning", Light.RED) in calm.assessment.reasons
    assert all(name != "lake_warning" for name, _ in windy.assessment.reasons)  # expired by 07:00


def test_minor_weather_warning_is_amber_and_thunderstorm_red():
    ws = [w for _, w in dwd_warnings.parse_warnings({"features": [_warning(1, "WINDBÖEN", "Minor")]}, "local")]
    (hour, _) = rowing_forecast(_club(), open_meteo.parse(PAYLOAD), None, None, ws)
    assert ("weather_warning", Light.AMBER) in hour.assessment.reasons
    ws = [w for _, w in dwd_warnings.parse_warnings({"features": [_warning(1, "GEWITTER", "Minor")]}, "local")]
    (hour, _) = rowing_forecast(_club(), open_meteo.parse(PAYLOAD), None, None, ws)
    assert ("weather_warning", Light.RED) in hour.assessment.reasons


def _serve(handler):
    original = httpx.AsyncClient

    class Mocked(original):
        def __init__(self, *args, **kwargs):
            kwargs["transport"] = httpx.MockTransport(handler)
            super().__init__(*args, **kwargs)

    return Mocked


def _reset():
    api._cache.clear()
    api._warnings_cache.clear()
    api._lake_areas = None
    api._english = None


def _fake_weather(monkeypatch):
    async def fake_fetch(client, lat, lon, hours=48):
        return open_meteo.parse(PAYLOAD)

    async def no_water(*args, **kwargs):
        return None

    async def no_outlook(client, lat, lon):
        return None

    monkeypatch.setattr(open_meteo, "fetch", fake_fetch)
    monkeypatch.setattr(open_meteo, "fetch_outlook", no_outlook)
    monkeypatch.setattr(api.gkd, "fetch_latest", no_water)


def test_forecast_says_no_warning_after_checking(monkeypatch):
    _fake_weather(monkeypatch)
    seen = []

    def handler(request):
        layer = request.url.params["typeName"]
        seen.append(layer)
        if layer == "dwd:Warngebiete_Binnenseen":
            return httpx.Response(200, json={"features": [{"geometry": {"type": "Polygon", "coordinates": [[[11.2, 47.8], [11.5, 47.8], [11.5, 48.1], [11.2, 48.1]]]}, "properties": {"WARNCELLID": 209904000, "NAME": "Starnberger See"}}]})
        return httpx.Response(200, json={"features": []})

    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(handler))
    _reset()
    body = TestClient(api.app).get("/clubs/mrc-1880/forecast").json()
    _reset()
    assert body["warnings"] == {"status": "ok", "lakeArea": "Starnberger See", "items": []}
    assert "dwd:Warnungen_Binnenseen" in seen and "dwd:Warnungen_Gemeinden" in seen


def test_forecast_reports_unavailable_warnings(monkeypatch):
    _fake_weather(monkeypatch)
    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(lambda request: httpx.Response(503)))
    _reset()
    body = TestClient(api.app).get("/clubs/mrc-1880/forecast").json()
    _reset()
    assert body["warnings"]["status"] == "unavailable"
    assert body["hours"], "the forecast still comes through"


ENGLISH_CAP = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2">
  <identifier>2.49.0.0.276.0.DWD.PVW.1.abc.ENG</identifier>
  <info>
    <language>en</language>
    <event>wind gusts</event>
    <headline>Official WARNING of WIND GUSTS</headline>
    <description>There is a risk of wind gusts (level 1 of 4).</description>
    <instruction>NOTE: be aware that this is an automatically generated product.</instruction>
  </info>
</alert>"""


def _english_zip() -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("2.49.0.0.276.0.DWD.PVW.1.abc.ENG.xml", ENGLISH_CAP)
    return buf.getvalue()


def test_english_cap_is_keyed_like_the_german_warning():
    texts = dwd_warnings.parse_english_cap(_english_zip())
    (_, w), = dwd_warnings.parse_warnings(
        {"features": [_warning(1, "WINDBÖEN", "Minor", IDENTIFIER="2.49.0.0.276.0.DWD.PVW.1.abc.DEU")]}, "local"
    )
    english = texts[w.identifier]
    assert english.headline == "Official WARNING of WIND GUSTS" and english.official


def test_english_fallback_translates_event_and_headline_only():
    (_, w), = dwd_warnings.parse_warnings({"features": [_warning(1, "STURMBÖEN", "Moderate")]}, "local")
    english = dwd_warnings.english_fallback(w)
    assert english.headline == "Official WARNING of GALE-FORCE GUSTS"
    assert english.description is None and not english.official


def test_forecast_warning_carries_english_and_german(monkeypatch):
    _fake_weather(monkeypatch)

    def handler(request):
        if request.url.host == "opendata.dwd.de":
            return httpx.Response(200, content=_english_zip())
        layer = request.url.params["typeName"]
        if layer == "dwd:Warnungen_Gemeinden":
            return httpx.Response(200, json={"features": [_warning(1, "WINDBÖEN", "Minor", IDENTIFIER="2.49.0.0.276.0.DWD.PVW.1.abc.DEU", EXPIRES="2099-01-01T00:00:00Z")]})
        return httpx.Response(200, json={"features": []})

    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(handler))
    _reset()
    body = TestClient(api.app).get("/clubs/mrc-1880/forecast").json()
    _reset()
    (item,) = body["warnings"]["items"]
    assert item["headline"] == "Amtliche WARNUNG vor WINDBÖEN"
    assert item["english"]["headline"] == "Official WARNING of WIND GUSTS"
    assert item["english"]["official"] is True
