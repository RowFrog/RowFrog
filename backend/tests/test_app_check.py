import json
from datetime import datetime, timezone

import pytest

from rowfrog import app_check as ac
from rowfrog import model_check as mc

UTC = timezone.utc


def _club_body():
    return {
        "generatedAt": "2026-11-12T04:31:07+00:00",
        "waterForecast": [{"date": "2026-11-12", "celsius": 9.5}, {"date": "2026-11-13", "celsius": 9.2}],
        "hours": [
            # Before the file was made: left out.
            {"time": "2026-11-12T04:00:00+00:00", "windSpeedMs": 1.0, "windGustMs": 2.0, "windFromDeg": 90, "temperatureC": 3.0, "precipitationMm": 0},
            {"time": "2026-11-12T05:00:00+00:00", "windSpeedMs": 2.5, "windGustMs": 5.0, "windFromDeg": 100, "temperatureC": 3.5, "precipitationMm": 0.1},
            # 23:00 UTC is already the 13th in Germany.
            {"time": "2026-11-12T23:00:00+00:00", "windSpeedMs": 4.0, "windGustMs": 8.0, "windFromDeg": 250, "temperatureC": 2.0, "precipitationMm": 0},
        ],
    }


def test_club_rows_take_the_files_hours_and_the_water_forecast_by_german_date():
    rows = ac.club_rows(_club_body(), "mrc-1880")
    assert [r["valid"] for r in rows] == ["2026-11-12T05:00Z", "2026-11-12T23:00Z"]
    assert rows[0]["issued"] == "2026-11-12T04:31Z" and rows[0]["lead_h"] == 0 and rows[1]["lead_h"] == 18
    assert rows[0]["model"] == "app" and rows[0]["wind"] == 2.5 and rows[0]["gust"] == 5.0
    assert rows[0]["water"] == 9.5 and rows[1]["water"] == 9.2


def _lake_body():
    return {
        "generatedAt": "2026-11-12T04:30:00Z",
        "waterC": 10.1,
        "points": [{"lat": 47.95, "lon": 11.10}, {"lat": 48.00, "lon": 11.13}],
        "hours": [
            {"time": "2026-11-12T05:00:00+00:00", "wind": [
                {"speedMs": 1.0, "gustMs": 2.0, "fromDeg": 10, "rainMm": 0},
                {"speedMs": 6.0, "gustMs": 9.0, "fromDeg": 240, "rainMm": 0.4},
            ]},
        ],
    }


def test_lake_rows_use_the_nearest_weather_point():
    rows = ac.lake_rows(_lake_body(), "ammersee-buoy", 48.0, 11.125)
    assert len(rows) == 1
    r = rows[0]
    assert (r["wind"], r["gust"], r["dir"], r["water"], r["temp"]) == (6.0, 9.0, 240, 10.1, "")


def test_app_rows_read_the_publisher_folder_and_survive_a_missing_file(tmp_path):
    (tmp_path / "clubs" / "mrc-1880").mkdir(parents=True)
    (tmp_path / "clubs" / "mrc-1880" / "forecast").write_text(json.dumps(_club_body()))
    points = [
        mc.Point("mrc-1880", "MRC", 47.99, 11.34, 1, club="mrc-1880"),
        mc.Point("ammersee-buoy", "Buoy", 48.0, 11.125, 1, lake="ammersee"),
        mc.Point("tegernsee", "Tegernsee", 47.7, 11.7, 1),
    ]
    rows, log = ac.app_rows(tmp_path, points)
    assert {r["point"] for r in rows} == {"mrc-1880"}
    assert any(l.startswith("app ammersee-buoy: FileNotFoundError") for l in log)


GKD_PAGE = """<table><tr><th>Date</th><th>Wind speed [m/s]</th></tr>
<tr><td>12.11.2026 06:00</td><td>4,2</td></tr>
<tr><td>12.11.2026 05:45</td><td>3,9</td></tr>
<tr><td>12.11.2026 05:00</td><td>2,0</td></tr></table>"""


def test_gkd_table_is_german_time_and_the_log_only_grows(tmp_path):
    values = ac.parse_table(GKD_PAGE)
    assert values[datetime(2026, 11, 12, 5, tzinfo=UTC)] == 4.2  # 06:00 CET
    path = ac.log_path(tmp_path, "wind", "ammerseeboje-16601050")
    assert ac.merge_log(path, values) == 3
    assert ac.merge_log(path, values) == 0
    later = {datetime(2026, 11, 12, 6, tzinfo=UTC): 5.0}
    assert ac.merge_log(path, later) == 1
    assert len(ac.read_log(path)) == 4


def test_buoy_wind_is_lifted_to_10_m_and_only_full_hours_count(tmp_path):
    assert ac.BUOY_TO_10M == pytest.approx(1.19, abs=0.01)
    ac.merge_log(ac.log_path(tmp_path, "wind", "boje"), ac.parse_table(GKD_PAGE))
    ac.merge_log(ac.log_path(tmp_path, "water", "boje"), ac.parse_table(GKD_PAGE))
    p = mc.Point("buoy", "Buoy", 48.0, 11.125, 1, gkd={"wind": "boje", "water": "boje"})
    obs = ac.gkd_observations(tmp_path, [p])
    t = datetime(2026, 11, 12, 5, tzinfo=UTC)
    assert set(obs["buoy"]["wind"]) == {t, datetime(2026, 11, 12, 4, tzinfo=UTC)}
    assert obs["buoy"]["wind"][t] == pytest.approx(4.2 * ac.BUOY_TO_10M, abs=0.01)
    assert obs["buoy"]["water"][t] == 4.2
    assert p.on_lake


def test_report_scores_the_app_and_keeps_lake_points_out_of_all_points():
    t = datetime(2026, 11, 12, 5, tzinfo=UTC)
    points = [
        mc.Point("mrc-1880", "MRC", 47.99, 11.34, 1, club="mrc-1880", gkd={"water": "starnberg"}),
        mc.Point("buoy", "Buoy", 48.0, 11.125, 1, lake="ammersee", gkd={"wind": "boje"}),
    ]

    def row(model, point, wind, gust=None, water=None):
        return {"issued": "2026-11-12T04:00Z", "model": model, "point": point, "valid": "2026-11-12T05:00Z",
                "lead_h": "1", "wind": wind, "gust": gust or "", "dir": "", "temp": "", "precip": "", "water": water or ""}

    rows = [
        row("app", "mrc-1880", 3.0, 6.0, 9.0), row("icon_d2", "mrc-1880", 4.0, 7.0),
        row("app", "buoy", 5.0), row("icon_d2", "buoy", 2.0),
    ]
    obs = {"mrc-1880": {"wind": {t: 2.0}, "gust": {t: 5.0}, "water": {t: 9.5}}, "buoy": {"wind": {t: 6.0}}}
    land = {"buoy": {"wind": {t: 3.0}}}
    scores = mc.score(rows, obs, apart={"buoy"})
    assert scores[("mrc-1880", "app", "day 1")].water_err == [-0.5]
    assert ("all", "app", "day 1") not in scores  # the app's rows stay out of the model ranking
    assert scores[("all", "icon_d2", "day 1")].wind_err == [2.0]  # the buoy is not in "all"

    text = mc.report(points, rows, obs, {}, t, land)
    assert "## App vs measured" in text and "| MRC | day 1 | 1 | 1.0 | 2.0 | +1.0 |" in text
    assert "## On the lake vs on land" in text and "| Buoy | 1 | 6.0 | 3.0 | 2.00 | 1 | 2.00 |" in text
    assert "**app** (what Row Frog showed)" in text


def test_points_file_names_known_clubs_and_lakes():
    from rowfrog import locations

    points = mc.load_points(mc_points_path(), 1)
    locs = locations.load()
    for p in points:
        if p.club:
            assert p.club in locs.clubs, p.club
        if p.lake:
            assert p.lake in locs.lakes, p.lake


def mc_points_path():
    from pathlib import Path

    return Path(__file__).resolve().parents[2] / "data" / "model-check" / "points.json"
