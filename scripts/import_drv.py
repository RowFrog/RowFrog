#!/usr/bin/env python3
"""Import the clubs of the German Rowing Association (DRV) into the search.

Usage (from the repository root):
    python3 scripts/import_drv.py

Reads the club list at rudern.de/service/vereinssuche and each club's page,
geocodes the boathouse address with Nominatim, and finds the water it lies
on in OpenStreetMap. Writes data/catalog-drv.json, which the app's search
offers next to the OSM catalog. Launch points count as unconfirmed:

- on a lake, the shore point nearest the boathouse, with the lake outline
  saved to data/outlines/ so waves can be estimated;
- on a river or canal, the boathouse itself (no waves are computed);
- elsewhere, the boathouse, under "Water near <town>".

Only club facts are kept (name, short name, abbreviation, DRV-ID, website,
kinds of rowing offered, boathouse address); no names, e-mails or phone
numbers of people. Geocoding results are cached in data/drv-geocode.json so
reruns ask Nominatim only about new or moved boathouses.

Club data: Deutscher Ruderverband e.V., rudern.de. Positions and waters:
© OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

from discover_clubs import _run, slug, water_rings
from live_check import nearest_shore

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "catalog-drv.json"
GEOCODE_CACHE = ROOT / "data" / "drv-geocode.json"
OUTLINES = ROOT / "data" / "outlines"
BASE = "https://www.rudern.de"
UA = "RowerWeather/0.1 (+https://github.com/RowerWeatherFrog/RowerWeather)"
LAKE_M = 300.0
RIVER_M = 400.0
BATCH = 20
LABELS = {
    "DRV-ID", "Kurzname", "Abkürzung", "Mitglieder", "Gründung", "Website", "E-Mail", "Telefon",
    "Sportliches Angebot", "Bootshaus", "Anschrift", "Vereine in der Umgebung", "Route planen",
}
RIVER_WATER = {"river", "canal", "stream", "oxbow", "lock", "moat", "ditch", "drain", "fish_pass"}


def get(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "de"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read().decode("utf-8")
        except OSError:
            if attempt == 3:
                raise
            time.sleep(5 * (attempt + 1))
    raise AssertionError


def club_slugs(page: str) -> list[str]:
    return list(dict.fromkeys(re.findall(r'href="/service/vereine/([a-z0-9-]+)"', page)))


def page_lines(page: str) -> list[str]:
    m = re.search(r"(?s)<main.*?</main>", page)
    t = m.group(0) if m else page
    t = re.sub(r"(?s)<(script|style|nav)\b.*?</\1>", "", t)
    t = re.sub(r"<(br|/p|/div|/li|/h\d|/dt|/dd|/tr)[^>]*>", "\n", t)
    t = html.unescape(re.sub(r"<[^>]+>", " ", t))
    return [" ".join(l.split()) for l in t.splitlines() if l.strip()]


def field(lines: list[str], label: str) -> str | None:
    if label in lines:
        i = lines.index(label)
        if i + 1 < len(lines) and lines[i + 1] not in LABELS:
            return lines[i + 1]
    return None


def block(lines: list[str], label: str) -> list[str]:
    if label not in lines:
        return []
    out = []
    for l in lines[lines.index(label) + 1 :]:
        if l in LABELS or l.startswith("Route planen"):
            break
        out.append(l)
    return out


def street_and_town(lines: list[str]) -> tuple[str, str, str] | None:
    """(street, postcode, town) from an address block whose last line is "Town 12345".

    Lines above the street (club name, a contact person) are dropped.
    """
    if not lines:
        return None
    m = re.match(r"^(.*\S)\s+(\d{5})$", lines[-1])
    if not m:
        return None
    town, plz = m.groups()
    street = next((l for l in reversed(lines[:-1]) if _looks_like_street(l)), "")
    return street, plz, town


def _looks_like_street(line: str) -> bool:
    if re.search(r"(?i)postfach|e\.\s?v\.|\bherrn?\b|\bfrau\b|/|c/o", line):
        return False
    return bool(re.search(r"(?i)\d|(str\.?|stra(ss|ß)e|weg|platz|ufer|damm|allee|kai|promenade|gasse|ring|hafen|wörth|insel|lände|au)\b", line))


def parse_club(club_slug: str, page: str) -> dict | None:
    lines = page_lines(page)
    if "DRV-ID" not in lines:
        return None
    name = lines[lines.index("DRV-ID") - 1]
    address = street_and_town(block(lines, "Bootshaus")) or street_and_town(block(lines, "Anschrift"))
    website = field(lines, "Website")
    if website and not re.match(r"https?://", website):
        website = "https://" + website
    sports = field(lines, "Sportliches Angebot")
    return {
        "drvSlug": club_slug,
        "drvId": field(lines, "DRV-ID"),
        "name": name,
        "shortName": field(lines, "Kurzname") or name,
        "abbreviation": field(lines, "Abkürzung"),
        "website": website,
        "sports": [s.strip() for s in sports.split(",")] if sports else [],
        "boathouse": bool(block(lines, "Bootshaus")),
        "_address": address,
    }


def geocode(street: str, plz: str, town: str, cache: dict) -> dict | None:
    key = f"{street}|{plz}|{town}"
    if key in cache:
        return cache[key]
    tries = []
    if street:
        tries.append(("street", {"street": street, "postalcode": plz, "city": town}))
        tries.append(("street", {"q": f"{street}, {plz} {town}"}))
    tries.append(("town", {"postalcode": plz, "city": town}))
    result = None
    for precision, params in tries:
        q = urllib.parse.urlencode({**params, "countrycodes": "de", "format": "jsonv2", "limit": 1})
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


def main() -> int:
    confirmed = json.loads((ROOT / "data" / "locations.json").read_text(encoding="utf-8"))
    confirmed_names = {c["name"] for c in confirmed["clubs"]}
    confirmed_lakes = {l["name"]: l["id"] for l in confirmed["lakes"]}
    cache = json.loads(GEOCODE_CACHE.read_text(encoding="utf-8")) if GEOCODE_CACHE.exists() else {}

    slugs = club_slugs(get(f"{BASE}/service/vereinssuche"))
    print(f"{len(slugs)} clubs on the DRV list")
    if len(slugs) < 100:
        sys.exit("the DRV list looks incomplete; keeping the old catalog")

    report: list[str] = []
    clubs: list[dict] = []
    failures = 0
    for i, s in enumerate(slugs):
        time.sleep(1.0)  # one page a second
        try:
            club = parse_club(s, get(f"{BASE}/service/vereine/{s}"))
        except OSError as err:
            failures += 1
            report.append(f"page failed: {s}: {err}")
            continue
        if club is None:
            failures += 1
            report.append(f"no club data: {s}")
            continue
        if club["name"] in confirmed_names:
            report.append(f"already confirmed: {club['name']}")
            continue
        if club["_address"] is None:
            report.append(f"no address: {club['name']}")
            continue
        try:
            club["_pos"] = geocode(*club["_address"], cache)
        except OSError as err:
            failures += 1
            report.append(f"geocoding failed: {club['name']}: {err}")
            continue
        if club["_pos"] is None:
            report.append(f"address not found: {club['name']}: {club['_address']}")
            continue
        clubs.append(club)
        if i % 50 == 0:
            print(f"{i}/{len(slugs)} pages read")
    GEOCODE_CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    if failures > len(slugs) // 5:
        print("\n".join(report))
        sys.exit(f"{failures} clubs failed; keeping the old catalog")

    lakes: dict[str, dict] = {}
    rivers: dict[str, dict] = {}
    out_clubs = []
    for start in range(0, len(clubs), BATCH):
        batch = clubs[start : start + BATCH]
        # Only street-level positions are near enough to say which water a club is on.
        exact = [c for c in batch if c["_pos"]["precision"] == "street"]
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
            street, plz, town = c["_address"]
            lake = river = None
            if c in exact:
                for kind, name, osm_id, rings in waters:
                    d, slon, slat = nearest_shore(lon, lat, rings)
                    if kind == "lake" and d <= LAKE_M and (lake is None or d < lake[0]):
                        lake = (d, name, osm_id, rings, slat, slon)
                    if kind == "river" and d <= RIVER_M and (river is None or d < river[0]):
                        river = (d, name)
            where = "boathouse" if c["boathouse"] else "club address"
            if lake:
                d, name, osm_id, rings, lat, lon = lake
                water_id = confirmed_lakes.get(name) or slug(name)
                if water_id in lakes and lakes[water_id]["osm"] != osm_id:
                    water_id = f"{water_id}-{osm_id.split('/')[1]}"
                if water_id not in lakes:
                    lons = [p[0] for p in rings[0]]
                    lats = [p[1] for p in rings[0]]
                    lakes[water_id] = {
                        "id": water_id,
                        "name": name,
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
                precision = f"shore point of {name} nearest the geocoded {where}, {d:.0f} m away"
                report.append(f"lake: {c['name']} -> {name}, {d:.0f} m")
            elif river:
                name = river[1]
                water_id = "river-" + slug(name)
                rivers.setdefault(water_id, {"id": water_id, "name": name, "center": {"lat": lat, "lon": lon}, "kind": "river"})
                precision = f"geocoded {where}, {river[0]:.0f} m from the {name}"
                report.append(f"river: {c['name']} -> {name}")
            else:
                name = f"Water near {town}"
                water_id = "near-" + slug(town)
                rivers.setdefault(water_id, {"id": water_id, "name": name, "center": {"lat": lat, "lon": lon}, "kind": "unknown"})
                precision = f"geocoded {where} ({c['_pos']['precision']} level); water not identified"
                report.append(f"no water found: {c['name']} ({c['_pos']['precision']})")

            out_clubs.append({
                "id": re.sub(r"-e-?v$", "", c["drvSlug"]),
                "name": c["name"],
                "shortName": c["shortName"],
                "abbreviation": c["abbreviation"],
                "drvId": c["drvId"],
                "lakeId": water_id,
                "address": ", ".join(filter(None, [street, f"{plz} {town}"])),
                "website": c["website"],
                "sports": c["sports"],
                "source": "drv",
                "launchPoint": {"lat": round(lat, 5), "lon": round(lon, 5), "precision": precision, "verified": False},
            })
        print(f"{min(start + BATCH, len(clubs))}/{len(clubs)} clubs placed")

    waters = {**rivers, **lakes}
    catalog = {
        "version": 1,
        "updated": date.today().isoformat(),
        "source": "Club data: Deutscher Ruderverband e.V. (rudern.de). Positions and waters: © OpenStreetMap contributors, ODbL",
        "lakes": sorted(waters.values(), key=lambda l: l["name"]),
        "clubs": sorted(out_clubs, key=lambda c: c["name"]),
    }
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("\n".join(sorted(report)))
    print(f"wrote {OUT} with {len(out_clubs)} clubs: {len(lakes)} lakes, "
          f"{sum(1 for c in out_clubs if c['lakeId'].startswith('river-'))} on rivers, "
          f"{sum(1 for c in out_clubs if c['lakeId'].startswith('near-'))} on unidentified water")
    return 0


if __name__ == "__main__":
    sys.exit(main())
