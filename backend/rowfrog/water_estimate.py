"""Water temperature for lakes without a GKD station, from satellite and air.

A satellite reading (sources/lake_temperature_satellite.py) is days old when
the app shows it: an LSWT file averages ten days and arrives three days after
them, and Landsat sees a lake about once every one or two weeks when it is
clear. So the newest reading is carried forward to today with the daily mean
air temperature, the way the ice model cools a lake: the surface water moves
towards the air by dTw/dt = K * (Ta - Tw) / H, with the ice model's K and H
the depth of the water that warms and cools with the surface (LAYER_M, set by
scripts/water_temperature_backtest.py against the GKD stations).

Without a reading in the last MAX_AGE_DAYS the estimate falls back to the ice
model's water temperature, in the cold months only, as before.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from . import ice

# Depth that warms and cools with the surface between a reading and today. The
# backtest of May-Oct 2026 against six GKD stations (Starnberg, Stegen/Ammersee,
# Lindau/Bodensee, Prien-Stock/Chiemsee, Pilsensee, Schliersee) gave a mean
# error of 1.3 °C with 10 m, against 1.4 (5 m), 1.5 (20 m), 1.9 (reading kept
# as it was) and 2.9 °C (monthly typical value).
LAYER_M = 10.0
# A reading older than this is not carried forward any more.
MAX_AGE_DAYS = 30


@dataclass(frozen=True)
class WaterEstimate:
    celsius: float
    # The reading it starts from (sources.lake_temperature_satellite.Reading).
    reading: object


def carry(start: date, celsius: float, temps: list[ice.DayTemperature], until: date, layer_m: float = LAYER_M) -> float:
    """`celsius` on `start`, moved towards the air of each later day up to and including `until`."""
    water = celsius
    for t in temps:
        if start < t.day <= until:
            water += ice.EXCHANGE_M_PER_DAY * (t.mean_c - water) / layer_m
            water = max(0.0, water)
    return water


def estimate(readings: list, temps: list[ice.DayTemperature], today: date) -> WaterEstimate | None:
    """From the newest reading (`readings` oldest first) carried forward to today; None without a recent one."""
    recent = [r for r in readings if 0 <= (today - r.day).days <= MAX_AGE_DAYS]
    if not recent:
        return None
    newest = max(recent, key=lambda r: r.day)
    return WaterEstimate(round(carry(newest.day, newest.celsius, temps, today), 1), newest)
