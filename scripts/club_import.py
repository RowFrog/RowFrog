"""Shared steps of the club imports: geocoding, finding the water, writing a catalog.

Each import (DRV, ÖRV, Swiss Rowing, OpenStreetMap per country) reads its own
source into club dicts with a position, then calls place() to find the lake or
river each club lies on, and write_catalog() to save data/catalogs/<cc>-<source>.json.

Positions and waters: © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import json
import re
import time
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

from discover_clubs import _run, slug, water_rings
from live_check import nearest_shore

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ROOT / "data" / "catalogs"
GEOCODE_CACHE = ROOT / "data" / "geocode.json"
OUTLINES = ROOT / "data" / "outlines"
UA = "RowFrog/0.1 (+https://github.com/RowFrog/RowFrog)"
LAKE_M = 300.0
RIVER_M = 400.0
BATCH = 20


def get(url: str, language: str = "de") -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": language})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read().decode("utf-8")
        except OSError:
            if attempt == 3:
                raise
            time.sleep(5 * (attempt + 1))
    raise AssertionError


def load_geocode_cache() -> dict:
    return json.loads(GEOCODE_CACHE.read_text(encoding="utf-8")) if GEOCODE_CACHE.exists() else {}


def save_geocode_cache(cache: dict) -> None:
    GEOCODE_CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")


def geocode(street: str, plz: str, town: str, cache: dict, country: str = "de") -> dict | None:
    """The address's position from Nominatim, cached; German keys have no country prefix."""
    key = f"{street}|{plz}|{town}" if country == "de" else f"{country}|{street}|{plz}|{town}"
    if key in cache:
        return cache[key]
    tries = []
    if street:
        tries.append(("street", {"street": street, "postalcode": plz, "city": town}))
        tries.append(("street", {"q": f"{street}, {plz} {town}"}))
    tries.append(("town", {"postalcode": plz, "city": town}))
    result = None
    for precision, params in tries:
        q = urllib.parse.urlencode({**params, "countrycodes": country, "format": "jsonv2", "limit": 1})
        time.sleep(1.1)  # Nominatim usage policy: at most one request per second
        hits = json.loads(get(f"https://nominatim.openstreetmap.org/search?{q}"))
        if hits:
            result = {"lat": round(float(hits[0]["lat"]), 5), "lon": round(float(hits[0]["lon"]), 5), "precision": precision}
            break
    cache[key] = result
    return result


def query_waters(points: list[tuple[float, float]]) -> list[dict]:
    """Named lakes within LAKE_M and named rivers and canals within RIVER_M of the points.

    River polygons (riverbanks) are left out: they are huge and the river
    line is enough to name the water.
    """
    near = "\n".join(f"way(around:{RIVER_M:.0f},{lat},{lon});" for lat, lon in points)
    return _run(
        f"""
        [out:json][timeout:240];
        ({near})->.near;
        (
          way.near["natural"="water"]["name"]["water"!~"^(river|canal|stream|oxbow|lock)$"];
          way.near["landuse"="reservoir"]["name"];
          rel(bw.near)["natural"="water"]["name"]["water"!~"^(river|canal|stream|oxbow|lock)$"];
          rel(bw.near)["landuse"="reservoir"]["name"];
          way.near["waterway"~"^(river|canal)$"]["name"];
        );
        out geom;
        """
    )


def place(clubs: list[dict], country: str, report: list[str], id_prefix: str = "") -> tuple[list[dict], list[dict]]:
    """Finds the water of each club and returns (waters, catalog clubs).

    Each club dict needs "name", "_pos" ({"lat", "lon", "precision"}), "_town"
    and "_where" (what the position is, e.g. "boathouse"), plus the catalog
    fields it keeps ("shortName", "address", "website", ...). Keys starting
    with "_" are dropped. Only "street" or "osm" positions are near enough to
    say which water a club is on; others land under "Water near <town>".
    """
    confirmed = json.loads((ROOT / "data" / "locations.json").read_text(encoding="utf-8"))
    confirmed_lakes = {l["name"]: l["id"] for l in confirmed["lakes"]}
    lakes: dict[str, dict] = {}
    rivers: dict[str, dict] = {}
    out = []
    for start in range(0, len(clubs), BATCH):
        batch = clubs[start : start + BATCH]
        exact = [c for c in batch if c["_pos"]["precision"] in ("street", "osm")]
        elements = query_waters([(c["_pos"]["lat"], c["_pos"]["lon"]) for c in exact]) if exact else []
        time.sleep(2)
        waters = []
        for e in elements:
            tags = e.get("tags", {})
            if "waterway" in tags:
                rings = [[(p["lon"], p["lat"]) for p in e.get("geometry", [])]]
                segments = [[a, b] for r in rings for a, b in zip(r, r[1:])]
                if segments:
                    waters.append(("river", tags["name"], f"way/{e['id']}", segments))
                continue
            try:
                waters.append(("lake", tags["name"], f"{e['type']}/{e['id']}", water_rings(e)))
            except (ValueError, KeyError) as err:
                report.append(f"skip water {tags.get('name')} {e['type']}/{e['id']}: {err}")

        for c in batch:
            lat, lon = c["_pos"]["lat"], c["_pos"]["lon"]
            lake = river = None
            if c in exact:
                for kind, name, osm_id, rings in waters:
                    d, slon, slat = nearest_shore(lon, lat, rings)
                    if kind == "lake" and d <= LAKE_M and (lake is None or d < lake[0]):
                        lake = (d, name, osm_id, rings, slat, slon)
                    if kind == "river" and d <= RIVER_M and (river is None or d < river[0]):
                        river = (d, name)
            where = c["_where"]
            if lake:
                d, name, osm_id, rings, lat, lon = lake
                water_id = confirmed_lakes.get(name) or id_prefix + slug(name)
                if water_id in lakes and lakes[water_id]["osm"] != osm_id:
                    water_id = f"{water_id}-{osm_id.split('/')[1]}"
                if water_id not in lakes:
                    lons = [p[0] for p in rings[0]]
                    lats = [p[1] for p in rings[0]]
                    lakes[water_id] = {
                        "id": water_id,
                        "name": name,
                        "country": country,
                        "center": {"lat": round((min(lats) + max(lats)) / 2, 4), "lon": round((min(lons) + max(lons)) / 2, 4)},
                        "osm": osm_id,
                    }
                    outline = OUTLINES / f"{water_id}.geojson"
                    if not outline.exists():
                        outline.write_text(json.dumps({
                            "type": "Feature",
                            "properties": {"id": water_id, "name": name, "source": "© OpenStreetMap contributors, ODbL"},
                            "geometry": {"type": "Polygon", "coordinates": [[list(p) for p in r] for r in rings]},
                        }), encoding="utf-8")
                precision = f"shore point of {name} nearest the {where}, {d:.0f} m away"
                report.append(f"lake: {c['name']} -> {name}, {d:.0f} m")
            elif river:
                name = river[1]
                water_id = id_prefix + "river-" + slug(name)
                rivers.setdefault(water_id, {"id": water_id, "name": name, "country": country, "center": {"lat": lat, "lon": lon}, "kind": "river"})
                precision = f"{where}, {river[0]:.0f} m from the {name}"
                report.append(f"river: {c['name']} -> {name}")
            else:
                town = c["_town"]
                name = f"Water near {town}"
                water_id = id_prefix + "near-" + slug(town)
                rivers.setdefault(water_id, {"id": water_id, "name": name, "country": country, "center": {"lat": lat, "lon": lon}, "kind": "unknown"})
                precision = f"{where} ({c['_pos']['precision']} level); water not identified"
                report.append(f"no water found: {c['name']} ({c['_pos']['precision']})")

            club = {k: v for k, v in c.items() if not k.startswith("_")}
            club.update({
                "country": country,
                "lakeId": water_id,
                "launchPoint": {"lat": round(lat, 5), "lon": round(lon, 5), "precision": precision, "verified": False},
            })
            out.append(club)
        print(f"{min(start + BATCH, len(clubs))}/{len(clubs)} clubs placed")
    return [*rivers.values(), *lakes.values()], out


def write_catalog(name: str, source: str, waters: list[dict], clubs: list[dict]) -> Path:
    """Saves data/catalogs/<name>.json, e.g. name "at-oerv"."""
    CATALOGS.mkdir(exist_ok=True)
    path = CATALOGS / f"{name}.json"
    catalog = {
        "version": 1,
        "updated": date.today().isoformat(),
        "source": source,
        "lakes": sorted(waters, key=lambda l: l["name"]),
        "clubs": sorted(clubs, key=lambda c: c["name"]),
    }
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lakes = sum(1 for w in waters if "osm" in w)
    print(f"wrote {path} with {len(clubs)} clubs: {lakes} lakes, "
          f"{sum(1 for c in clubs if '-river-' in '-' + c['lakeId'])} on rivers, "
          f"{sum(1 for c in clubs if '-near-' in '-' + c['lakeId'])} on unidentified water")
    return path


def split_address(address: str, digits: int) -> tuple[str, str, str] | None:
    """(street, postcode, town) from "Street 1, 1220 Wien" with `digits`-digit postcodes."""
    m = re.match(rf"^(?:(.*?),\s*)?(?:[A-Z]{{1,2}}-)?(\d{{{digits}}})\s+(.+)$", address.strip())
    if not m:
        return None
    street, plz, town = m.groups()
    return (street or "").strip(), plz, town.strip()
