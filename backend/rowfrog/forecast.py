"""Combine the sources into an hourly rowing forecast for one launch point."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from .locations import Club
from .outlines import Rings
from .score import Assessment, HourConditions, LakeWarning, Light, Thresholds, assess
from .sources.dwd_warnings import Warning
from .sources.open_meteo import ForecastHour
from .sun import SunDay, sun_days
from .waves import fetch_m, significant_wave_height

# Placeholder thunderstorm signal from CAPE until DWD warnings are wired in.
CAPE_AMBER_JKG = 500.0
CAPE_RED_JKG = 1000.0
CONVECTIVE_RAIN_MM = 1.0
# The ice estimate is per German calendar day.
LOCAL = ZoneInfo("Europe/Berlin")


@dataclass(frozen=True)
class RowingHour:
    weather: ForecastHour
    fetch_m: float | None
    wave_height_m: float | None
    assessment: Assessment
    sun_up: bool | None = None
    # What the weather warning behind a "weather_warning" reason is about (weather_warning_topic).
    warning_topic: str | None = None


def _thunderstorm(h: ForecastHour) -> Light:
    cape = h.cape_jkg or 0.0
    if cape >= CAPE_RED_JKG and (h.precipitation_mm or 0.0) >= CONVECTIVE_RAIN_MM:
        return Light.RED
    if cape >= CAPE_AMBER_JKG:
        return Light.AMBER
    return Light.GREEN


def _daylight(h: ForecastHour, days: list[SunDay]) -> tuple[str, Light, bool | None]:
    """Rowing is advised only while the sun is up.

    Each forecast row covers the hour from its time. A row with the sun up for
    the whole hour is green, a row with sunrise or sunset inside it is amber
    ("twilight") and a row entirely in the dark is red. Also returns whether
    the sun is up at the middle of the hour. Without sun times the model's
    is_day flag decides.
    """
    if not days:
        return "daylight", (Light.GREEN if h.is_day in (True, None) else Light.RED), h.is_day
    start, end = h.time, h.time + timedelta(hours=1)
    middle = start + timedelta(minutes=30)
    sun_up = any(d.sunrise <= middle < d.sunset for d in days)
    if any(d.sunrise <= start and end <= d.sunset for d in days):
        return "daylight", Light.GREEN, sun_up
    if any(start < t < end for d in days for t in (d.sunrise, d.sunset)):
        return "twilight", Light.AMBER, sun_up
    return "daylight", Light.RED, sun_up


def _lake_warning(warnings: list[Warning], start, end) -> LakeWarning:
    """Storm (red) for storm, hurricane or severe lake warnings; strong wind (amber) otherwise."""
    worst = LakeWarning.NONE
    for w in warnings:
        if w.kind != "lake" or not w.active_during(start, end):
            continue
        storm = w.level >= 2 or any(word in w.event.upper() for word in ("STURM", "ORKAN"))
        worst = max(worst, LakeWarning.STORM if storm else LakeWarning.STRONG_WIND)
    return worst


# What an official weather warning is about, from its German event word (DWD,
# GeoSphere and MeteoAlarm all name events in German, see sources/). Frost,
# black ice, thaw, heat and cold say nothing about the water, so they stay in
# the warnings card but leave the rowing light alone. Checked first, so that
# e.g. "SCHNEEGLÄTTE" counts as black ice, not snow.
INFO_ONLY_WORDS = ("FROST", "GLÄTTE", "GLATT", "TAUWETTER", "HITZE", "KÄLTE", "UV")
# (topic, words), most serious first: it picks the topic when two warnings are equally bad.
WARNING_TOPICS = (
    ("thunderstorm", ("GEWITTER", "HAGEL")),
    ("wind", ("ORKAN", "STURM", "BÖEN", "WIND")),
    ("rain", ("REGEN", "HOCHWASSER")),
    ("snow", ("SCHNEE",)),
    ("fog", ("NEBEL",)),
)


def warning_topic(event: str) -> str | None:
    """What a weather warning is about for rowing, or None for one that leaves the light alone.

    An event the lists don't know counts ("other"): better a light too strict than a warning missed.
    """
    word = event.upper()
    if any(w in word for w in INFO_ONLY_WORDS):
        return None
    return next((topic for topic, words in WARNING_TOPICS if any(w in word for w in words)), "other")


def _counting(warnings: list[Warning], start, end) -> list[tuple[Light, int, str]]:
    """(light, topic rank, topic) for each weather warning in the hour that changes the advice."""
    ranks = [t for t, _ in WARNING_TOPICS] + ["other"]
    out = []
    for w in warnings:
        if w.kind != "local" or not w.active_during(start, end):
            continue
        topic = warning_topic(w.event)
        if topic is None:
            continue
        red = w.level >= 1 or topic == "thunderstorm"
        out.append((Light.RED if red else Light.AMBER, ranks.index(topic), topic))
    return out


def _weather_warning(warnings: list[Warning], start, end) -> Light:
    """A minor warning (yellow) is amber; moderate (orange) and above, or any thunderstorm, is red.

    Only warnings about the water count (warning_topic); frost or heat leave the light alone.
    """
    return max((light for light, _, _ in _counting(warnings, start, end)), default=Light.GREEN)


def weather_warning_topic(warnings: list[Warning], start, end) -> str | None:
    """What the worst counting weather warning in the hour is about, so the app can name it."""
    found = _counting(warnings, start, end)
    if not found:
        return None
    return min(found, key=lambda f: (-int(f[0]), f[1]))[2]


def rowing_forecast(
    club: Club,
    weather: list[ForecastHour],
    outline: Rings | None,
    water_temp_c: float | None = None,
    warnings: list[Warning] = (),
    thresholds: Thresholds = Thresholds(),
    ice_by_day: dict[date, Light] | None = None,
    water_by_day: dict[date, float] | None = None,
    river: tuple[str, Light] | None = None,
    river_until: datetime | None = None,
) -> list[RowingHour]:
    """`river` is the gauge's reason and light (river.py), for the hours before `river_until`."""
    hours = []
    p = club.launch_point
    days = sun_days(weather[0].time, weather[-1].time, p.lat, p.lon) if weather else []
    for h in weather:
        daylight_name, daylight, sun_up = _daylight(h, days)
        fetch = wave = None
        if outline is not None and h.wind_from_deg is not None and h.wind_speed_ms is not None:
            fetch = fetch_m(club.launch_point.lon, club.launch_point.lat, h.wind_from_deg, outline)
            wave = significant_wave_height(h.wind_speed_ms, fetch)
        conditions = HourConditions(
            wind_speed_ms=h.wind_speed_ms or 0.0,
            wind_gust_ms=h.wind_gust_ms or 0.0,
            wave_height_m=wave,
            visibility_m=h.visibility_m,
            # The water forecast for the hour's day where there is one, else today's water.
            water_temp_c=(water_by_day or {}).get(h.time.astimezone(LOCAL).date(), water_temp_c),
            thunderstorm=_thunderstorm(h),
            daylight=daylight,
            daylight_name=daylight_name,
            precipitation_mm=h.precipitation_mm,
            weather_code=h.weather_code,
            lake_warning=_lake_warning(list(warnings), h.time, h.time + timedelta(hours=1)),
            weather_warning=_weather_warning(list(warnings), h.time, h.time + timedelta(hours=1)),
            ice=(ice_by_day or {}).get(h.time.astimezone(LOCAL).date(), Light.GREEN),
            **({"river_name": river[0], "river": river[1]} if river and river_until and h.time < river_until else {}),
        )
        topic = weather_warning_topic(list(warnings), h.time, h.time + timedelta(hours=1))
        hours.append(RowingHour(h, fetch, wave, assess(conditions, thresholds), sun_up, topic))
    return hours
