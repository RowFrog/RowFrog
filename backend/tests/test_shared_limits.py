"""The backend's limits against testdata/limits.json, the table the app's and the website's tests read too."""

import json
from pathlib import Path

from rowfrog import river
from rowfrog.score import Light, Thresholds

TABLE = json.loads((Path(__file__).resolve().parents[2] / "testdata" / "limits.json").read_text(encoding="utf-8"))


def test_small_racing_boats_match_the_shared_table():
    row = next(b for b in TABLE["boats"] if b["type"] == "racing" and b["class"] == "1x")
    t = Thresholds()
    assert (t.wind_amber_ms, t.wind_red_ms, t.gust_amber_ms, t.gust_red_ms, t.wave_amber_m, t.wave_red_m) == (
        row["windAmber"], row["windRed"], row["gustAmber"], row["gustRed"], row["waveAmber"], row["waveRed"],
    )
    assert t.strong_wind_light == Light.RED


def test_cold_water_and_current_match_the_shared_table():
    t = Thresholds()
    cold = TABLE["coldWater"]
    assert (t.water_temp_cold_c, t.cold_wind_margin_ms, t.water_temp_freezing_c) == (
        cold["belowC"], cold["windMarginMs"], cold["freezingC"],
    )
    every = TABLE["everyBoat"]
    assert (river.CURRENT_AMBER_MS, river.CURRENT_RED_MS) == (every["currentAmber"], every["currentRed"])
