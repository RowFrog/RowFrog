"""Ice cover estimate per lake, from frost and water temperature.

No open source reports day by day whether a Bavarian lake is frozen, so the
backend estimates it, like it estimates waves. The estimate is a small
degree-day model, run over the last ~90 days of daily mean air temperature
and the next week's forecast:

1. Water cools towards the air. The lake's surface water follows the daily
   mean air temperature with a lag set by how much water has to cool:
   dTw/dt = K * (Ta - Tw) / H, with K = 0.41 m/day (a heat exchange of about
   20 W/m²K) and H the mixed depth. Above 4 °C the whole lake mixes, so H is
   the mean depth; a deep lake like Starnberger See (53 m) takes months to
   get there. Below 4 °C the cold water stays on top, so only a surface
   layer (a fifth of the mean depth, 2 to 10 m, as wind still stirs a big
   lake deeper) has to cool further before ice forms.
2. Ice grows with frost (Stefan's law): h² grows by A² per degree-day below
   0 °C, with A = 2.0 cm per sqrt(°C·day), a typical value for lake ice with
   some snow on it.
3. Ice melts by MELT_CM_PER_DEGREE_DAY per degree-day above 0 °C.

The lake's GKD water temperature, where there is one, overrides the model:
a reading above OPEN_WATER_C means the lake is open whatever the model says,
and the model continues from the measured value.

Sheltered bays and harbours freeze long before the open lake, so a cold lake
(at or below 4 °C) after a few frosty days counts as "edges": thin ice at the
shore is possible.

All of this is an estimate for the rowing advice. It can never say that ice is
safe to walk on, and the app says so.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date

# Heat exchange between air and water, as metres of water cooled by 1 °C per day and °C difference.
EXCHANGE_M_PER_DAY = 0.41
# Cold surface layer that has to freeze once the lake is below 4 °C: a share of the mean depth, within limits.
SURFACE_LAYER_SHARE = 0.2
SURFACE_LAYER_M = (2.0, 10.0)
# Lakes without a known depth are taken as shallow, so ice is rather over- than underestimated.
DEFAULT_DEPTH_M = 5.0
MAX_MIXED_DEPTH_M = 60.0
DENSEST_WATER_C = 4.0

STEFAN_CM = 2.0
MELT_CM_PER_DEGREE_DAY = 0.5
# Ice this thick or more counts as a closed ice cover.
COVER_CM = 5.0

# A measured water temperature above this means open water.
OPEN_WATER_C = 3.0
# Water this warm cannot freeze within the forecast week, so the model is not run.
WARM_WATER_C = 8.0
# Frost over the last three days that lets thin ice form in sheltered bays of a cold lake.
EDGE_FROST_DEGREE_DAYS = 6.0
# Rivers: frost over the last week after which drift ice is possible.
DRIFT_ICE_FROST_DEGREE_DAYS = 30.0

# Rough lake surface temperatures in southern Bavaria by month, used only to
# start the model ~90 days back when there is no measurement.
TYPICAL_WATER_C = {1: 3.5, 2: 3.5, 3: 4.5, 4: 8, 5: 13, 6: 18, 7: 21, 8: 21, 9: 18, 10: 13, 11: 8, 12: 5}

# Ice can only occur in these months; outside them no data is fetched.
ICE_MONTHS = {11, 12, 1, 2, 3, 4}

OPEN = "open"
EDGES = "edges"
FORMING = "forming"
FROZEN = "frozen"
DRIFT_ICE = "drift_ice"
STATUS_LIGHT = {OPEN: 0, EDGES: 1, FORMING: 2, FROZEN: 2, DRIFT_ICE: 1}


@dataclass(frozen=True)
class DayTemperature:
    day: date
    mean_c: float


@dataclass(frozen=True)
class IceDay:
    day: date
    status: str
    thickness_cm: float
    water_c: float


@dataclass(frozen=True)
class IceEstimate:
    status: str
    thickness_cm: float | None
    water_c: float | None
    # "season" (no ice possible this month), "measured" (a GKD reading shows open water) or "model".
    basis: str
    frost_degree_days_7: float | None
    days: list[IceDay]

    @property
    def light(self) -> int:
        return STATUS_LIGHT[self.status]


def _frost(temps: list[DayTemperature]) -> float:
    return sum(max(0.0, -t.mean_c) for t in temps)


def _surface_layer(depth_m: float) -> float:
    low, high = SURFACE_LAYER_M
    return min(depth_m, max(low, min(high, SURFACE_LAYER_SHARE * depth_m)))


def _status(thickness_cm: float, water_c: float, recent: list[DayTemperature]) -> str:
    if thickness_cm >= COVER_CM:
        return FROZEN
    if thickness_cm > 0:
        return FORMING
    if water_c <= DENSEST_WATER_C and _frost(recent[-3:]) >= EDGE_FROST_DEGREE_DAYS:
        return EDGES
    return OPEN


def simulate(
    temps: list[DayTemperature],
    today: date,
    mean_depth_m: float | None = None,
    measured_water_c: float | None = None,
) -> IceEstimate:
    """Run the model over `temps` (oldest first, past days and forecast) and report `today` and later."""
    if not temps:
        return IceEstimate(OPEN, None, None, "model", None, [])
    depth = min(mean_depth_m or DEFAULT_DEPTH_M, MAX_MIXED_DEPTH_M)
    water = TYPICAL_WATER_C[temps[0].day.month]
    ice = 0.0
    days: list[IceDay] = []
    for i, t in enumerate(temps):
        if t.day == today and measured_water_c is not None:
            water = measured_water_c
            if measured_water_c > OPEN_WATER_C:
                ice = 0.0
        if ice > 0:
            if t.mean_c < 0:
                ice = math.sqrt(ice * ice + STEFAN_CM * STEFAN_CM * -t.mean_c)
            else:
                ice = max(0.0, ice - MELT_CM_PER_DEGREE_DAY * t.mean_c)
            water = 0.0
        else:
            layer = depth if water > DENSEST_WATER_C else _surface_layer(depth)
            water += EXCHANGE_M_PER_DAY * (t.mean_c - water) / layer
            if water < 0:
                # The heat lost below 0 °C goes into the first ice: 1 °C over 1 m of water freezes about 1.3 cm.
                ice = -water * layer * 1.3
                water = 0.0
        if t.day >= today:
            days.append(IceDay(t.day, _status(ice, water, temps[: i + 1]), round(ice, 1), round(water, 1)))
    if not days:
        return IceEstimate(OPEN, None, round(water, 1), "model", None, [])
    now = days[0]
    upto_today = [t for t in temps if t.day <= today]
    basis = "measured" if measured_water_c is not None and measured_water_c > OPEN_WATER_C else "model"
    return IceEstimate(
        status=now.status,
        thickness_cm=now.thickness_cm if now.thickness_cm > 0 else None,
        water_c=measured_water_c if measured_water_c is not None else now.water_c,
        basis=basis,
        frost_degree_days_7=round(_frost(upto_today[-7:]), 1),
        days=days,
    )


def river(temps: list[DayTemperature], today: date) -> IceEstimate:
    """Rivers keep flowing, so only drift ice after a hard week of frost is flagged."""
    days = []
    for i, t in enumerate(temps):
        if t.day >= today:
            frost = _frost(temps[max(0, i - 6) : i + 1])
            days.append(IceDay(t.day, DRIFT_ICE if frost >= DRIFT_ICE_FROST_DEGREE_DAYS else OPEN, 0.0, 0.0))
    upto_today = [t for t in temps if t.day <= today]
    return IceEstimate(
        status=days[0].status if days else OPEN,
        thickness_cm=None,
        water_c=None,
        basis="model",
        frost_degree_days_7=round(_frost(upto_today[-7:]), 1),
        days=days,
    )


def out_of_season(today: date) -> bool:
    return today.month not in ICE_MONTHS
