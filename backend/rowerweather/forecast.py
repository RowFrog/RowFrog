"""Combine the sources into an hourly rowing forecast for one launch point."""

from __future__ import annotations

from dataclasses import dataclass

from .locations import Club
from .outlines import Rings
from .score import Assessment, HourConditions, Light, Thresholds, assess
from .sources.open_meteo import ForecastHour
from .waves import fetch_m, significant_wave_height

# Placeholder thunderstorm signal from CAPE until DWD warnings are wired in.
CAPE_AMBER_JKG = 500.0
CAPE_RED_JKG = 1000.0
CONVECTIVE_RAIN_MM = 1.0


@dataclass(frozen=True)
class RowingHour:
    weather: ForecastHour
    fetch_m: float | None
    wave_height_m: float | None
    assessment: Assessment


def _thunderstorm(h: ForecastHour) -> Light:
    cape = h.cape_jkg or 0.0
    if cape >= CAPE_RED_JKG and (h.precipitation_mm or 0.0) >= CONVECTIVE_RAIN_MM:
        return Light.RED
    if cape >= CAPE_AMBER_JKG:
        return Light.AMBER
    return Light.GREEN


def rowing_forecast(
    club: Club,
    weather: list[ForecastHour],
    outline: Rings | None,
    water_temp_c: float | None = None,
    thresholds: Thresholds = Thresholds(),
) -> list[RowingHour]:
    hours = []
    for h in weather:
        fetch = wave = None
        if outline is not None and h.wind_from_deg is not None and h.wind_speed_ms is not None:
            fetch = fetch_m(club.launch_point.lon, club.launch_point.lat, h.wind_from_deg, outline)
            wave = significant_wave_height(h.wind_speed_ms, fetch)
        conditions = HourConditions(
            wind_speed_ms=h.wind_speed_ms or 0.0,
            wind_gust_ms=h.wind_gust_ms or 0.0,
            wave_height_m=wave,
            visibility_m=h.visibility_m,
            water_temp_c=water_temp_c,
            thunderstorm=_thunderstorm(h),
            daylight=Light.GREEN if h.is_day in (True, None) else Light.RED,
        )
        hours.append(RowingHour(h, fetch, wave, assess(conditions, thresholds)))
    return hours
