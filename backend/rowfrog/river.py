"""The river at a river club: water level and current from the nearest gauge,
for the app's Current tile (which takes the ice tile's place on rivers).

data/river-gauges.json (scripts/river_gauge_survey.py) names each river
club's PEGELONLINE gauge with its characteristic values: MW (mean water),
MHW (mean high water) and HSW (the level at which shipping stops), in cm at
the gauge, and MQ (mean discharge) in m³/s. From the gauge's last two days:

  level  normal, raised (more than half way from MW to MHW), high (at MHW or
         above) or shipping stopped (at HSW or above: even motor ships stay in);
  speed  measured where the gauge has a flow speed series (VA), else estimated
         mid-river as discharge / (width x depth): the width from the section
         outline, the depth a typical one for the river at mean water plus the
         gauge's difference from MW. Near the bank the water is slower.

The light (owner's choices, proposal page "River sections", rounds 1 and 2):
shipping stopped is red, high water amber, and the current amber from
CURRENT_AMBER_MS and red from CURRENT_RED_MS (app setting "Current" in My
limits). Gauges report the present, so these count for the next
GAUGE_HOURS only. Data: WSV PEGELONLINE, DL-DE Zero 2.0.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from functools import lru_cache

from . import locations
from .score import Light

PATH = locations.DATA_DIR / "river-gauges.json"
CURRENT_AMBER_MS = 1.5
CURRENT_RED_MS = 2.5
GAUGE_HOURS = 24
# A level this old no longer counts.
MAX_AGE = timedelta(hours=6)
# Typical depth at mean water in the rowing stretches (behind weirs on the
# Main, Neckar, Mosel and Saar), in m; others DEFAULT_DEPTH_M.
DEPTH_M = {"Rhein": 4.0, "Donau": 3.5, "Main": 3.0, "Neckar": 3.0, "Mosel": 3.0, "Saar": 3.0, "Elbe": 2.5, "Weser": 2.5, "Oder": 2.5}
DEFAULT_DEPTH_M = 2.5
MIN_DEPTH_M = 0.5
# Level change over the last RISING_HOURS that counts as rising or falling, in cm.
RISING_HOURS = 6
RISING_CM = 5


@dataclass(frozen=True)
class Gauge:
    id: str
    name: str
    water: str
    river_km: float | None
    lat: float
    lon: float
    distance_km: float
    series: tuple[str, ...]
    values: dict = field(default_factory=dict, hash=False, compare=False)

    def value(self, series: str, name: str) -> float | None:
        v = (self.values.get(series) or {}).get(name)
        return float(v) if v is not None else None

    @property
    def hsw_cm(self) -> float | None:
        """The level at which shipping stops; the Rhine has HSW I and II, the first counts."""
        found = [float(v) for k, v in (self.values.get("W") or {}).items() if k.startswith("HSW") and v is not None]
        return min(found) if found else None


@lru_cache(maxsize=1)
def _load() -> dict[str, Gauge]:
    if not PATH.exists():
        return {}
    raw = json.loads(PATH.read_text(encoding="utf-8"))
    return {
        club_id: Gauge(g["id"], g["name"], g.get("water", ""), g.get("riverKm"), g["lat"], g["lon"], g.get("distanceKm", 0.0),
                       tuple(g.get("series", ())), g.get("values", {}))
        for club_id, g in raw.get("clubs", {}).items()
    }


def gauge_for(club_id: str) -> Gauge | None:
    return _load().get(club_id)


@dataclass(frozen=True)
class Reading:
    time: datetime
    value: float


@dataclass(frozen=True)
class RiverNow:
    gauge: Gauge
    time: datetime
    level_cm: float | None
    trend: str  # "rising", "falling", "steady" or "" when unknown
    state: str  # "normal", "raised", "high", "shipping_stopped" or "" without the values to tell
    discharge_m3s: float | None
    speed_ms: float | None
    speed_measured: bool
    history: list[Reading]  # hourly levels of the last two days, oldest first

    @property
    def light(self) -> tuple[str, Light] | None:
        """The worst of level and current, as a reason for the verdict."""
        found = []
        if self.state == "shipping_stopped":
            found.append(("shipping_stopped", Light.RED))
        elif self.state == "high":
            found.append(("high_water", Light.AMBER))
        if self.speed_ms is not None:
            if self.speed_ms > CURRENT_RED_MS:
                found.append(("current", Light.RED))
            elif self.speed_ms >= CURRENT_AMBER_MS:
                found.append(("current", Light.AMBER))
        return max(found, key=lambda r: r[1], default=None)


def level_state(level_cm: float, gauge: Gauge) -> str:
    hsw, mw, mhw = gauge.hsw_cm, gauge.value("W", "MW"), gauge.value("W", "MHW")
    if hsw is not None and level_cm >= hsw:
        return "shipping_stopped"
    if mhw is not None and level_cm >= mhw:
        return "high"
    if mw is not None and mhw is not None and level_cm > mw + (mhw - mw) / 2:
        return "raised"
    if mw is not None:
        return "normal"
    return ""


def trend(history: list[Reading]) -> str:
    if len(history) < 2:
        return ""
    last = history[-1]
    before = [r for r in history if r.time <= last.time - timedelta(hours=RISING_HOURS)]
    if not before:
        return ""
    change = last.value - before[-1].value
    return "rising" if change >= RISING_CM else "falling" if change <= -RISING_CM else "steady"


def estimate_speed(discharge: float, width_m: float, level_cm: float | None, gauge: Gauge, river: str) -> float | None:
    """Mid-river speed from the discharge, in m/s."""
    if width_m <= 0:
        return None
    depth = DEPTH_M.get(river, DEFAULT_DEPTH_M)
    mw = gauge.value("W", "MW")
    if level_cm is not None and mw is not None:
        depth += (level_cm - mw) / 100
    return round(discharge / (width_m * max(depth, MIN_DEPTH_M)), 2)


def hourly(readings: list[Reading]) -> list[Reading]:
    """The last reading of each hour, oldest first."""
    by_hour = {}
    for r in sorted(readings, key=lambda r: r.time):
        by_hour[r.time.replace(minute=0, second=0, microsecond=0)] = r
    return [by_hour[k] for k in sorted(by_hour)]


def now_at(gauge: Gauge, levels: list[Reading], discharge: list[Reading], speeds: list[Reading], width_m: float | None,
           river: str, now: datetime) -> RiverNow | None:
    """The river now, from the gauge's readings (any order)."""
    levels = hourly(levels)
    if not levels or now - levels[-1].time > MAX_AGE:
        return None
    level = levels[-1].value
    q = hourly(discharge)[-1].value if discharge else None
    if speeds:
        speed, measured = hourly(speeds)[-1].value, True
    elif q is not None and width_m:
        speed, measured = estimate_speed(q, width_m, level, gauge, river), False
    else:
        speed, measured = None, False
    return RiverNow(gauge, levels[-1].time, level, trend(levels), level_state(level, gauge), q, speed, measured,
                    [r for r in levels if r.time >= now - timedelta(hours=48)])


def to_json(river_now: RiverNow | None, gauge: Gauge) -> dict:
    """The forecast's "river" block."""
    g = gauge
    out = {
        "gauge": {"name": g.name, "water": g.water, "riverKm": g.river_km, "lat": g.lat, "lon": g.lon, "distanceKm": g.distance_km,
                  "meanCm": g.value("W", "MW"), "meanHighCm": g.value("W", "MHW"), "shippingStopsCm": g.hsw_cm,
                  "meanDischarge": g.value("Q", "MQ")},
        "limits": {"currentAmberMs": CURRENT_AMBER_MS, "currentRedMs": CURRENT_RED_MS},
        "attribution": "WSV PEGELONLINE, DL-DE Zero 2.0",
    }
    if river_now is None:
        out["now"] = None
        return out
    r = river_now
    light = r.light
    out["now"] = {
        "time": r.time.isoformat(),
        "levelCm": r.level_cm,
        "trend": r.trend,
        "state": r.state,
        "discharge": r.discharge_m3s,
        "speedMs": r.speed_ms,
        "speedMeasured": r.speed_measured,
        "light": (light[1] if light else Light.GREEN).name.lower(),
        "history": [{"time": h.time.isoformat(), "levelCm": h.value} for h in r.history],
    }
    return out
