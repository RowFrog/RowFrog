"""Lakes and clubs, loaded from data/locations.json and data/catalog.json.

locations.json holds the clubs whose launch points were confirmed by hand.
New lakes and clubs are added by editing that file; no code change is needed.
catalog.json is generated from OpenStreetMap by scripts/discover_clubs.py and
makes more clubs findable in the app's search; its launch points are the
boathouse positions from OSM and count as unconfirmed. An entry in
locations.json always wins over a catalog entry with the same id.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[2] / "data"
DEFAULT_PATH = DATA_DIR / "locations.json"
DEFAULT_CATALOG_PATH = DATA_DIR / "catalog.json"


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


@dataclass(frozen=True)
class Locations:
    lakes: dict[str, Lake]
    clubs: dict[str, Club]

    def clubs_on(self, lake_id: str) -> list[Club]:
        return [c for c in self.clubs.values() if c.lake_id == lake_id]


def _parse(raw: dict, lakes: dict[str, Lake], clubs: dict[str, Club]) -> None:
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
        clubs[c["id"]] = Club(
            id=c["id"],
            name=c["name"],
            short_name=c.get("shortName") or c["name"],
            lake_id=c["lakeId"],
            address=c.get("address", ""),
            website=c.get("website"),
            launch_point=Point(lat=lp["lat"], lon=lp["lon"]),
            launch_point_verified=lp.get("verified", False),
        )


def load(path: Path = DEFAULT_PATH, catalog_path: Path | None = DEFAULT_CATALOG_PATH) -> Locations:
    lakes: dict[str, Lake] = {}
    clubs: dict[str, Club] = {}
    _parse(json.loads(path.read_text(encoding="utf-8")), lakes, clubs)
    if catalog_path is not None and catalog_path.exists():
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        for c in catalog.get("clubs", []):
            c.setdefault("launchPoint", {})["verified"] = False
        _parse(catalog, lakes, clubs)
    return Locations(lakes=lakes, clubs=clubs)
