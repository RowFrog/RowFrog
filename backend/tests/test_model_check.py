from datetime import date, datetime, timezone

from rowfrog import model_check as mc

UTC = timezone.utc
P = [mc.Point("a", "A", 47.9, 11.3, 1), mc.Point("b", "B", 48.0, 11.1, 1)]


def _payload(winds_a, winds_b):
    def one(winds):
        return {"hourly": {
            "time": ["2026-10-23T10:00", "2026-10-23T11:00"],
            "wind_speed_10m": winds,
            "wind_gusts_10m": [w and w + 3 for w in winds],
            "wind_direction_10m": [200, 210],
            "temperature_2m": [10.0, 11.0],
            "precipitation": [0.0, 0.2],
        }}
    return [one(winds_a), one(winds_b)]


def test_rows_skip_hours_outside_the_model_area():
    issued = datetime(2026, 10, 23, 4, tzinfo=UTC)
    rows = mc.rows_from_payload(_payload([3.0, 4.0], [None, None]), P, "icon_d2", issued)
    assert [(r["point"], r["lead_h"]) for r in rows] == [("a", 6), ("a", 7)]
    assert rows[0]["issued"] == "2026-10-23T04:00Z"


def test_archive_rows_have_no_lead():
    rows = mc.rows_from_payload(_payload([3.0, 4.0], [1.0, 2.0]), P, "icon_d2", None)
    assert {r["issued"] for r in rows} == {"archive"}
    assert mc.bucket(rows[0]) == "archive"


def test_station_list_and_nearest():
    text = (
        "Stations_id von_datum bis_datum Stationshoehe geoBreite geoLaenge Stationsname Bundesland Abgabe\n"
        "----------- --------- ---------\n"
        "03739 19930101 20261022 586 48.0816 11.2836 Oberpfaffenhofen Bayern Frei\n"
        "01262 19930101 20261022 446 48.3477 11.8134 München-Flughafen Bayern Frei\n"
        "09999 19930101 20001231 500 47.9 11.3 Alt Bayern Frei\n"
    )
    stations = mc.parse_station_list(text)
    assert [s.id for s in stations] == ["03739", "01262", "09999"]
    assert stations[1].name == "München-Flughafen"
    station, km = mc.nearest_station(stations, 47.9, 11.3, date(2026, 10, 20))
    assert station.id == "03739" and 19 < km < 22  # the closed station is skipped


def test_measurements_and_hourly_values():
    text = (
        "STATIONS_ID;MESS_DATUM;  QN;FX_10;eor\n"
        + "".join(f"3739;2026102310{m:02d};    3;   {v};eor\n" for m, v in [(10, 5.0), (20, 7.5), (30, -999), (40, 6.0), (50, 4.0)])
        + "3739;202610231100;    3;   5.5;eor\n"
    )
    values = mc.parse_measurements(text, "FX_10")
    assert len(values) == 5
    gusts = mc.hourly(values, "gust")
    assert gusts == {datetime(2026, 10, 23, 11, tzinfo=UTC): 7.5}
    assert mc.hourly(values, "wind") == {datetime(2026, 10, 23, 11, tzinfo=UTC): 5.5}


def test_score_and_report():
    issued = datetime(2026, 10, 23, 4, tzinfo=UTC)
    rows = mc.rows_from_payload(_payload([3.0, 9.0], [2.0, 2.0]), P, "icon_d2", issued)
    rows += mc.rows_from_payload(_payload([6.0, 9.0], [2.0, 2.0]), P, "best_match", issued)
    t10, t11 = datetime(2026, 10, 23, 10, tzinfo=UTC), datetime(2026, 10, 23, 11, tzinfo=UTC)
    obs = {"a": {"wind": {t10: 4.0, t11: 8.0}, "gust": {t10: 6.0, t11: 12.0}, "temp": {t10: 9.0}}}
    scores = mc.score(rows, obs)
    s = scores[("a", "icon_d2", "day 1")]
    assert s.n == 2 and s.wind_err == [-1.0, 1.0] and s.temp_err == [1.0]
    assert s.light_n == 2 and s.light_wrong == 0
    assert ("b", "icon_d2", "day 1") not in scores  # no measurements for b

    dis = mc.disagreements(rows)
    # Gusts differ by exactly 3 m/s, which is not more than the limit.
    assert dis == [{"issued": "2026-10-23T04:00Z", "point": "a", "valid": "2026-10-23T10:00Z", "wind": -3.0}]

    text = mc.report(P, rows, obs, {"a": {"wind": {"station": "03739", "name": "Oberpfaffenhofen", "km": 20.5}}}, issued)
    assert "**icon_d2** (app today)" in text
    assert "Oberpfaffenhofen (20.5 km)" in text


def test_light():
    assert mc.light(3.0, 6.0) == 0
    assert mc.light(6.0, 6.0) == 1
    assert mc.light(3.0, 13.0) == 2
    assert mc.light(None, 3.0) is None


def test_schedule_effect_compares_both_runs_with_the_morning_run():
    morning = datetime(2026, 10, 23, 4, tzinfo=UTC)
    evening = datetime(2026, 10, 22, 16, tzinfo=UTC)
    by_hand = datetime(2026, 10, 23, 12, tzinfo=UTC)
    rows = mc.rows_from_payload(_payload([4.0, 8.0], [2.0, 2.0]), P, "icon_d2", morning)
    rows += mc.rows_from_payload(_payload([6.0, 10.0], [2.0, 2.0]), P, "icon_d2", evening)
    rows += mc.rows_from_payload(_payload([1.0, 1.0], [2.0, 2.0]), P, "icon_d2", by_hand)
    rows += mc.rows_from_payload(_payload([5.0, 9.0], [2.0, 2.0]), P, "best_match", morning)
    t10, t11 = datetime(2026, 10, 23, 10, tzinfo=UTC), datetime(2026, 10, 23, 11, tzinfo=UTC)
    obs = {"a": {"wind": {t10: 4.0, t11: 8.0}}}
    assert [mc.run_slot(x) for x in ("2026-10-23T04:00Z", "2026-10-23T17:00Z", "2026-10-23T12:00Z", "archive")] == [
        "morning", "evening", None, None,
    ]
    effect = mc.schedule_effect(rows, obs)
    twice, once = effect["icon_d2"]
    assert twice.n == 4 and once.n == 2, "the run by hand is left out"
    assert once.wind_err == [0.0, 0.0]
    assert effect["best_match"][1].n == 2
    text = "\n".join(mc._schedule_lines(effect))
    assert "Once a day instead of twice?" in text
    assert "Same order of the models with one run a day: **no**" in text
