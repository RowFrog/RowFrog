"""Schneeregen (rain and snow mixed), worked out from Open-Meteo's rain and snowfall.

Open-Meteo has no weather code for a rain-snow mix: an hour comes as rain
(61-65) or snow (71-77), as the model rounds it. Asked for the hour's rain and
snowfall as well, the backend marks an hour in which both fall with WMO 68
(light) or 69 (moderate or heavy rain and snow); older app versions show those
as rain.

The two values cost Open-Meteo calls (one call per 10 variables and point), so
they are asked only for clubs whose last forecast has rain or snow at air
temperatures around freezing (the cold band), or, without a forecast yet, in the
cold months. Summer costs nothing. Settings on the Pi (owner's pick, 15 Nov 2026,
decision 0042):

- RW_SLEET=off switches it off; the app then shows rain or snow as before.
- RW_SLEET_MIN_C and RW_SLEET_MAX_C set the cold band (default -2 to +4 °C).

The publish run reports the extra calls to the usage counter as their own job
("sleet") and logs a line with the clubs in the cold band.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta
from typing import Iterable, Protocol

# The two values asked for besides the usual ones.
HOURLY = ["rain", "snowfall"]
# Without a forecast to look at, the cold band is possible in these months.
COLD_MONTHS = {10, 11, 12, 1, 2, 3, 4}
# How far ahead the last forecast is looked at.
AHEAD = timedelta(hours=48)
# Rain from this much (mm) together with snowfall from this much (cm) is a mix.
RAIN_MM = 0.05
SNOW_CM = 0.05
# From this much precipitation in the hour the mix is moderate or heavy (69).
HEAVY_MM = 2.5
# Codes a mix may replace: drizzle, rain, snow and their showers; never freezing
# rain (56, 57, 66, 67), thunderstorms or hail.
REPLACEABLE = {51, 53, 55, 61, 63, 65, 71, 73, 75, 77, 80, 81, 82, 85, 86}
LIGHT, HEAVY = 68, 69


class Hour(Protocol):
    time: datetime
    temperature_c: float | None
    precipitation_mm: float | None
    weather_code: int | None


def enabled() -> bool:
    return os.environ.get("RW_SLEET", "on").strip().lower() not in {"off", "0", "no", "false"}


def band() -> tuple[float, float]:
    """The cold band in °C, from the Pi's settings."""
    return float(os.environ.get("RW_SLEET_MIN_C", "-2")), float(os.environ.get("RW_SLEET_MAX_C", "4"))


def _wet(h: Hour) -> bool:
    code = h.weather_code
    return (h.precipitation_mm or 0) >= 0.1 or (code is not None and 51 <= code <= 86)


def in_cold_band(hours: Iterable[Hour] | None, now: datetime) -> bool:
    """Whether a club's next forecast should ask for rain and snowfall: its last
    forecast has a wet hour in the cold band within the next 48 hours, or there is
    no forecast yet and it is a cold month."""
    if not enabled():
        return False
    hours = list(hours or [])
    if not hours:
        return now.month in COLD_MONTHS
    low, high = band()
    return any(
        now - timedelta(hours=1) <= h.time <= now + AHEAD
        and h.temperature_c is not None
        and low <= h.temperature_c <= high
        and _wet(h)
        for h in hours
    )


def mixed_code(code: int | None, precipitation_mm: float | None, rain_mm: float | None, snowfall_cm: float | None) -> int | None:
    """The hour's code, 68 or 69 when rain and snow both fall in it."""
    if code not in REPLACEABLE or rain_mm is None or snowfall_cm is None:
        return code
    if rain_mm < RAIN_MM or snowfall_cm < SNOW_CM:
        return code
    return HEAVY if (precipitation_mm or 0) >= HEAVY_MM else LIGHT
