from datetime import datetime, timedelta, timezone

from rowfrog import river
from rowfrog.score import HourConditions, Light, assess

NOW = datetime(2026, 10, 28, 15, tzinfo=timezone.utc)
# Like Köln on the Rhine: mean water 300 cm, mean high water 700, shipping stops at 830.
KOELN = river.Gauge("koeln", "Köln", "Rhein", 688.0, 50.94, 6.96, 1.9, ("W", "Q"),
                    {"W": {"MW": 300, "MHW": 700, "HSW I": 830, "HSW II": 1000}, "Q": {"MQ": 2100}})


def levels(*cm, step=timedelta(hours=1)):
    return [river.Reading(NOW - step * (len(cm) - 1 - i), v) for i, v in enumerate(cm)]


def test_level_states():
    assert river.level_state(320, KOELN) == "normal"
    assert river.level_state(520, KOELN) == "raised"
    assert river.level_state(700, KOELN) == "high"
    assert river.level_state(830, KOELN) == "shipping_stopped"
    assert KOELN.hsw_cm == 830, "the Rhine's first shipping mark counts"
    bare = river.Gauge("x", "X", "Ilmenau", None, 53, 10, 1, ("W",), {})
    assert river.level_state(100, bare) == ""


def test_trend_over_six_hours():
    assert river.trend(levels(300, 302, 303, 305, 307, 309, 312)) == "rising"
    assert river.trend(levels(312, 310, 309, 308, 306, 305, 304)) == "falling"
    assert river.trend(levels(300, 301, 300, 301, 302, 301, 302)) == "steady"
    assert river.trend(levels(300, 301)) == ""


def test_speed_from_discharge_width_and_depth():
    # 2,100 m³/s through 400 m x 4 m at mean water: about 1.3 m/s.
    assert river.estimate_speed(2100, 400, 300, KOELN, "Rhein") == 1.31
    # Two metres higher, the same discharge is spread over more depth.
    assert river.estimate_speed(2100, 400, 500, KOELN, "Rhein") == 0.88


def test_river_now_and_its_light():
    now = river.now_at(KOELN, levels(840, 845, 850, 852, 855, 857, 860), levels(6000), [], 400, "Rhein", NOW)
    assert (now.state, now.trend, now.speed_measured) == ("shipping_stopped", "rising", False)
    assert now.light == ("shipping_stopped", Light.RED)
    high = river.now_at(KOELN, levels(720), levels(2100), [], 400, "Rhein", NOW)
    assert high.light == ("high_water", Light.AMBER)
    fast = river.now_at(KOELN, levels(300), [], levels(2.7), None, "Rhein", NOW)
    assert fast.speed_measured and fast.light == ("current", Light.RED)
    calm = river.now_at(KOELN, levels(300), levels(500), [], 400, "Rhein", NOW)
    assert calm.light is None
    assert river.now_at(KOELN, [river.Reading(NOW - timedelta(hours=7), 300)], [], [], 400, "Rhein", NOW) is None, "too old"


def test_river_reason_in_the_verdict():
    a = assess(HourConditions(wind_speed_ms=1, wind_gust_ms=2, river_name="shipping_stopped", river=Light.RED))
    assert a.light == Light.RED and ("shipping_stopped", Light.RED) in a.reasons


def test_json_block():
    now = river.now_at(KOELN, levels(300, 301), levels(2000), [], 400, "Rhein", NOW)
    block = river.to_json(now, KOELN)
    assert block["gauge"]["shippingStopsCm"] == 830 and block["now"]["state"] == "normal"
    assert block["now"]["light"] == "green" and len(block["now"]["history"]) == 2
    assert river.to_json(None, KOELN)["now"] is None


def test_river_clubs_forecast_carries_the_gauge(monkeypatch):
    from fastapi.testclient import TestClient

    from rowfrog import api
    from rowfrog.sources import open_meteo

    from .test_forecast import PAYLOAD

    async def fake_fetch(client, lat, lon, hours=48):
        return open_meteo.parse(PAYLOAD)

    async def nothing(*args, **kwargs):
        return None

    async def no_history(*args, **kwargs):
        return None, []

    async def no_warnings(client, club, now):
        return {"status": "ok", "lakeArea": None, "items": []}, []

    now = datetime.now(timezone.utc)

    async def series(client, station, name, days=2):
        values = {"W": [840, 850, 860], "Q": [6000, 6100, 6200]}[name]
        return [(now - timedelta(hours=2 - i), v) for i, v in enumerate(values)]

    club = next(c for c in api._locations.clubs.values() if api._locations.lakes[c.lake_id].kind == "river")
    monkeypatch.setattr(open_meteo, "fetch", fake_fetch)
    monkeypatch.setattr(open_meteo, "fetch_outlook", nothing)
    monkeypatch.setattr(api.gkd, "fetch_latest", nothing)
    monkeypatch.setattr(api.gkd, "fetch_recent", no_history)
    monkeypatch.setattr(api.pegelonline, "fetch_recent", no_history)
    monkeypatch.setattr(api.bafu, "fetch_recent", no_history, raising=False)
    monkeypatch.setattr(api, "_warnings", no_warnings)
    monkeypatch.setattr(api, "_air_days", nothing)
    monkeypatch.setattr(river, "gauge_for", lambda club_id: KOELN if club_id == club.id else None)
    monkeypatch.setattr(api.pegelonline, "fetch_series", series)
    api._cache.clear()
    api._gauge_cache.clear()
    body = TestClient(api.app).get(f"/clubs/{club.id}/forecast").json()
    api._cache.clear()
    api._gauge_cache.clear()
    assert body["river"]["now"]["state"] == "shipping_stopped"
    assert body["river"]["gauge"]["name"] == "Köln"
    first = body["hours"][0]
    assert first["light"] == "red" and any(r["condition"] == "shipping_stopped" for r in first["reasons"])
