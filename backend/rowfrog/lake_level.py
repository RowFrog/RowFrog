"""Lakes lowered on purpose: the water level from the lake's gauge, for the
app's Water level tile, which takes the ice tile's place while the lake is
lowered (owner's choice A, proposal page "River sections", round 4).

Forggensee is let down every winter, for flood protection and power: from
mid-November to about 6 m below full by February, full again at the end of
May. data/lake-levels.json names each such lake's gauge (GKD Bayern) and its
marks in m above sea level:

  full     the usual summer level, for "x m below full";
  lowered  below loweredBelowM: amber, shallows and a long way to the water;
  drained  below drainedBelowM: red, too little water at the club to row.

A lake's level changes over days, not hours, so the reading counts for the
whole forecast. Data: Gewässerkundlicher Dienst Bayern, CC BY 4.0.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timedelta
from functools import lru_cache

from . import locations
from .score import Light

PATH = locations.DATA_DIR / "lake-levels.json"
ATTRIBUTION = "Gewässerkundlicher Dienst Bayern, CC BY 4.0"
# A level this old no longer counts.
MAX_AGE = timedelta(hours=12)
# Change over the last TREND_HOURS that counts as rising or falling, in m.
TREND_HOURS = 24
TREND_M = 0.05
LIGHT = {"lowered": ("lake_lowered", Light.AMBER), "drained": ("lake_drained", Light.RED)}


@dataclass(frozen=True)
class LevelLake:
    lake_id: str
    station: str
    name: str
    full_m: float
    lowered_below_m: float
    drained_below_m: float


@lru_cache(maxsize=1)
def _load() -> dict[str, LevelLake]:
    if not PATH.exists():
        return {}
    raw = json.loads(PATH.read_text(encoding="utf-8"))
    return {
        lake_id: LevelLake(lake_id, x["station"], x["name"], x["fullM"], x["loweredBelowM"], x["drainedBelowM"])
        for lake_id, x in raw.get("lakes", {}).items()
    }


def for_lake(lake_id: str) -> LevelLake | None:
    return _load().get(lake_id)


@dataclass(frozen=True)
class LevelNow:
    lake: LevelLake
    time: datetime
    level_m: float
    state: str  # "full", "lowered" or "drained"
    trend: str  # "rising", "falling", "steady" or "" when unknown
    history: list[tuple[datetime, float]]  # hourly, oldest first

    @property
    def light(self) -> tuple[str, Light] | None:
        """As a reason for the verdict; None while the lake is full."""
        return LIGHT.get(self.state)


def state(level_m: float, lake: LevelLake) -> str:
    if level_m < lake.drained_below_m:
        return "drained"
    if level_m < lake.lowered_below_m:
        return "lowered"
    return "full"


def hourly(readings: list[tuple[datetime, float]]) -> list[tuple[datetime, float]]:
    """The last reading of each hour, oldest first."""
    by_hour = {}
    for t, v in sorted(readings):
        by_hour[t.replace(minute=0, second=0, microsecond=0)] = (t, v)
    return [by_hour[k] for k in sorted(by_hour)]


def trend(history: list[tuple[datetime, float]]) -> str:
    if len(history) < 2:
        return ""
    last_t, last_v = history[-1]
    before = [v for t, v in history if t <= last_t - timedelta(hours=TREND_HOURS)]
    if not before:
        return ""
    change = last_v - before[-1]
    return "rising" if change >= TREND_M else "falling" if change <= -TREND_M else "steady"


def now_at(lake: LevelLake, readings: list[tuple[datetime, float]], now: datetime) -> LevelNow | None:
    """The lake now, from the gauge's readings (any order); None when the last one is too old."""
    history = hourly(readings)
    if not history or now - history[-1][0] > MAX_AGE:
        return None
    t, level = history[-1]
    return LevelNow(lake, t, level, state(level, lake), trend(history), history)


def to_json(level_now: LevelNow | None, lake: LevelLake) -> dict:
    """The forecast's "waterLevel" block."""
    out = {
        "gauge": lake.name,
        "fullM": lake.full_m,
        "loweredBelowM": lake.lowered_below_m,
        "drainedBelowM": lake.drained_below_m,
        "attribution": ATTRIBUTION,
        "now": None,
    }
    if level_now is not None:
        r = level_now
        light = r.light
        out["now"] = {
            "time": r.time.isoformat(),
            "levelM": r.level_m,
            "belowFullM": round(max(0.0, lake.full_m - r.level_m), 2),
            "state": r.state,
            "trend": r.trend,
            "light": (light[1] if light else Light.GREEN).name.lower(),
            "history": [{"time": t.isoformat(), "levelM": v} for t, v in r.history],
        }
    return out
