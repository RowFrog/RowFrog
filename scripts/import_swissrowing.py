#!/usr/bin/env python3
"""Import the clubs of Swiss Rowing (Schweizerischer Ruderverband) into the search.

Usage (from the repository root):
    python3 scripts/import_swissrowing.py              # writes the catalog
    python3 scripts/import_swissrowing.py --dry-run 3  # reads 3 club pages, prints, writes nothing

Swiss Rowing's imprint asks for written consent before any part of the site
is reproduced, so the catalog is only written once that consent is given;
until then data/catalogs/ch-osm.json covers Switzerland. --dry-run reads a
few pages to check the parsing still fits the site.

Reads the club directory at swissrowing.ch/de/verband/ruderclubs and each
club's page, geocodes the boathouse address with Nominatim and finds the
water it lies on, like scripts/import_drv.py. Writes
data/catalogs/ch-swissrowing.json. Only club facts are kept (name, address,
website, founding year); no people, e-mail addresses, phone numbers or blade
pictures.

Club data: Swiss Rowing, swissrowing.ch. Positions and waters:
© OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import html
import re
import sys
import time
import urllib.parse

from club_import import geocode, get, load_geocode_cache, place, save_geocode_cache, write_catalog
from discover_clubs import slug
from import_drv import page_lines

BASE = "https://www.swissrowing.ch"
LIST = BASE + "/de/verband/ruderclubs"
NOT_WEBSITES = re.compile(r"(?i)swissrowing\.ch|facebook|instagram|linkedin|youtube|twitter|x\.com|tiktok|google|soul\.media|mailto:")


def club_links(page: str) -> list[tuple[str, str]]:
    """(url, name) for each club in the directory's title column."""
    found = re.findall(r'(?s)views-field-title[^>]*>\s*<a href="([^"]+)"[^>]*>(.*?)</a>', page)
    return list(dict.fromkeys((urllib.parse.urljoin(BASE, u), html.unescape(" ".join(n.split()))) for u, n in found))


def parse_club(url: str, name: str, page: str) -> dict:
    lines = page_lines(page)
    street = plz = town = None
    for i, line in enumerate(lines):
        m = re.match(r"^(?:CH-)?(\d{4})\s+([^\d].*)$", line)
        if m and i > 0:
            plz, town = m.groups()
            prev = lines[i - 1]
            street = prev if re.search(r"\d|strasse|weg|quai|platz|rue|chemin|via|avenue|ufer", prev, re.I) and prev != name else ""
            break
    founded = None
    for line in lines:
        m = re.search(r"(?i)(gegründet|gründung\w*|fondé\w*|fondat\w*)\D{0,20}((?:18|19|20)\d\d)", line)
        if m:
            founded = int(m.group(2))
            break
    links = re.findall(r'<a\b[^>]*href="(https?://[^"]+)"', page)
    main = re.search(r"(?s)<main.*?</main>", page)
    if main:
        links = re.findall(r'<a\b[^>]*href="(https?://[^"]+)"', main.group(0))
    website = next((l for l in links if not NOT_WEBSITES.search(l)), None)
    return {
        "id": slug(name),
        "name": name,
        "shortName": name,
        "address": ", ".join(filter(None, [street, f"{plz} {town}" if plz else None])),
        "website": website,
        "founded": founded,
        "source": "swissrowing",
        "_url": url,
        "_parts": (street or "", plz, town) if plz else None,
        "_lines": lines,
    }


def main() -> int:
    dry = None
    if "--dry-run" in sys.argv:
        dry = int(sys.argv[sys.argv.index("--dry-run") + 1])
    links = club_links(get(LIST))
    print(f"{len(links)} clubs in the Swiss Rowing directory")
    if len(links) < 40:
        sys.exit("the Swiss Rowing directory looks incomplete; keeping the old catalog")

    report: list[str] = []
    clubs: list[dict] = []
    cache = load_geocode_cache()
    for url, name in links[: dry or None]:
        time.sleep(1.0)  # one page a second
        try:
            club = parse_club(url, name, get(url))
        except OSError as err:
            report.append(f"page failed: {name}: {err}")
            continue
        if dry:
            print(f"--- {url}")
            print({k: v for k, v in club.items() if k != "_lines"})
            for line in club["_lines"][:60]:
                print("   ", line[:160])
            continue
        if club["_parts"] is None:
            report.append(f"no address: {name} ({url})")
            continue
        pos = geocode(*club["_parts"], cache, country="ch")
        if pos is None:
            report.append(f"address not found: {name}: {club['address']}")
            continue
        club.update({"_pos": pos, "_town": club["_parts"][2], "_where": "geocoded club address"})
        clubs.append(club)
    if dry:
        return 0
    save_geocode_cache(cache)
    waters, out = place(clubs, "ch", report)
    write_catalog(
        "ch-swissrowing",
        "Club data: Swiss Rowing (swissrowing.ch). Positions and waters: © OpenStreetMap contributors, ODbL",
        waters,
        out,
    )
    print("\n".join(sorted(report)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
