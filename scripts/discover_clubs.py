#!/usr/bin/env python3
"""Find rowing clubs on lakes in southern Bavaria in OpenStreetMap.

Usage (from the repository root):
    python3 scripts/discover_clubs.py

Writes data/catalog.json with every OSM feature tagged sport=rowing that lies
or is named like a rowing club ("Ruderclub", "Ruderverein", ...) and lies
within 300 m of a named lake, plus that lake, and saves the lake outline to
data/outlines/ when it is missing. The app offers these clubs in its search.
Their launch point is the shore point nearest the boathouse and counts as
unconfirmed until the club is moved into data/locations.json by hand.
Clubs on rivers and canals are left out, since the wave model needs a lake.

Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import json
import math
import re
import sys
import unicodedata
from datetime import date
from pathlib import Path

from fetch_lake_outline import overpass, stitch
from live_check import nearest_shore

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data" / "catalog.json"
OUTLINES = ROOT / "data" / "outlines"
# Upper Bavaria and the lakes south of Munich: south, west, north, east.
BBOX = (47.40, 10.70, 48.60, 12.90)
MAX_SHORE_M = 300.0
# Few clubs carry sport=rowing in OSM, so club names are matched too.
CLUB_NAME = "[Rr]uder(club|verein|gesellschaft|sport|-| )|Rowing"
NOT_LAKES = {"river", "canal", "stream", "ditch", "drain", "wastewater", "moat", "fish_pass"}


def slug(text: str) -> str:
    text = text.lower().replace("ß", "ss").replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")[:48].rstrip("-")


def _run(q: str) -> list[dict]:
    result = overpass(q, timeout=250)
    if "remark" in result:  # Overpass reports timeouts and memory limits here, with a partial result
        raise OSError(f"Overpass: {result['remark']}")
    return result["elements"]


def query_clubs() -> list[dict]:
    s, w, n, e = BBOX
    bbox = f"({s},{w},{n},{e})"
    return _run(
        f"""
        [out:json][timeout:240];
        (
          nwr["sport"="rowing"]["name"]{bbox};
          nwr["name"~"{CLUB_NAME}"]["club"]{bbox};
          nwr["name"~"{CLUB_NAME}"]["leisure"]{bbox};
        );
        out center tags;
        """
    )


def query_waters(points: list[tuple[float, float]]) -> list[dict]:
    """Named lakes and reservoirs within MAX_SHORE_M of any of the (lat, lon) points.

    Big lakes are multipolygon relations, which `around` does not find
    directly, so their shore ways are found first and then their relations.
    """
    near = "\n".join(f"way(around:{MAX_SHORE_M:.0f},{lat},{lon});" for lat, lon in points)
    return _run(
        f"""
        [out:json][timeout:240];
        ({near})->.near;
        (
          way.near["natural"="water"]["name"];
          way.near["landuse"="reservoir"]["name"];
          rel(bw.near)["natural"="water"]["name"];
          rel(bw.near)["landuse"="reservoir"]["name"];
        );
        out geom;  # "out geom tags" would drop the members of multipolygons
        """
    )


def water_rings(e: dict) -> list[list[tuple[float, float]]]:
    """Shore first, then islands, as (lon, lat) rings."""
    if e["type"] == "way":
        return [[(p["lon"], p["lat"]) for p in e["geometry"]]]
    members = [m for m in e.get("members", []) if m.get("type") == "way" and m.get("geometry")]
    outer = [[(p["lon"], p["lat"]) for p in m["geometry"]] for m in members if m.get("role") == "outer"]
    inner = [[(p["lon"], p["lat"]) for p in m["geometry"]] for m in members if m.get("role") == "inner"]
    return stitch(outer) + (stitch(inner) if inner else [])


def address(tags: dict) -> str:
    street = " ".join(filter(None, [tags.get("addr:street"), tags.get("addr:housenumber")]))
    town = " ".join(filter(None, [tags.get("addr:postcode"), tags.get("addr:city")]))
    return ", ".join(filter(None, [street, town]))


def distance_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Between two (lat, lon) points; fine over a few kilometres."""
    dy = math.radians(b[0] - a[0]) * 6_371_000
    dx = math.radians(b[1] - a[1]) * 6_371_000 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)


def main() -> int:
    confirmed = json.loads((ROOT / "data" / "locations.json").read_text(encoding="utf-8"))
    confirmed_lakes = {l["name"]: l["id"] for l in confirmed["lakes"]}
    confirmed_points = [(c["launchPoint"]["lat"], c["launchPoint"]["lon"]) for c in confirmed["clubs"]]
    confirmed_names = {slug(c["name"]) for c in confirmed["clubs"]} | {slug(c.get("shortName", "")) for c in confirmed["clubs"]}

    def is_club(tags: dict) -> bool:
        name = tags.get("name", "")
        if re.search("verleih|rental|boote? ", name, re.I) or tags.get("shop") or tags.get("amenity") == "boat_rental":
            return False  # boat hire, not a club
        return tags.get("sport") == "rowing" or bool(re.search(CLUB_NAME, name))

    def position(e: dict) -> tuple[float, float]:
        c = e.get("center") or e
        return c["lat"], c["lon"]

    features = [e for e in query_clubs() if is_club(e.get("tags", {})) and ("center" in e or "lat" in e)]
    if not features:
        sys.exit("no rowing clubs found; keeping the old catalog")
    waters = []
    raw_waters = query_waters([position(f) for f in features])
    print(f"{len(features)} club features; lakes nearby: " + ", ".join(
        f"{e.get('tags', {}).get('name')} ({e['type']}/{e['id']}, {len(e.get('members', []))} members)" for e in raw_waters
    ))
    for e in raw_waters:
        tags = e.get("tags", {})
        is_water = tags.get("natural") == "water" or tags.get("landuse") == "reservoir"
        if not is_water or tags.get("water") in NOT_LAKES:
            continue
        try:
            rings = water_rings(e)
        except ValueError as err:
            print(f"skip water {tags.get('name')} {e['type']}/{e['id']}: {err}")
            continue
        waters.append((tags["name"], f"{e['type']}/{e['id']}", rings))

    lakes: dict[str, dict] = {}
    clubs: dict[str, dict] = {}
    report = []
    for f in features:
        tags = f["tags"]
        lat, lon = position(f)
        best = None
        for name, osm_id, rings in waters:
            d, slon, slat = nearest_shore(lon, lat, rings)
            if d <= MAX_SHORE_M and (best is None or d < best[0]):
                best = (d, name, osm_id, rings, slat, slon)
        label = f"{tags['name']} ({f['type']}/{f['id']})"
        if best is None:
            report.append(f"no lake within {MAX_SHORE_M:.0f} m: {label}")
            continue
        d, lake_name, osm_id, rings, slat, slon = best
        if slug(tags["name"]) in confirmed_names or any(distance_m((slat, slon), p) < 150 for p in confirmed_points):
            report.append(f"already confirmed: {label}")
            continue

        lake_id = confirmed_lakes.get(lake_name) or slug(lake_name)
        if lake_id in lakes and lakes[lake_id]["osm"] != osm_id:
            lake_id = f"{lake_id}-{osm_id.split('/')[1]}"
        if lake_id not in lakes:
            lons = [p[0] for p in rings[0]]
            lats = [p[1] for p in rings[0]]
            lakes[lake_id] = {
                "id": lake_id,
                "name": lake_name,
                "center": {"lat": round((min(lats) + max(lats)) / 2, 4), "lon": round((min(lons) + max(lons)) / 2, 4)},
                "osm": osm_id,
            }
            outline = OUTLINES / f"{lake_id}.geojson"
            if not outline.exists():
                outline.write_text(
                    json.dumps(
                        {
                            "type": "Feature",
                            "properties": {"id": lake_id, "name": lake_name, "source": "© OpenStreetMap contributors, ODbL"},
                            "geometry": {"type": "Polygon", "coordinates": [[list(p) for p in r] for r in rings]},
                        }
                    ),
                    encoding="utf-8",
                )

        club_id = re.sub(r"-e-v$", "", slug(tags["name"]))
        if club_id in clubs:  # boathouse and clubhouse both tagged: keep the one nearer the water
            if clubs[club_id]["_shoreM"] <= d:
                continue
        clubs[club_id] = {
            "id": club_id,
            "name": tags["name"],
            "shortName": tags.get("short_name") or tags["name"],
            "lakeId": lake_id,
            "address": address(tags),
            "website": tags.get("website") or tags.get("contact:website"),
            "launchPoint": {
                "lat": round(slat, 5),
                "lon": round(slon, 5),
                "precision": f"shore point nearest {f['type']}/{f['id']} in OpenStreetMap, {d:.0f} m away",
                "verified": False,
            },
            "_shoreM": d,
        }
        report.append(f"added: {label} -> {lake_name}, {d:.0f} m from the shore")

    for c in clubs.values():
        del c["_shoreM"]
    catalog = {
        "version": 1,
        "updated": date.today().isoformat(),
        "source": "© OpenStreetMap contributors, ODbL",
        "lakes": sorted(lakes.values(), key=lambda l: l["name"]),
        "clubs": sorted(clubs.values(), key=lambda c: (lakes[c["lakeId"]]["name"], c["name"])),
    }
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("\n".join(sorted(report)))
    print(f"wrote {CATALOG} with {len(clubs)} clubs on {len(lakes)} lakes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
