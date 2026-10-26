import asyncio
from datetime import datetime, timezone

import httpx
from fastapi.testclient import TestClient

from rowfrog import api
from rowfrog.forecast import _weather_warning
from rowfrog.score import Light
from rowfrog.sources import geosphere_warnings

from .test_dwd_warnings import _fake_weather, _reset, _serve


def _answer(lang="de"):
    """As GeoSphere's Warn API spec shows it (Schwechat, 2023), geometry left out."""
    text = "Gelbe Windwarnung von Mo, 27.03.2023 08:00 bis Mo, 27.03.2023 18:00" if lang == "de" else "Yellow wind warning from Mon, 27.03.2023 08:00 to Mon, 27.03.2023 18:00"
    return {
        "type": "Feature",
        "properties": {
            "location": {"type": "Municipal", "properties": {"gemeindenr": 30740, "name": "Schwechat", "urlname": "schwechat"}},
            "warnings": [
                {
                    "type": "Warning",
                    "properties": {
                        "warnid": 4149,
                        "chgid": 6,
                        "verlaufid": 2,
                        "warntypid": 1,
                        "begin": "27.03.2023 08:00",
                        "end": "27.03.2023 18:00",
                        "create": "2023-03-27 06:00:00+00",
                        "text": text,
                        "auswirkungen": "* Äste können herabstürzen." if lang == "de" else "* Branches may fall.",
                        "empfehlungen": "* Seien Sie in Wäldern achtsam!" if lang == "de" else "* Take care in forests!",
                        "meteotext": "Windspitzen zwischen 60 und 80 km/h." if lang == "de" else "Gusts of 60 to 80 km/h.",
                        "updategrund": "",
                        "warnstufeid": 1,
                        "rawinfo": {"wtype": 1, "wlevel": 1, "start": "1679896800", "end": "1679932800"},
                    },
                },
                {
                    "type": "Warning",
                    "properties": {
                        "warnid": 4200,
                        "warntypid": 5,
                        "warnstufeid": 2,
                        "begin": "27.03.2023 14:00",
                        "end": "27.03.2023 20:00",
                        "text": "Orange Gewitterwarnung",
                        "auswirkungen": "",
                        "empfehlungen": None,
                        "meteotext": "",
                        "rawinfo": {},
                    },
                },
            ],
        },
    }


def test_parse_maps_type_level_and_times():
    (wid, wind), (_, storm) = geosphere_warnings.parse(_answer())
    assert wid == 4149 and wind.event == "WIND" and wind.severity == "Minor" and wind.area == "Schwechat"
    assert wind.onset == datetime(2023, 3, 27, 6, tzinfo=timezone.utc)
    assert wind.expires == datetime(2023, 3, 27, 16, tzinfo=timezone.utc)
    assert wind.description == "* Äste können herabstürzen.\n\nWindspitzen zwischen 60 und 80 km/h."
    assert wind.instruction == "* Seien Sie in Wäldern achtsam!" and wind.source == "geosphere"
    # Without rawinfo the local time text counts (CEST in summer time).
    assert storm.event == "GEWITTER" and storm.severity == "Moderate" and storm.instruction is None
    assert storm.onset == datetime(2023, 3, 27, 12, tzinfo=timezone.utc)
    # A thunderstorm makes the hour red, a yellow wind warning amber, as with DWD.
    assert _weather_warning([wind], wind.onset, wind.expires) == Light.AMBER
    assert _weather_warning([storm], storm.onset, storm.expires) == Light.RED


def test_english_texts_are_geospheres_own():
    german = geosphere_warnings.parse(_answer())
    english = _answer("en")
    del english["properties"]["warnings"][1]
    texts = geosphere_warnings.english_texts(german, english)
    wind = texts["geosphere-4149"]
    assert wind.official and wind.event == "wind" and wind.headline.startswith("Yellow wind warning")
    assert wind.description == "* Branches may fall.\n\nGusts of 60 to 80 km/h."
    # A warning missing from the English answer gets a translated event only.
    assert texts["geosphere-4200"].official is False and texts["geosphere-4200"].event == "thunderstorms"


def test_fetch_asks_english_only_while_a_warning_is_out():
    asked = []

    def handler(request):
        asked.append(request.url.params["lang"])
        return httpx.Response(200, json={"type": "Feature", "properties": {"location": {}, "warnings": []}})

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await geosphere_warnings.fetch(client, 13.78, 47.91)

    assert asyncio.run(run()) == ([], {}) and asked == ["de"]


def test_austrian_club_gets_geosphere_warnings(monkeypatch):
    _fake_weather(monkeypatch)
    seen = []

    def handler(request):
        if request.url.host == "warnungen.zamg.at":
            seen.append(request.url.params["lang"])
            return httpx.Response(200, json=_answer(request.url.params["lang"]))
        return httpx.Response(200, json={"features": []})

    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(handler))
    monkeypatch.setattr(api, "_now", lambda: datetime(2023, 3, 27, 7, tzinfo=timezone.utc))
    _reset()
    body = TestClient(api.app).get("/clubs/gmundner-ruderverein/forecast").json()
    _reset()
    w = body["warnings"]
    assert w["status"] == "ok" and w["local"]["source"] == "geosphere" and w["local"]["checked"] is True
    assert [(i["source"], i["event"], i["severity"]) for i in w["items"]] == [("geosphere", "WIND", "minor"), ("geosphere", "GEWITTER", "moderate")]
    assert w["items"][0]["english"]["official"] is True
    assert "Warnings: GeoSphere Austria, CC BY 4.0" in body["attribution"]
    assert sorted(seen) == ["de", "en"]


def test_geosphere_down_reports_unavailable(monkeypatch):
    _fake_weather(monkeypatch)

    def handler(request):
        if request.url.host == "warnungen.zamg.at":
            return httpx.Response(503)
        return httpx.Response(200, json={"features": []})

    monkeypatch.setattr(api.httpx, "AsyncClient", _serve(handler))
    _reset()
    body = TestClient(api.app).get("/clubs/gmundner-ruderverein/forecast").json()
    _reset()
    assert body["warnings"]["status"] == "unavailable" and body["warnings"]["local"]["source"] == "geosphere"
