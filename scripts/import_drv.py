#!/usr/bin/env python3
"""Import the clubs of the German Rowing Association (DRV) into the search.

Usage (from the repository root):
    python3 scripts/import_drv.py

Reads the club list at rudern.de/service/vereinssuche and each club's page,
geocodes the boathouse address with Nominatim, and finds the water it lies
on in OpenStreetMap. Writes data/catalogs/de-drv.json, which the app's search
offers next to the OSM catalog. Launch points count as unconfirmed:

- on a lake, the shore point nearest the boathouse, with the lake outline
  saved to data/outlines/ so waves can be estimated;
- on a river or canal, the boathouse itself (no waves are computed);
- elsewhere, the boathouse, under "Water near <town>".

Only club facts are kept (name, short name, abbreviation, DRV-ID, website,
kinds of rowing offered, boathouse address); no names, e-mails or phone
numbers of people. Geocoding results are cached in data/geocode.json so
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

from club_import import ROOT, geocode, get, load_geocode_cache, place, save_geocode_cache, write_catalog

BASE = "https://www.rudern.de"
LABELS = {
    "DRV-ID", "Kurzname", "Abkürzung", "Mitglieder", "Gründung", "Website", "E-Mail", "Telefon",
    "Sportliches Angebot", "Bootshaus", "Anschrift", "Vereine in der Umgebung", "Route planen",
}


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


def main() -> int:
    confirmed = json.loads((ROOT / "data" / "locations.json").read_text(encoding="utf-8"))
    confirmed_names = {c["name"] for c in confirmed["clubs"]}
    cache = load_geocode_cache()

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
    save_geocode_cache(cache)
    if failures > len(slugs) // 5:
        print("\n".join(report))
        sys.exit(f"{failures} clubs failed; keeping the old catalog")

    for c in clubs:
        street, plz, town = c.pop("_address")
        c["_town"] = town
        c["_where"] = "geocoded " + ("boathouse" if c.pop("boathouse") else "club address")
        c["id"] = re.sub(r"-e-?v$", "", c.pop("drvSlug"))
        c["address"] = ", ".join(filter(None, [street, f"{plz} {town}"]))
        c["source"] = "drv"
    waters, out_clubs = place(clubs, "de", report)
    write_catalog(
        "de-drv",
        "Club data: Deutscher Ruderverband e.V. (rudern.de). Positions and waters: © OpenStreetMap contributors, ODbL",
        waters,
        out_clubs,
    )
    print("\n".join(sorted(report)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
