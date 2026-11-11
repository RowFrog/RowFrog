#!/usr/bin/env python3
"""Finds each club's own place in OpenStreetMap: the feature whose name the
map draws for the club, so the website can put the club's pin on it once
zoomed in (the owner's option A, as the app does with Apple Maps places).

Usage (from the repository root, needs the backend installed):
    python3 scripts/osm_club_places.py

For every club in the app's lists it looks at the rowing club features in
OpenStreetMap (tagged sport=rowing, or a club or leisure place named like a
rowing club) within MAX_M of the club's launch point or checked clubhouse,
and takes the one whose name shares the most words with the club's name,
leaving out words every club has ("Ruder", "Club", "e.V."). A club with no
such feature has no place; the website then keeps the clubhouse checked by
hand, as before. Writes data/catalogs/osm-places.json; the server sends it
as each club's `mapPlace`.

The clubs are looked up one 1 x 1 degree square at a time, a few squares
per Overpass query, so no query covers a whole country.

Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import json
import math
import re
import sys
import time
import unicodedata
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fetch_lake_outline import overpass

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "catalogs" / "osm-places.json"
# How far a club's map place may lie from its launch point or checked clubhouse.
MAX_M = 700.0
# How many 1 x 1 degree squares one Overpass query covers.
SQUARES_PER_QUERY = 6
# As import_osm_clubs.CLUB_NAME, plus the Dutch, Danish and Polish words.
CLUB_NAME = "[Rr]uder|[Rr]owing|[Aa]viron|[Cc]anott|[Rr]oei|[Rr]o[ -]?klub|[Ww]io[sś]l"
NOT_CLUBS = re.compile(
    r"(?i)verleih|vermietung|rental|location|noleggio|shop|spielplatz|brunnen|ruderal|throwing|^hafen"
)
# Words in many clubs' names, which say nothing about which club it is.
COMMON = {
    "ruder", "rudern", "ruderclub", "ruderverein", "rudergesellschaft", "rudergemeinschaft", "ruderriege",
    "rudersport", "ruderabteilung", "ruderer", "rudervereinigung", "ruderzentrum", "wassersport", "wassersportverein",
    "club", "klub", "verein", "gesellschaft", "gemeinschaft", "vereinigung", "abteilung", "riege", "sport", "sportverein",
    "rc", "rv", "rg", "rgm", "wsv", "sv", "tv", "tsv", "e", "v", "ev", "eingetragener", "von", "vom", "und", "der", "die",
    "das", "des", "dem", "den", "am", "an", "auf", "im", "in", "zu", "zum", "zur", "bei", "fuer", "mit", "a", "the", "of",
    "rowing", "boat", "boathouse", "bootshaus", "aviron", "nautique", "societe", "canottieri", "societa", "di",
    "roeivereniging", "roeiclub", "roklub", "seeclub", "1", "st",
}


def words(name: str) -> set[str]:
    """The name's telling words, lower case, without accents (ß as ss, ä as ae)."""
    text = name.lower().replace("ß", "ss").replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    # "Ruder-Club" and "RuderClub" alike: split compounds that start with "ruder".
    parts = re.findall(r"[a-z0-9]+", text)
    out = set()
    for p in parts:
        if p.startswith("ruder") and p not in COMMON:
            p = p[len("ruder"):]
        if p and p not in COMMON:
            out.add(p)
    return out


def likeness(club: str, feature: str) -> float:
    """How much two names say the same: shared telling words over the fewer of them."""
    a, b = words(club), words(feature)
    if not a or not b:
        return 0.0
    return len(a & b) / min(len(a), len(b))


def distance_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    dy = math.radians(b[0] - a[0]) * 6_371_000
    dx = math.radians(b[1] - a[1]) * 6_371_000 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)


def candidates(club: dict, features: list[dict]) -> list[tuple[float, float, dict]]:
    """(likeness, distance, feature) for the features named like the club within MAX_M.
    `club` has "name", "shortName" and "points" (launch point, checked clubhouse)."""
    out = []
    for f in features:
        at = (f["lat"], f["lon"])
        near = min(distance_m(at, p) for p in club["points"])
        if near > MAX_M:
            continue
        like = max(likeness(club["name"], f["name"]), likeness(club.get("shortName") or "", f["name"]))
        if like >= 0.5:
            out.append((like, near, f))
    return out


def match(clubs: list[dict], features: list[dict]) -> dict[str, dict]:
    """Each club's place: best names first, then the nearer. A feature another club
    matched better stays that club's ("Münchener Ruder-Club" does not take the
    "Münchener Ruderclub Bayern" when its own feature is missing); clubs that match
    a feature equally well share it (a school crew at a club's boathouse)."""
    pairs = sorted(((like, near, c["id"], f) for c in clubs for like, near, f in candidates(c, features)),
                   key=lambda x: (-x[0], x[1], x[2]))
    places: dict[str, dict] = {}
    taken: dict[str, float] = {}  # feature -> likeness of the club that took it
    for like, _near, club_id, f in pairs:
        if club_id in places or taken.get(f["osm"], like) > like:
            continue
        places[club_id] = f
        taken[f["osm"]] = like
    return places


def features_from(elements: list[dict]) -> list[dict]:
    out = []
    for e in elements:
        tags = e.get("tags", {})
        name = tags.get("name", "")
        if not name or NOT_CLUBS.search(name) or tags.get("shop") or tags.get("amenity") == "boat_rental":
            continue
        c = e.get("center") or e
        if "lat" not in c:
            continue
        out.append({"name": name, "lat": round(c["lat"], 6), "lon": round(c["lon"], 6), "osm": f"{e['type']}/{e['id']}"})
    return out


def query(squares: list[tuple[int, int]]) -> list[dict]:
    parts = []
    for lat, lon in squares:
        box = f"({lat},{lon},{lat + 1},{lon + 1})"
        parts += [
            f'nwr["sport"="rowing"]["name"]{box};',
            f'nwr["name"~"{CLUB_NAME}"]["club"]{box};',
            f'nwr["name"~"{CLUB_NAME}"]["leisure"]{box};',
            f'nwr["name"~"{CLUB_NAME}"]["building"]{box};',
        ]
    q = "[out:json][timeout:180];\n(\n" + "\n".join(parts) + "\n);\nout center tags;"
    result = overpass(q, timeout=200)
    if "remark" in result:  # timeouts and memory limits, with a partial result
        raise OSError(f"Overpass: {result['remark']}")
    return result["elements"]


def clubs_to_place() -> list[dict]:
    from rowfrog import locations

    out = []
    for c in locations.load().clubs.values():
        points = [(c.launch_point.lat, c.launch_point.lon)]
        if c.clubhouse:
            points.append((c.clubhouse.lat, c.clubhouse.lon))
        out.append({"id": c.id, "name": c.name, "shortName": c.short_name, "points": points})
    return out


def main() -> int:
    clubs = clubs_to_place()
    squares = sorted({(math.floor(p[0]), math.floor(p[1])) for c in clubs for p in c["points"]})
    print(f"{len(clubs)} clubs in {len(squares)} squares")
    features: dict[str, dict] = {}
    for i in range(0, len(squares), SQUARES_PER_QUERY):
        batch = squares[i:i + SQUARES_PER_QUERY]
        for f in features_from(query(batch)):
            features[f["osm"]] = f
        print(f"  squares {i + 1}-{i + len(batch)}: {len(features)} features so far")
        time.sleep(5)  # be gentle with the public Overpass servers
    found = list(features.values())

    places = {club_id: {"at": [f["lat"], f["lon"]], "name": f["name"], "osm": f["osm"]}
              for club_id, f in sorted(match(clubs, found).items())}
    print(f"{len(places)} of {len(clubs)} clubs have a place in OpenStreetMap")
    if len(places) < len(clubs) // 4:
        sys.exit("too few places found; keeping the old file")
    OUT.write_text(json.dumps({
        "comment": "Each club's own place in OpenStreetMap (scripts/osm_club_places.py): where the map draws the "
                   "club's name. The website puts the club's pin there once zoomed in, unless a clubhouse checked "
                   "by hand lies more than 80 m away.",
        "source": "© OpenStreetMap contributors, ODbL",
        "updated": datetime.now(UTC).date().isoformat(),
        "places": places,
    }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
