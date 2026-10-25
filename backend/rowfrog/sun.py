"""Sunrise and sunset for a launch point.

Uses the sunrise equation (NOAA's simplified solar position), which is
accurate to about a minute at Bavarian latitudes and needs no network call.
Rowing is only advised while the sun is up.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

J2000 = 2451545.0
_J2000_DATE = date(2000, 1, 1)
# Sun's upper limb on the horizon, including atmospheric refraction.
HORIZON_DEG = -0.833


@dataclass(frozen=True)
class SunDay:
    day: date
    sunrise: datetime
    sunset: datetime


def _from_julian(j: float) -> datetime:
    return datetime(2000, 1, 1, 12, tzinfo=timezone.utc) + timedelta(days=j - J2000)


def sun_day(day: date, lat: float, lon: float) -> SunDay | None:
    """Sunrise and sunset in UTC for a date, or None during polar day or night."""
    n = (day - _J2000_DATE).days
    mean_solar = n - lon / 360.0
    m = math.radians((357.5291 + 0.98560028 * mean_solar) % 360)
    centre = 1.9148 * math.sin(m) + 0.0200 * math.sin(2 * m) + 0.0003 * math.sin(3 * m)
    ecliptic_lon = math.radians((math.degrees(m) + centre + 180 + 102.9372) % 360)
    transit = J2000 + mean_solar + 0.0053 * math.sin(m) - 0.0069 * math.sin(2 * ecliptic_lon)
    declination = math.asin(math.sin(ecliptic_lon) * math.sin(math.radians(23.4397)))
    phi = math.radians(lat)
    cos_hour_angle = (math.sin(math.radians(HORIZON_DEG)) - math.sin(phi) * math.sin(declination)) / (
        math.cos(phi) * math.cos(declination)
    )
    if not -1.0 <= cos_hour_angle <= 1.0:
        return None
    half_day = math.degrees(math.acos(cos_hour_angle)) / 360.0
    return SunDay(day, _from_julian(transit - half_day), _from_julian(transit + half_day))


def sun_days(start: datetime, end: datetime, lat: float, lon: float) -> list[SunDay]:
    """Every day from the one before `start` to the one after `end` (UTC dates)."""
    days = []
    d = start.astimezone(timezone.utc).date() - timedelta(days=1)
    last = end.astimezone(timezone.utc).date() + timedelta(days=1)
    while d <= last:
        s = sun_day(d, lat, lon)
        if s is not None:
            days.append(s)
        d += timedelta(days=1)
    return days
