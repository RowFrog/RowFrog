"""Which water temperature station a club's forecast reads.

data/water-stations.json (written by scripts/water_station_survey.py --write)
names, per club, the nearest station on the club's own water within reach,
so on a lake or river with several stations (Main, Bodensee) each club gets
the one closest to its launch point. A club not listed falls back to its
lake's gkdWaterTemperatureStation in data/locations.json, if any.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache

from . import locations

PATH = locations.DATA_DIR / "water-stations.json"


@dataclass(frozen=True)
class Station:
    network: str  # "gkd", "pegelonline" or "bafu"
    id: str  # GKD page slug, PEGELONLINE uuid or BAFU station number
    kind: str = "lake"  # GKD keeps lake and river stations under different pages
    name: str | None = None
    lat: float | None = None
    lon: float | None = None
    distance_km: float | None = None

    @property
    def key(self) -> str:
        return f"{self.network}:{self.id}"


@lru_cache(maxsize=1)
def _load() -> dict[str, Station]:
    if not PATH.exists():
        return {}
    raw = json.loads(PATH.read_text(encoding="utf-8"))
    return {
        club_id: Station(s["network"], s["id"], s.get("kind", "lake"), s.get("name"), s.get("lat"), s.get("lon"), s.get("distanceKm"))
        for club_id, s in raw.get("clubs", {}).items()
    }


def for_club(club: locations.Club, lake: locations.Lake) -> Station | None:
    if club.id in _load():
        return _load()[club.id]
    return Station("gkd", lake.gkd_water_temperature_station) if lake.gkd_water_temperature_station else None


def for_lake(lake: locations.Lake, clubs: list[locations.Club] = ()) -> Station | None:
    """The lake's own station, else a lake station one of its clubs reads (Stegen on the Ammersee), for the lake view."""
    if lake.gkd_water_temperature_station:
        return Station("gkd", lake.gkd_water_temperature_station)
    return next((s for c in clubs if (s := _load().get(c.id)) and s.kind == "lake"), None)
