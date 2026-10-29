from datetime import datetime, timedelta, timezone

from rowfrog import lake_level
from rowfrog.score import HourConditions, Light, assess
from rowfrog.sources import gkd

NOW = datetime(2026, 12, 10, 12, tzinfo=timezone.utc)
FORGGENSEE = lake_level.for_lake("forggensee")


def readings(*m, step=timedelta(hours=1)):
    return [(NOW - step * (len(m) - 1 - i), v) for i, v in enumerate(m)]


def test_forggensee_has_its_gauge_and_marks():
    assert FORGGENSEE.station == "rosshaupten-seepegel-12001301"
    assert FORGGENSEE.drained_below_m < FORGGENSEE.lowered_below_m < FORGGENSEE.full_m
    assert lake_level.for_lake("starnberger-see") is None


def test_states_follow_the_marks():
    # Values from the gauge's 2025/26 season.
    assert lake_level.state(780.32, FORGGENSEE) == "full"  # 29 Oct
    assert lake_level.state(779.44, FORGGENSEE) == "lowered"  # 16 Nov
    assert lake_level.state(774.14, FORGGENSEE) == "drained"  # 11 Feb


def test_now_trend_and_light():
    falling = [780.0 - 0.01 * i for i in range(30)]
    now = lake_level.now_at(FORGGENSEE, readings(*falling), NOW)
    assert now.state == "lowered" and now.trend == "falling"
    assert now.light == ("lake_lowered", Light.AMBER)
    drained = lake_level.now_at(FORGGENSEE, readings(774.2, 774.2), NOW)
    assert drained.light == ("lake_drained", Light.RED) and drained.trend == ""
    assert lake_level.now_at(FORGGENSEE, readings(780.5), NOW).light is None
    old = [(NOW - timedelta(hours=13), 776.0)]
    assert lake_level.now_at(FORGGENSEE, old, NOW) is None, "a stale reading does not count"


def test_reason_turns_the_verdict():
    a = assess(HourConditions(wind_speed_ms=1, wind_gust_ms=2, river_name="lake_drained", river=Light.RED))
    assert a.light == Light.RED and ("lake_drained", Light.RED) in a.reasons


def test_json_block():
    now = lake_level.now_at(FORGGENSEE, readings(776.5, 776.4), NOW)
    out = lake_level.to_json(now, FORGGENSEE)
    assert out["now"]["state"] == "drained" and out["now"]["light"] == "red"
    assert out["now"]["belowFullM"] == 4.2
    assert len(out["now"]["history"]) == 2
    assert lake_level.to_json(None, FORGGENSEE)["now"] is None


def test_gkd_level_page_parses_oldest_first():
    page = "<td>29.10.2026 07:15</td><td>780.32</td><td>29.10.2026 07:00</td><td>780.33</td>"
    rows = [(r.time, r.celsius) for r in reversed(gkd.parse(page))]
    assert [v for _, v in rows] == [780.33, 780.32]
    assert gkd.LEVEL_URL.format(station="x").endswith("/waterlevel/bayern/x/current-values/table")
