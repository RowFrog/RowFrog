from datetime import datetime, timezone

import httpx
from fastapi.testclient import TestClient

from rowfrog import api
from rowfrog.forecast import _weather_warning
from rowfrog.score import Light
from rowfrog.sources import meteoalarm

from .test_dwd_warnings import _fake_weather, _reset, _serve

NOW = datetime(2026, 10, 18, 4, tzinfo=timezone.utc)
# Around Zürich (the Seeclub Zürich launch point is 47.357, 8.536), as "lat,lon" pairs.
ZURICH = "47.30,8.45 47.30,8.65 47.42,8.65 47.42,8.45 47.30,8.45"
GENEVA = "46.15,6.05 46.15,6.25 46.30,6.25 46.30,6.05 46.15,6.05"


def _info(lang, event, headline, polygon, level="2; yellow; Moderate", kind="1; Wind", expires="2026-10-18T22:00:00+00:00"):
    return {
        "language": lang,
        "event": event,
        "headline": headline,
        "description": f"{headline}: Böen 70 km/h." if lang == "de" else f"{headline}: gusts of 70 km/h.",
        "instruction": "Achtung am See." if lang == "de" else "Take care on the lake.",
        "onset": "2026-10-18T03:00:00+00:00",
        "expires": expires,
        "severity": "Moderate",
        "senderName": "MeteoSwiss",
        "parameter": [{"valueName": "awareness_level", "value": level}, {"valueName": "awareness_type", "value": kind}],
        "area": [{"areaDesc": "Zürich" if polygon == ZURICH else "Genève", "polygon": [polygon]}],
    }


def _feed():
    def warning(uid, polygon, **kw):
        return {
            "uuid": uid,
            "alert": {
                "identifier": f"2.49.0.0.756.0.CH.{uid}",
                "msgType": "Alert",
                "status": "Actual",
                "info": [
                    _info("de", "Stürmischer Wind", "Stürmischer Wind", polygon, **kw),
                    _info("en", "Gale force wind", "Gale force wind", polygon, **kw),
                ],
            },
        }

    return {
        "warnings": [
            warning("zh", ZURICH),
            warning("ge", GENEVA),
            warning("old", ZURICH, expires="2026-10-17T22:00:00+00:00"),
            warning("fire", ZURICH, kind="8; forest-fire"),
            warning("storm", ZURICH, level="3; orange; Severe", kind="3; Thunderstorm"),
        ]
    }


def test_parse_keeps_running_warnings_for_the_water():
    alerts = meteoalarm.parse(_feed(), NOW)
    assert [a.warning.identifier for a in alerts] == ["meteoalarm-2.49.0.0.756.0.CH.zh", "meteoalarm-2.49.0.0.756.0.CH.ge", "meteoalarm-2.49.0.0.756.0.CH.storm"]
    wind, _, storm = alerts
    assert wind.warning.event == "WIND" and wind.warning.severity == "Minor" and wind.warning.source == "meteoswiss"
    assert wind.warning.headline == "Stürmischer Wind" and wind.warning.area == "Zürich"
    assert wind.english.headline == "Gale force wind" and wind.english.official
    assert storm.warning.event == "GEWITTER" and storm.warning.severity == "Moderate"
    assert _weather_warning([wind.warning], NOW, NOW) == Light.AMBER
    assert _weather_warning([storm.warning], NOW, NOW) == Light.RED


def test_for_point_matches_the_region():
    alerts = meteoalarm.parse(_feed(), NOW)
    assert [a.warning.area for a in meteoalarm.for_point(alerts, 8.536, 47.357)] == ["Zürich", "Zürich"]
    assert [a.warning.area for a in meteoalarm.for_point(alerts, 6.15, 46.20)] == ["Genève"]
    assert meteoalarm.for_point(alerts, 7.45, 46.95) == []
    # Polygons may also come as one list of "lat,lon" points.
    assert meteoalarm._rings([{"polygon": ["47.0,8.0", "47.0,8.1", "47.1,8.1"]}]) == [[(8.0, 47.0), (8.1, 47.0), (8.1, 47.1)]]


def test_swiss_club_gets_meteoswiss_warnings_from_one_feed_call(monkeypatch):
    _fake_weather(monkeypatch)
    calls = []

    def handler(request):
        if request.url.host == "feeds.meteoalarm.org":
            calls.append(request.url.path)
            return httpx.Response(200, json=_feed())
        return httpx.Response(200, json={"features": []})

    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(handler))
    monkeypatch.setattr(api, "_now", lambda: NOW)
    _reset()
    client = TestClient(api.app)
    body = client.get("/clubs/seeclub-zuerich/forecast").json()
    client.get("/clubs/grasshopper-club-zuerich/forecast")
    _reset()
    w = body["warnings"]
    assert w["status"] == "ok" and w["local"]["source"] == "meteoswiss" and w["local"]["checked"] is True
    assert [(i["source"], i["event"]) for i in w["items"]] == [("meteoswiss", "WIND"), ("meteoswiss", "GEWITTER")]
    assert w["items"][0]["english"]["headline"] == "Gale force wind"
    assert "Warnings: MeteoSwiss, via MeteoAlarm (EUMETNET)" in body["attribution"]
    assert calls == ["/api/v1/warnings/feeds-switzerland"], "one feed call serves both clubs"


def test_sample_warning_club_without_lake_area_gets_a_sample_from_its_own_service(monkeypatch):
    _fake_weather(monkeypatch)
    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(lambda request: httpx.Response(200, json={"warnings": [], "features": []})))
    monkeypatch.setattr(api, "_now", lambda: NOW)
    monkeypatch.setattr(api, "SAMPLE_WARNING_CLUBS", {"seeclub-zuerich"})
    _reset()
    body = TestClient(api.app).get("/clubs/seeclub-zuerich/forecast").json()
    _reset()
    [item] = body["warnings"]["items"]
    assert (item["source"], item["event"], item["sample"]) == ("meteoswiss", "GEWITTER", True)
    assert "weather_warning" in [r["condition"] for r in body["hours"][0]["reasons"]]
