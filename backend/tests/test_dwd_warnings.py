import asyncio
import io
import zipfile
from datetime import datetime, timezone

import httpx
from fastapi.testclient import TestClient

from rowfrog import api, locations
from rowfrog.forecast import rowing_forecast, warning_topic
from rowfrog.score import Light
from rowfrog.sources import dwd_warnings, open_meteo

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


def test_frost_and_heat_warnings_leave_the_light_alone():
    for event in ("FROST", "STRENGER FROST", "GLÄTTE", "GLATTEIS", "TAUWETTER", "HITZE"):
        ws = [w for _, w in dwd_warnings.parse_warnings({"features": [_warning(1, event, "Moderate")]}, "local")]
        (hour, _) = rowing_forecast(_club(), open_meteo.parse(PAYLOAD), None, None, ws)
        assert all(name != "weather_warning" for name, _ in hour.assessment.reasons), event
        assert hour.warning_topic is None


def test_warning_topic_names_what_the_warning_is_about():
    assert warning_topic("STURMBÖEN") == "wind"
    assert warning_topic("SCHWERES GEWITTER mit HAGEL") == "thunderstorm"
    assert warning_topic("DAUERREGEN") == "rain"
    assert warning_topic("SCHNEEVERWEHUNG") == "snow"
    assert warning_topic("NEBEL") == "fog"
    assert warning_topic("FROST") is None
    assert warning_topic("WARNUNG") == "other"  # unknown events still count


def test_worst_weather_warning_names_the_topic():
    ws = [
        w
        for _, w in dwd_warnings.parse_warnings(
            {"features": [_warning(1, "NEBEL", "Minor"), _warning(1, "STURMBÖEN", "Moderate"), _warning(1, "FROST", "Moderate")]},
            "local",
        )
    ]
    (hour, _) = rowing_forecast(_club(), open_meteo.parse(PAYLOAD), None, None, ws)
    assert ("weather_warning", Light.RED) in hour.assessment.reasons
    assert hour.warning_topic == "wind"
    assert {"condition": "weather_warning", "light": "red", "topic": "wind"} in api._hour_json(hour)["reasons"]


def test_sample_frost_warning_shows_but_leaves_the_light_alone(monkeypatch):
    _fake_weather(monkeypatch)

    def handler(request):
        return httpx.Response(200, json={"features": []})

    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(handler))
    monkeypatch.setattr(api, "SAMPLE_FROST_CLUBS", {"mrc-1880"})
    _reset()
    body = TestClient(api.app).get("/clubs/mrc-1880/forecast").json()
    _reset()
    assert [i["event"] for i in body["warnings"]["items"]] == ["FROST"]
    assert all(r["condition"] != "weather_warning" for h in body["hours"] for r in h["reasons"])


def test_shore_lights_list_covers_every_dwd_lake_area():
    # The 23 areas DWD's GeoServer listed on 30.10.2026 (scripts/lake_lights_check.py).
    assert dwd_warnings.has_shore_lights(209904000)  # Starnberger See
    assert dwd_warnings.has_shore_lights(208439000)  # Bodensee - West
    assert not dwd_warnings.has_shore_lights(202006000)  # Alster: DWD warns, no lights
    assert not dwd_warnings.has_shore_lights(213010000)  # Müritz: lights only planned
    assert not dwd_warnings.has_shore_lights(1)  # unknown areas: no lights claimed


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
    api._swiss_alerts = None
    api._lake_warnings = None
    api._english = None
    api._primed_local_warnings.clear()


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

    async def no_water_history(*args, **kwargs):
        return None, []

    monkeypatch.setattr(api.gkd, "fetch_recent", no_water_history)


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
    assert body["warnings"] == {
        "status": "ok",
        "lakeArea": "Starnberger See",
        "items": [],
        "local": {"source": "dwd", "service": "Deutscher Wetterdienst (DWD)", "url": "https://www.wettergefahren.de/", "checked": True},
        "shoreLights": True,
    }
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


def _local(cell: int, event: str) -> dict:
    return {"properties": {"WARNCELLID": cell, "NAME": f"Gemeinde {cell}", "EVENT": event, "SEVERITY": "Minor", "IDENTIFIER": f"{cell}.{event}.DEU"}}


def test_local_warnings_for_many_cells_take_a_few_queries(monkeypatch):
    queries = []

    def handler(request):
        cql = request.url.params["CQL_FILTER"]
        queries.append(cql)
        asked = [int(x) for x in cql[cql.index("(") + 1 : -1].split(",")]
        return httpx.Response(200, json={"features": [_local(c, "WINDBÖEN") for c in asked if c % 100 == 0]})

    cells = list(range(1, 401))

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await dwd_warnings.fetch_local_warnings_for_cells(client, cells)

    got = asyncio.run(run())
    assert len(queries) == 3 and all(q.startswith("WARNCELLID IN (") for q in queries)
    assert set(got) == set(cells), "every cell asked for gets a list"
    assert [w.event for w in got[100]] == ["WINDBÖEN"] and got[101] == []


def test_warn_cell_lookup_reads_the_municipality(monkeypatch):
    def handler(request):
        assert request.url.params["typeName"] == "dwd:Warngebiete_Gemeinden"
        assert "INTERSECTS(SHAPE,POINT(47.99 11.34))" == request.url.params["CQL_FILTER"]
        return httpx.Response(200, json={"features": [{"properties": {"WARNCELLID": 809188139}}]})

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await dwd_warnings.fetch_warn_cell(client, 11.34, 47.99)

    assert asyncio.run(run()) == 809188139


def test_primed_local_warnings_are_used_without_asking_dwd(monkeypatch):
    _fake_weather(monkeypatch)
    seen = []

    def handler(request):
        seen.append(request.url.params["typeName"])
        return httpx.Response(200, json={"features": []})

    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(handler))
    _reset()
    api._primed_local_warnings["mrc-1880"] = [w for _, w in dwd_warnings.parse_warnings({"features": [_local(809188139, "WINDBÖEN")]}, "local")]
    body = TestClient(api.app).get("/clubs/mrc-1880/forecast").json()
    _reset()
    assert [i["event"] for i in body["warnings"]["items"]] == ["WINDBÖEN"]
    assert "dwd:Warnungen_Gemeinden" not in seen


def test_clubs_without_a_warning_service_do_not_claim_no_warning(monkeypatch):
    _fake_weather(monkeypatch)
    seen = []

    def handler(request):
        seen.append(request.url.params.get("typeName"))
        return httpx.Response(200, json={"features": []})

    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(handler))
    # A country without a service the app reads (as Switzerland was before MeteoAlarm).
    monkeypatch.setattr(api, "CHECKED_COUNTRIES", {"de", "at"})
    _reset()
    body = TestClient(api.app).get("/clubs/seeclub-zuerich/forecast").json()
    mrc = TestClient(api.app).get("/clubs/mrc-1880/forecast").json()
    _reset()
    assert body["warnings"]["local"]["checked"] is False and body["warnings"]["local"]["service"] == "MeteoSwiss"
    assert seen.count("dwd:Warnungen_Gemeinden") == 1, "DWD is asked for the German club only"
    assert mrc["warnings"]["local"]["checked"] is True
