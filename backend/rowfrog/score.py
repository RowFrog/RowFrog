"""The rowing traffic light: green, amber or red per hour.

The light is the worst of the individual conditions, and every condition that
is not green is reported as a reason, so the app can say why. Thresholds are
for small racing boats (1x, 2x, 2-), from the research in the thread "Boat
sizes and rowing limits" (approved by the owner on 2026-10-23).
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from enum import IntEnum


class Light(IntEnum):
    GREEN = 0
    AMBER = 1
    RED = 2


class LakeWarning(IntEnum):
    """DWD lake warning shown by the shore lights."""

    NONE = 0
    STRONG_WIND = 1  # 40 flashes/min, gusts 46-61 km/h
    STORM = 2  # 90 flashes/min, gusts above 61 km/h


@dataclass(frozen=True)
class Thresholds:
    """Limits for small racing boats (1x, 2x, 2-), the app's starting boat.

    The app works the light out again on the phone for other boats and for
    limits the user changed (ios/RowFrog/Limits.swift); keep the two in step.
    """

    wind_amber_ms: float = 5.5  # Bft 4, the first whitecaps
    wind_red_ms: float = 8.0  # Bft 5
    gust_amber_ms: float = 8.0
    gust_red_ms: float = 10.3  # 20 kn
    wave_amber_m: float = 0.15
    wave_red_m: float = 0.25  # a racing single has only ~7 cm of side
    visibility_amber_m: float = 1000.0
    visibility_red_m: float = 500.0
    # Below this the wind and gust limits drop (the app shows the life-jacket badge from 15 °C).
    water_temp_cold_c: float = 10.0
    water_temp_freezing_c: float = 4.0  # small boats strongly advised to stay ashore
    # Below the cold-water temperature the wind and gust limits drop by this much (DRV advice).
    cold_wind_margin_ms: float = 1.0
    rain_amber_mm: float = 4.0  # heavy rain per hour
    # Light for the lakes' strong-wind warning (40 flashes/min): red for small racing
    # and training boats, amber for the others. The storm warning is red for all.
    strong_wind_light: Light = Light.RED

    def for_water(self, water_temp_c: float | None) -> "Thresholds":
        """These limits, with the cold-water margin on wind and gusts when it applies."""
        if water_temp_c is None or water_temp_c >= self.water_temp_cold_c:
            return self
        m = self.cold_wind_margin_ms
        return replace(
            self,
            wind_amber_ms=self.wind_amber_ms - m,
            wind_red_ms=self.wind_red_ms - m,
            gust_amber_ms=self.gust_amber_ms - m,
            gust_red_ms=self.gust_red_ms - m,
            cold_wind_margin_ms=0.0,
        )


@dataclass(frozen=True)
class HourConditions:
    wind_speed_ms: float
    wind_gust_ms: float
    wave_height_m: float | None = None
    visibility_m: float | None = None
    water_temp_c: float | None = None
    thunderstorm: Light = Light.GREEN
    lake_warning: LakeWarning = LakeWarning.NONE
    # DWD weather warning for the municipality: amber for a minor one, red above.
    weather_warning: Light = Light.GREEN
    ice: Light = Light.GREEN
    daylight: Light = Light.GREEN
    # "daylight" when the hour is dark, "twilight" when the sun rises or sets in it.
    daylight_name: str = "daylight"
    precipitation_mm: float | None = None
    # WMO weather code; 96 and 99 are thunderstorms with hail.
    weather_code: int | None = None
    # Rivers: the gauge's level or current ("shipping_stopped", "high_water", "current"), see river.py.
    river_name: str = "current"
    river: Light = Light.GREEN


@dataclass(frozen=True)
class Assessment:
    light: Light
    reasons: list[tuple[str, Light]] = field(default_factory=list)


HAIL_CODES = (96, 99)


def _rising(value: float, amber: float, red: float) -> Light:
    if value > red:
        return Light.RED
    if value >= amber:
        return Light.AMBER
    return Light.GREEN


def assess(c: HourConditions, t: Thresholds = Thresholds()) -> Assessment:
    t = t.for_water(c.water_temp_c)
    lake = {
        LakeWarning.NONE: ("lake_warning", Light.GREEN),
        LakeWarning.STRONG_WIND: ("lake_strong_wind", t.strong_wind_light),
        LakeWarning.STORM: ("lake_warning", Light.RED),
    }[c.lake_warning]
    checks: list[tuple[str, Light]] = [
        lake,
        ("weather_warning", c.weather_warning),
        ("wind", _rising(c.wind_speed_ms, t.wind_amber_ms, t.wind_red_ms)),
        ("gusts", _rising(c.wind_gust_ms, t.gust_amber_ms, t.gust_red_ms)),
        ("thunderstorm", c.thunderstorm),
        ("ice", c.ice),
        (c.daylight_name, c.daylight),
        (c.river_name, c.river),
    ]
    if c.wave_height_m is not None:
        checks.append(("waves", _rising(c.wave_height_m, t.wave_amber_m, t.wave_red_m)))
    if c.visibility_m is not None:
        if c.visibility_m < t.visibility_red_m:
            checks.append(("fog", Light.RED))
        elif c.visibility_m <= t.visibility_amber_m:
            checks.append(("fog", Light.AMBER))
    if c.weather_code in HAIL_CODES:
        checks.append(("hail", Light.RED))
    elif c.precipitation_mm is not None and c.precipitation_mm >= t.rain_amber_mm:
        checks.append(("heavy_rain", Light.AMBER))
    # Cold water no longer colours the light (owner decision 2026-10-26): the
    # app shows a life-jacket badge below 15 °C instead, and below 10 °C the
    # wind and gust limits above are already lower. Only near-freezing water,
    # a few weeks a year, stays a strong warning for small boats.
    if c.water_temp_c is not None and c.water_temp_c < t.water_temp_freezing_c:
        checks.append(("freezing_water", Light.AMBER))

    reasons = [(name, light) for name, light in checks if light > Light.GREEN]
    worst = max((light for _, light in reasons), default=Light.GREEN)
    return Assessment(light=worst, reasons=sorted(reasons, key=lambda r: -r[1]))
