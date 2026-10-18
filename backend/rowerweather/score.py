"""The rowing traffic light: green, amber or red per hour.

The light is the worst of the individual conditions, and every condition that
is not green is reported as a reason, so the app can say why. Thresholds are
the proposed defaults for small boats (1x, 2x) from the MVP plan and are meant
to be tuned with rowers.
"""

from __future__ import annotations

from dataclasses import dataclass, field
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
    wind_amber_ms: float = 5.5  # Bft 4
    wind_red_ms: float = 8.0  # Bft 5
    gust_amber_ms: float = 8.0
    gust_red_ms: float = 12.8  # 46 km/h, the DWD strong-wind threshold
    wave_amber_m: float = 0.15
    wave_red_m: float = 0.30
    visibility_amber_m: float = 1000.0
    visibility_red_m: float = 500.0
    water_temp_amber_c: float = 15.0
    water_temp_cold_c: float = 10.0


@dataclass(frozen=True)
class HourConditions:
    wind_speed_ms: float
    wind_gust_ms: float
    wave_height_m: float | None = None
    visibility_m: float | None = None
    water_temp_c: float | None = None
    thunderstorm: Light = Light.GREEN
    lake_warning: LakeWarning = LakeWarning.NONE
    ice: Light = Light.GREEN
    daylight: Light = Light.GREEN


@dataclass(frozen=True)
class Assessment:
    light: Light
    reasons: list[tuple[str, Light]] = field(default_factory=list)


def _rising(value: float, amber: float, red: float) -> Light:
    if value > red:
        return Light.RED
    if value >= amber:
        return Light.AMBER
    return Light.GREEN


def assess(c: HourConditions, t: Thresholds = Thresholds()) -> Assessment:
    checks: list[tuple[str, Light]] = [
        ("lake_warning", Light(int(c.lake_warning))),
        ("wind", _rising(c.wind_speed_ms, t.wind_amber_ms, t.wind_red_ms)),
        ("gusts", _rising(c.wind_gust_ms, t.gust_amber_ms, t.gust_red_ms)),
        ("thunderstorm", c.thunderstorm),
        ("ice", c.ice),
        ("daylight", c.daylight),
    ]
    if c.wave_height_m is not None:
        checks.append(("waves", _rising(c.wave_height_m, t.wave_amber_m, t.wave_red_m)))
    if c.visibility_m is not None:
        if c.visibility_m < t.visibility_red_m:
            checks.append(("fog", Light.RED))
        elif c.visibility_m <= t.visibility_amber_m:
            checks.append(("fog", Light.AMBER))
    if c.water_temp_c is not None and c.water_temp_c < t.water_temp_amber_c:
        # Cold water calls for extra care but never closes the lake on its own.
        name = "cold_water" if c.water_temp_c < t.water_temp_cold_c else "cool_water"
        checks.append((name, Light.AMBER))

    reasons = [(name, light) for name, light in checks if light > Light.GREEN]
    worst = max((light for _, light in reasons), default=Light.GREEN)
    return Assessment(light=worst, reasons=sorted(reasons, key=lambda r: -r[1]))
