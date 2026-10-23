#!/usr/bin/env python3
"""Find the rowing clubs of a whole country in OpenStreetMap.

Usage (from the repository root):
    python3 scripts/import_osm_clubs.py at    # or ch, ...

Takes every feature in the country tagged sport=rowing, or tagged as a club
or leisure place and named like a rowing club in German, French, Italian or
English, finds the lake or river it lies on (like the federation imports)
and writes data/catalogs/<country>-osm.json. Clubs a federation list already
has are dropped when the catalogs load (same place within 300 m), so this
file only adds clubs missing from the federation's list. Launch points count
as unconfirmed.

Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import re
import sys

from club_import import place, write_catalog
from discover_clubs import _run, address, slug

# Rowing club names in German, English, French and Italian; "Seeclub" alone is often sailing.
CLUB_NAME = "[Rr]uder|[Rr]owing|[Aa]viron|[Cc]anott"
NOT_CLUBS = re.compile(r"(?i)verleih|vermietung|rental|location|noleggio|shop")


def query_clubs(country: str) -> list[dict]:
    return _run(
        f"""
        [out:json][timeout:240];
        area["ISO3166-1"="{country.upper()}"][admin_level=2]->.country;
        (
          nwr["sport"="rowing"]["name"](area.country);
          nwr["name"~"{CLUB_NAME}"]["club"](area.country);
          nwr["name"~"{CLUB_NAME}"]["leisure"](area.country);
        );
        out center tags;
        """
    )


def main() -> int:
    if len(sys.argv) != 2 or not re.fullmatch(r"[a-z]{2}", sys.argv[1]):
        sys.exit("usage: import_osm_clubs.py <country code, e.g. at>")
    country = sys.argv[1]
    features = []
    for e in query_clubs(country):
        tags = e.get("tags", {})
        name = tags.get("name", "")
        if NOT_CLUBS.search(name) or tags.get("shop") or tags.get("amenity") == "boat_rental":
            continue
        if "center" in e or "lat" in e:
            features.append(e)
    print(f"{len(features)} rowing club features in {country.upper()}")
    if not features:
        sys.exit("no rowing clubs found; keeping the old catalog")

    report: list[str] = []
    clubs: dict[str, dict] = {}
    for f in features:
        tags = f["tags"]
        club_id = slug(tags["name"])
        if club_id in clubs:  # boathouse and clubhouse both tagged: keep the first
            report.append(f"same name twice: {tags['name']} ({f['type']}/{f['id']})")
            continue
        c = f.get("center") or f
        town = tags.get("addr:city") or tags.get("addr:place") or tags["name"]
        clubs[club_id] = {
            "id": club_id,
            "name": tags["name"],
            "shortName": tags.get("short_name") or tags["name"],
            "address": address(tags),
            "website": tags.get("website") or tags.get("contact:website"),
            "source": "osm",
            "_pos": {"lat": round(c["lat"], 5), "lon": round(c["lon"], 5), "precision": "osm"},
            "_town": town,
            "_where": f"{f['type']}/{f['id']} in OpenStreetMap",
        }
    waters, out = place(list(clubs.values()), country, report)
    write_catalog(f"{country}-osm", "© OpenStreetMap contributors, ODbL", waters, out)
    print("\n".join(sorted(report)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
