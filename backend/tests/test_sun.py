from datetime import date, datetime, timezone

from rowfrog import locations
from rowfrog.forecast import rowing_forecast
from rowfrog.score import Light
from rowfrog.sources.open_meteo import ForecastHour
from rowfrog.sun import sun_day

STARNBERG = (47.9967, 11.3475)


def minutes(t: datetime) -> int:
    return t.hour * 60 + t.minute


def test_starnberg_autumn_sun_times():
    # timeanddate.com for Starnberg on 18 Oct 2026: sunrise 07:35, sunset 18:21 CEST.
    s = sun_day(date(2026, 10, 18), *STARNBERG)
    assert abs(minutes(s.sunrise) - (5 * 60 + 35)) <= 4
    assert abs(minutes(s.sunset) - (16 * 60 + 21)) <= 4


def test_starnberg_midsummer_sun_times():
    # Around 05:13 and 21:17 CEST at the summer solstice.
    s = sun_day(date(2026, 6, 21), *STARNBERG)
    assert abs(minutes(s.sunrise) - (3 * 60 + 13)) <= 5
    assert abs(minutes(s.sunset) - (19 * 60 + 17)) <= 5


def test_polar_night_has_no_sunrise():
    assert sun_day(date(2026, 12, 21), 80.0, 15.0) is None


def _hour(h: int, m: int = 0) -> ForecastHour:
    return ForecastHour(
        time=datetime(2026, 10, 18, h, m, tzinfo=timezone.utc),
        temperature_c=10,
        wind_speed_ms=1,
        wind_gust_ms=2,
        wind_from_deg=0,
        cloud_cover_pct=0,
        cloud_cover_low_pct=0,
        visibility_m=20_000,
        precipitation_mm=0,
        cape_jkg=0,
        is_day=True,  # deliberately wrong at night: the sun times decide
    )


def test_rowing_only_advised_while_the_sun_is_up():
    club = locations.Club(
        id="t",
        name="T",
        short_name="T",
        lake_id="none",
        address="",
        website=None,
        launch_point=locations.Point(*STARNBERG),
        launch_point_verified=False,
    )
    # Sunrise is about 05:35 UTC and sunset about 16:21 UTC.
    night, dawn, day, dusk, evening = rowing_forecast(club, [_hour(4), _hour(5), _hour(12), _hour(16), _hour(18)], None)
    assert night.assessment.light == Light.RED and ("daylight", Light.RED) in night.assessment.reasons
    assert night.sun_up is False
    # The sunrise and sunset hours are partly dark, so red (the app splits their dot).
    assert dawn.assessment.reasons == [("daylight", Light.RED)]
    assert day.assessment.light == Light.GREEN and day.sun_up is True
    assert dusk.assessment.reasons == [("daylight", Light.RED)]
    assert evening.assessment.light == Light.RED


def _days(sunrise: tuple[int, int], sunset: tuple[int, int]) -> list:
    from rowfrog.sun import SunDay

    on = lambda hm: datetime(2026, 10, 18, *hm, tzinfo=timezone.utc)  # noqa: E731
    return [SunDay(day=on(sunrise).date(), sunrise=on(sunrise), sunset=on(sunset))]


def test_the_hour_before_sunset_turns_amber_to_the_minute():
    from rowfrog.forecast import _daylight

    days = _days((6, 0), (16, 49))
    light = lambda hour: _daylight(_hour(hour), days)[:2]  # noqa: E731
    assert light(14) == ("daylight", Light.GREEN)
    assert light(15) == ("twilight", Light.AMBER)  # amber from 15:49
    assert light(16) == ("daylight", Light.RED)  # dark from 16:49
    assert light(17) == ("daylight", Light.RED)


def test_sunset_on_the_hour_leaves_one_whole_amber_hour():
    from rowfrog.forecast import _daylight

    days = _days((6, 0), (17, 0))
    assert _daylight(_hour(15), days)[:2] == ("daylight", Light.GREEN)
    assert _daylight(_hour(16), days)[:2] == ("twilight", Light.AMBER)
    assert _daylight(_hour(17), days)[:2] == ("daylight", Light.RED)


def test_daylight_light_at_a_moment():
    from rowfrog.forecast import daylight_light_at

    days = _days((6, 0), (17, 1))
    at = lambda h, m: daylight_light_at(datetime(2026, 10, 18, h, m, tzinfo=timezone.utc), days)  # noqa: E731
    assert at(5, 59) == Light.RED and at(6, 0) == Light.GREEN
    assert at(16, 0) == Light.GREEN and at(16, 1) == Light.AMBER
    assert at(17, 0) == Light.AMBER and at(17, 1) == Light.RED
