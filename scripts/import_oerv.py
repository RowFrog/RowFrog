#!/usr/bin/env python3
"""Import the clubs of the Austrian Rowing Federation (ÖRV) into the search.

Usage (from the repository root):
    python3 scripts/import_oerv.py

Reads the club list at rudern.at/vereine, which holds every member club by
state in one page, geocodes each club's address with Nominatim and finds the
water it lies on in OpenStreetMap, like scripts/import_drv.py. Writes
data/catalogs/at-oerv.json. Launch points count as unconfirmed.

Only club facts are kept (name, abbreviation, website, address, state); not
the e-mail addresses the list also shows.

Club data: Österreichischer Ruderverband, rudern.at. Positions and waters:
© OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import json
import re
import sys

from club_import import geocode, get, load_geocode_cache, place, save_geocode_cache, split_address, write_catalog
from discover_clubs import slug

URL = "https://www.rudern.at/vereine/"
STATES = {
    "wien": "Wien", "niederoesterreich": "Niederösterreich", "oberoesterreich": "Oberösterreich",
    "salzburg": "Salzburg", "tirol": "Tirol", "vorarlberg": "Vorarlberg", "kaernten": "Kärnten",
    "steiermark": "Steiermark", "burgenland": "Burgenland",
}


def club_list(page: str) -> list[dict]:
    """The page's `oerv_vereine_data` array: one entry per state with its clubs."""
    m = re.search(r"oerv_vereine_data\s*=\s*", page)
    if not m:
        raise ValueError("no oerv_vereine_data on the page")
    data, _ = json.JSONDecoder().raw_decode(page[m.end():])
    return data


def state_name(entry: dict) -> str:
    land = entry.get("land", "")
    return STATES.get(land) or re.sub(r"^Vereine (in|aus) ", "", entry.get("name", "")) or land


def main() -> int:
    states = club_list(get(URL))
    entries = [(state_name(s), v) for s in states for v in s.get("vereine", [])]
    print(f"{len(entries)} clubs in {len(states)} states on the ÖRV list")
    if len(entries) < 30:
        sys.exit("the ÖRV list looks incomplete; keeping the old catalog")

    cache = load_geocode_cache()
    report: list[str] = []
    clubs: list[dict] = []
    seen: set[str] = set()
    for state, v in entries:
        name = " ".join(v.get("name", "").split())
        address = " ".join(v.get("address", "").split())
        parts = split_address(address, 4)
        if not name:
            continue
        club_id = slug(name)
        if club_id in seen:
            report.append(f"listed twice: {name}")
            continue
        seen.add(club_id)
        if parts is None:
            report.append(f"no address: {name}: {address!r}")
            continue
        street, plz, town = parts
        try:
            pos = geocode(street, plz, town, cache, country="at")
        except OSError as err:
            report.append(f"geocoding failed: {name}: {err}")
            continue
        if pos is None:
            report.append(f"address not found: {name}: {address}")
            continue
        website = (v.get("url") or "").strip() or None
        if website and not re.match(r"https?://", website):
            website = "https://" + website
        clubs.append({
            "id": club_id,
            "name": name,
            "shortName": name,
            "abbreviation": (v.get("short") or "").strip() or None,
            "address": ", ".join(filter(None, [street, f"{plz} {town}"])),
            "website": website,
            "region": state,
            "source": "oerv",
            "_pos": pos,
            "_town": town,
            "_where": "geocoded club address",
        })
    save_geocode_cache(cache)

    waters, out = place(clubs, "at", report)
    write_catalog(
        "at-oerv",
        "Club data: Österreichischer Ruderverband (rudern.at). Positions and waters: © OpenStreetMap contributors, ODbL",
        waters,
        out,
    )
    print("\n".join(sorted(report)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
