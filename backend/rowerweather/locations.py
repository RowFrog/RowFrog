"""Lakes and clubs, loaded from data/locations.json and data/catalogs/.

locations.json holds the clubs whose launch points were confirmed by hand.
New lakes and clubs are added by editing that file; no code change is needed.
The catalogs make more clubs findable in the app's search, one file per
country and source, named <country>-<source>.json: de-drv from the German
Rowing Association's club list (scripts/import_drv.py), at-oerv from the
Austrian federation's (scripts/import_oerv.py), ch-swissrowing from Swiss
Rowing's (scripts/import_swissrowing.py) and <country>-osm from OpenStreetMap
(scripts/discover_clubs.py for Bavaria, scripts/import_osm_clubs.py for
whole countries). Their launch points count as unconfirmed. locations.json
always wins, then the catalogs in CATALOGS order (a federation's list before
OpenStreetMap); a catalog club with the same id as an earlier club, or within
DUPLICATE_M of a club from an earlier file, is left out as the same club.
Every lake and club has a country (ISO 3166 code, lower case); the app loads
the clubs of one country at a time.
"""

from __future__ import annotations

import dataclasses
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

DATA_DIR = Path(__file__).resolve().parents[2] / "data"
DEFAULT_PATH = DATA_DIR / "locations.json"
CATALOG_DIR = DATA_DIR / "catalogs"
CATALOGS = ("de-drv", "de-osm", "at-oerv", "at-osm", "ch-swissrowing", "ch-osm")
DEFAULT_CATALOG_PATHS = tuple(CATALOG_DIR / f"{name}.json" for name in CATALOGS)
# Country names for the app's country list, in English and German.
COUNTRIES = {
    "de": ("Germany", "Deutschland"),
    "at": ("Austria", "Österreich"),
    "ch": ("Switzerland", "Schweiz"),
}
# Mean depths for lakes from the catalogs, which do not carry one; used by the ice estimate.
DEPTHS_PATH = DATA_DIR / "lake-depths.json"
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
    # "lake" or, for catalog waters, "river" or "unknown".
    kind: str = "lake"
    mean_depth_m: float | None = None
    country: str = "de"


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
    country: str = "de"
    # The state or canton, where the source names one (e.g. "Wien", "Zürich").
    region: str | None = None


@dataclass(frozen=True)
class Locations:
    lakes: dict[str, Lake]
    clubs: dict[str, Club]

    def clubs_on(self, lake_id: str, country: str | None = None) -> list[Club]:
        return [c for c in self.clubs.values() if c.lake_id == lake_id and country in (None, c.country)]

    def countries(self) -> list[str]:
        """Countries with clubs, in the order of COUNTRIES, then any others."""
        found = {c.country for c in self.clubs.values()}
        return [c for c in COUNTRIES if c in found] + sorted(found - set(COUNTRIES))


def _distance_m(a: Point, b: Point) -> float:
    dy = math.radians(b.lat - a.lat) * 6_371_000
    dx = math.radians(b.lon - a.lon) * 6_371_000 * math.cos(math.radians(a.lat))
    return math.hypot(dx, dy)


def _parse(raw: dict, lakes: dict[str, Lake], clubs: dict[str, Club], source: str | None = None, country: str = "de") -> None:
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
                kind=l.get("kind", "lake"),
                mean_depth_m=l.get("meanDepthM"),
                country=l.get("country", country),
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
            country=c.get("country", country),
            region=c.get("region"),
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
        # "at-oerv.json" -> country "at", source "oerv"; other names count as OpenStreetMap.
        country, _, name = catalog_path.stem.partition("-")
        if not name or len(country) != 2:
            country, name = "de", "osm"
        _parse(catalog, lakes, clubs, source=name, country=country)
        used = {c.lake_id for c in clubs.values()}
        for lake_id in set(lakes) - before - used:
            del lakes[lake_id]
    if DEPTHS_PATH.exists():
        depths = json.loads(DEPTHS_PATH.read_text(encoding="utf-8"))["meanDepthM"]
        for lake_id, depth in depths.items():
            if lake_id in lakes and lakes[lake_id].mean_depth_m is None:
                lakes[lake_id] = dataclasses.replace(lakes[lake_id], mean_depth_m=depth)
    return Locations(lakes=lakes, clubs=clubs)
