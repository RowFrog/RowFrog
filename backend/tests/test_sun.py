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
    assert dawn.assessment.reasons == [("twilight", Light.AMBER)]
    assert day.assessment.light == Light.GREEN and day.sun_up is True
    assert dusk.assessment.reasons == [("twilight", Light.AMBER)]
    assert evening.assessment.light == Light.RED
