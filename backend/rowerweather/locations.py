"""Lakes and clubs, loaded from data/locations.json and data/catalog.json.

locations.json holds the clubs whose launch points were confirmed by hand.
New lakes and clubs are added by editing that file; no code change is needed.
The catalogs make more clubs findable in the app's search: catalog-drv.json
comes from the German Rowing Association's club list (scripts/import_drv.py)
and catalog.json from OpenStreetMap (scripts/discover_clubs.py). Their launch
points count as unconfirmed. locations.json always wins, then the DRV
catalog; a catalog club with the same id as an earlier club, or within
DUPLICATE_M of a club from an earlier file, is left out as the same club.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

DATA_DIR = Path(__file__).resolve().parents[2] / "data"
DEFAULT_PATH = DATA_DIR / "locations.json"
DEFAULT_CATALOG_PATHS = (DATA_DIR / "catalog-drv.json", DATA_DIR / "catalog.json")
DUPLICATE_M = 300.0


@dataclass(frozen=True)
class Point:
    lat: float
    lon: float


@dataclass(frozen=True)
class Lake:
    id: str
    name: str
    center: Point
    area_km2: float | None
    length_km: float | None
    gkd_water_temperature_station: str | None
    storm_warning_service: bool


@dataclass(frozen=True)
class Club:
    id: str
    name: str
    short_name: str
    lake_id: str
    address: str
    website: str | None
    launch_point: Point
    launch_point_verified: bool
    source: str | None = None
    abbreviation: str | None = None


@dataclass(frozen=True)
class Locations:
    lakes: dict[str, Lake]
    clubs: dict[str, Club]

    def clubs_on(self, lake_id: str) -> list[Club]:
        return [c for c in self.clubs.values() if c.lake_id == lake_id]


def _distance_m(a: Point, b: Point) -> float:
    dy = math.radians(b.lat - a.lat) * 6_371_000
    dx = math.radians(b.lon - a.lon) * 6_371_000 * math.cos(math.radians(a.lat))
    return math.hypot(dx, dy)


def _parse(raw: dict, lakes: dict[str, Lake], clubs: dict[str, Club], source: str | None = None) -> None:
    # Clubs in one file can share a boathouse or a town; only earlier files count as duplicates.
    earlier = list(clubs.values()) if source is not None else []
    for l in raw.get("lakes", []):
        lakes.setdefault(
            l["id"],
            Lake(
                id=l["id"],
                name=l["name"],
                center=Point(**l["center"]),
                area_km2=l.get("areaKm2"),
                length_km=l.get("lengthKm"),
                gkd_water_temperature_station=l.get("gkdWaterTemperatureStation"),
                storm_warning_service=l.get("stormWarningService", False),
            ),
        )
    for c in raw.get("clubs", []):
        if c["id"] in clubs:
            continue
        if c["lakeId"] not in lakes:
            raise ValueError(f"club {c['id']} refers to unknown lake {c['lakeId']}")
        lp = c["launchPoint"]
        point = Point(lat=lp["lat"], lon=lp["lon"])
        if source is not None and any(_distance_m(point, o.launch_point) < DUPLICATE_M for o in earlier):
            continue
        clubs[c["id"]] = Club(
            id=c["id"],
            name=c["name"],
            short_name=c.get("shortName") or c["name"],
            lake_id=c["lakeId"],
            address=c.get("address", ""),
            website=c.get("website"),
            launch_point=point,
            launch_point_verified=lp.get("verified", False),
            source=c.get("source", source),
            abbreviation=c.get("abbreviation"),
        )


def load(path: Path = DEFAULT_PATH, catalog_paths: Sequence[Path] = DEFAULT_CATALOG_PATHS) -> Locations:
    lakes: dict[str, Lake] = {}
    clubs: dict[str, Club] = {}
    _parse(json.loads(path.read_text(encoding="utf-8")), lakes, clubs)
    for catalog_path in catalog_paths:
        if not catalog_path.exists():
            continue
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        for c in catalog.get("clubs", []):
            c.setdefault("launchPoint", {})["verified"] = False
        # Drop waters whose clubs all turned out to be duplicates.
        before = set(lakes)
        _parse(catalog, lakes, clubs, source="osm")
        used = {c.lake_id for c in clubs.values()}
        for lake_id in set(lakes) - before - used:
            del lakes[lake_id]
    return Locations(lakes=lakes, clubs=clubs)
