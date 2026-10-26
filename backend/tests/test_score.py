from rowfrog.score import HourConditions, LakeWarning, Light, Thresholds, assess


def test_calm_morning_is_green():
    a = assess(HourConditions(wind_speed_ms=2, wind_gust_ms=4, wave_height_m=0.05, visibility_m=10_000, water_temp_c=18))
    assert a.light == Light.GREEN
    assert a.reasons == []


def test_worst_condition_wins_and_is_reported():
    a = assess(HourConditions(wind_speed_ms=6, wind_gust_ms=9, wave_height_m=0.35))
    assert a.light == Light.RED
    assert a.reasons[0] == ("waves", Light.RED)
    assert ("wind", Light.AMBER) in a.reasons


def test_storm_warning_overrides_calm_forecast():
    a = assess(HourConditions(wind_speed_ms=1, wind_gust_ms=2, lake_warning=LakeWarning.STORM))
    assert a.light == Light.RED
    assert a.reasons == [("lake_warning", Light.RED)]


def test_fog_thresholds():
    assert assess(HourConditions(0, 0, visibility_m=800)).light == Light.AMBER
    assert assess(HourConditions(0, 0, visibility_m=300)).light == Light.RED


def test_cold_water_does_not_colour_the_light():
    # The app shows a life-jacket badge instead; the light stays about the weather.
    assert assess(HourConditions(0, 0, water_temp_c=12)) == assess(HourConditions(0, 0, water_temp_c=18))
    a = assess(HourConditions(0, 0, water_temp_c=6))
    assert a.light == Light.GREEN
    assert a.reasons == []
    a = assess(HourConditions(0, 0, water_temp_c=3))
    assert a.light == Light.AMBER, "near-freezing water is a strong warning, the rower decides"
    assert a.reasons == [("freezing_water", Light.AMBER)]


def test_cold_water_lowers_the_wind_limits_by_one_metre_per_second():
    assert assess(HourConditions(wind_speed_ms=5.0, wind_gust_ms=5.0, water_temp_c=16)).light == Light.GREEN
    a = assess(HourConditions(wind_speed_ms=5.0, wind_gust_ms=5.0, water_temp_c=8))
    assert ("wind", Light.AMBER) in a.reasons
    assert ("gusts", Light.RED) in assess(HourConditions(wind_speed_ms=1, wind_gust_ms=9.5, water_temp_c=8)).reasons


def test_strong_wind_light_is_red_for_small_boats_and_storm_for_all():
    a = assess(HourConditions(wind_speed_ms=1, wind_gust_ms=2, lake_warning=LakeWarning.STRONG_WIND))
    assert a.reasons == [("lake_strong_wind", Light.RED)]
    big = Thresholds(strong_wind_light=Light.AMBER)
    assert assess(HourConditions(1, 2, lake_warning=LakeWarning.STRONG_WIND), big).light == Light.AMBER
    assert assess(HourConditions(1, 2, lake_warning=LakeWarning.STORM), big).light == Light.RED


def test_heavy_rain_is_amber_and_hail_red():
    assert assess(HourConditions(0, 0, precipitation_mm=1.0)).light == Light.GREEN
    a = assess(HourConditions(0, 0, precipitation_mm=5.0))
    assert a.reasons == [("heavy_rain", Light.AMBER)]
    a = assess(HourConditions(0, 0, precipitation_mm=1.0, weather_code=96))
    assert a.reasons == [("hail", Light.RED)]
