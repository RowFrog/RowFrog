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

Overpass is asked only around the clubs themselves (MAX_M around each
launch point and checked clubhouse), CLUBS_PER_QUERY clubs per query, so
each query stays small. A query that fails is tried again after a pause;
clubs whose query still fails keep the place from the last run, so one bad
batch doesn't lose the rest.

With --report PATH it writes nothing to the places file: for every club
without a place it lists, as CSV, the OpenStreetMap features near it that
could be its place (rowing club names within REPORT_M, any named club or
sports place within REPORT_ANY_M), nearest first, so the matching rule can be
checked or loosened by hand:
    python3 scripts/osm_club_places.py --report osm-places-missing.csv

Data © OpenStreetMap contributors, ODbL.
"""

from __future__ import annotations

import csv
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
# How far the report looks around clubs without a place: rowing club names,
# and any named club or sports place.
REPORT_M = 1500.0
REPORT_ANY_M = 300.0
# How close a feature named with no rowing word must be, and then it must have the club's very name.
CLOSE_M = 300.0
# How many clubs one Overpass query looks around.
CLUBS_PER_QUERY = 20
# Tries per query, and the pause before the next try (seconds).
TRIES = 3
RETRY_AFTER = 60
# Queries failing in a row after which the rest are skipped (kept from the last run).
STOP_AFTER = 3
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
    # What the building is, in front of the club's name: "Clubhaus Neusser Ruderverein".
    "clubhaus", "clubheim", "vereinshaus", "vereinsheim", "sportheim", "jugendraum",
}


def plain(name: str) -> str:
    """Lower case without accents (ß as ss, ä as ae)."""
    text = name.lower().replace("ß", "ss").replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()


def words(name: str) -> set[str]:
    """The name's telling words: lower case, without accents, and a town's adjective
    as the town ("Breisacher" as "breisach", so it meets "Ruderverein Breisach")."""
    out = set()
    for p in re.findall(r"[a-z0-9]+", plain(name)):
        # "Ruder-Club" and "RuderClub" alike: split compounds that start with "ruder".
        if p.startswith("ruder") and p not in COMMON:
            p = p[len("ruder"):]
        if p and p not in COMMON:
            out.add(p[:-2] if p.endswith("er") and len(p) > 5 else p)
    return out


def likeness(club: str, feature: str) -> float:
    """How much two names say the same: shared telling words over the fewer of them."""
    a, b = words(club), words(feature)
    if not a or not b:
        return 0.0
    return len(a & b) / min(len(a), len(b))


def sameness(club: str, feature: str) -> float:
    """Shared telling words over the more of them: 1 only when both say the same.
    Of two clubs whose names fit a feature, the one it fits wholly keeps it
    ("Seeclub Zürich" over "Grasshopper Club Zürich")."""
    a, b = words(club), words(feature)
    if not a or not b:
        return 0.0
    return len(a & b) / max(len(a), len(b))


# Features named for another sport belong to another club, unless the club's own name has that sport
# too ("Segelclub Ägeri" is not "Ruderclub Ägeri"; "Strandbad Sursee" is not "Seeclub Sursee").
OTHER_SPORT = re.compile(r"segel|yacht|kanu|kajak|kayak|schwimm|tauch|golf|surf|wasserski|voile|vela|sail|swim"
                         r"|tennis|fussball|angel|fischer|dlrg|strandbad|freibad|lido|beach")


def distance_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    dy = math.radians(b[0] - a[0]) * 6_371_000
    dx = math.radians(b[1] - a[1]) * 6_371_000 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)


def candidates(club: dict, features: list[dict]) -> list[tuple[tuple[float, float], float, dict]]:
    """((likeness, sameness), distance, feature) for the features named like the club within MAX_M.
    `club` has "name", "shortName" and "points" (launch point, checked clubhouse)."""
    out = []
    names = [club["name"], club.get("shortName") or club["name"]]
    for f in features:
        at = (f["lat"], f["lon"])
        near = min(distance_m(at, p) for p in club["points"])
        if near > MAX_M:
            continue
        if (OTHER_SPORT.search(plain(f["name"])) and not re.search(CLUB_NAME, f["name"])
                and not OTHER_SPORT.search(plain(club["name"]))):
            continue
        like = max(likeness(n, f["name"]) for n in names)
        same = max(sameness(n, f["name"]) for n in names)
        if shares_only_the_town(club, f["name"]):
            continue
        # Named with no rowing word and not tagged as rowing (fetched only close by): only the club's
        # full name, "Wassersportverein" and all ("Wassersportverein Remagen" is not "Ruder-Gesellschaft Remagen").
        if not f.get("rowing", True) and (near > CLOSE_M or not any(names_alike(n, f["name"]) for n in names)):
            continue
        if like >= 0.5:
            out.append(((like, same), near, f))
    return out


# Words for the building or site in front of a club's name ("Marina Merseburger Rudergesellschaft").
SITE_WORDS = {"marina", "anleger", "anleg", "steg", "gelaende", "bootshafen", "sportanlage", "ruderheim", "bootshalle", "see"}
# What kind of club a name says it is.
KINDS = {"club": r"club|klub", "verein": r"verein", "gesellschaft": r"gesellschaft", "gemeinschaft": r"gemeinschaft",
         "riege": r"riege", "vereinigung": r"vereinigung"}


def kinds(name: str) -> set[str]:
    text = plain(name)
    return {k for k, pattern in KINDS.items() if re.search(pattern, text)}


def shares_only_the_town(club: dict, feature: str) -> bool:
    """Whether the names share only the club's town and then part ways: another word that
    tells a club apart ("Bremer Sport-Club" and "Bremer Ruder Club Hansa", "Grasshopper Club
    Zürich" and "Seeclub Zürich") or another kind of club ("Bonner Ruder-Gesellschaft" and
    "Bonner Ruder-Verein 1882"). Years, short words (abbreviations) and site words don't count
    ("Ruderverein Esslingen e.V. von 1906", "Ruderclub Kaufering RCLK", "Anleger Verdener Ruderverein")."""
    town = club.get("town", set())
    a, f = words(club["name"]), words(feature)
    shared = a & f
    in_town = lambda w: any(w == t or (len(w) >= 4 and w[:4] == t[:4]) for t in town)  # "brem" and "bremen"
    if not shared or not all(in_town(w) for w in shared):
        return False
    # One name holds the other whole: the same club, written longer or shorter ("Ruder-Club
    # Wittenberg e.V. E. Tilch", "Möllner Ruder Club", "Bootshaus der Dormagener Rudergesellschaft").
    c_all, f_all = spelled_out(club["name"]), spelled_out(feature)
    if c_all and f_all and (c_all <= f_all or f_all <= c_all):
        return False
    if a == f:
        # Both say only the town: then the rest must say the same ("Ruderverein Torgau e.V." and
        # "Torgauer Ruderverein", "Seeclub Thun" and "See Club Thun"; not "Ruderclub Zürich" and "Seeclub Zürich").
        return rest_of(club["name"], town) != rest_of(feature, town)
    telling = {w for w in a ^ f if len(w) >= 5 and not w.isdigit() and not in_town(w) and w not in SITE_WORDS}
    # A short word only the feature has is another club's initials unless it spells the club's
    # ("Ruderclub Kaufering RCLK" fits "Ruder Club am Lech Kaufering"; "BSRK" does not fit "Ruder-Club-Havel").
    abbreviations = {w for w in f - a if 3 <= len(w) <= 4 and w.isalpha() and w not in SITE_WORDS}
    telling |= {w for w in abbreviations if not spells(w, club["name"])}
    # The club's own long words the feature writes as initials ("VWM" for "Volkstümlicher Wassersport Mannheim").
    if any(spells(w, club["name"]) for w in abbreviations):
        telling -= a - f
    other_kind = kinds(club["name"]) and kinds(feature) and not kinds(club["name"]) & kinds(feature)
    return bool(telling or other_kind)


def spells(abbreviation: str, name: str) -> bool:
    """Whether the letters are the name's initials in order ("rve" in "Ruder-Verein Erlangen";
    "Ruderverein" counts as "r" and "v")."""
    parts = re.findall(r"[a-z0-9]+", plain(name))
    # Or one long word's letters, from its first ("USC" in "Universitätssportclub").
    if any(len(p) > 8 and p[0] == abbreviation[0] and all(ch in iter(p[1:]) for ch in abbreviation[1:]) for p in parts):
        return True
    initials = []
    for p in parts:
        if p.startswith("ruder") and len(p) > 5:
            initials += ["r", p[5]]
        else:
            initials.append(p[0])
    it = iter(initials)
    return all(ch in it for ch in abbreviation)


# Words a place's name adds to the club's: its building, "e.V.", little words.
FILLER = {"e", "v", "ev", "r", "eingetragener", "bootshaus", "boathouse", "clubhaus", "clubheim", "vereinshaus",
          "vereinsheim", "sportheim", "der", "die", "das", "des", "dem", "den", "von", "vom", "vorm", "am", "an",
          "a", "d", "im", "zu", "und"}


def spelled_out(name: str) -> set[str]:
    """All of a name's words but its building, years and little words, "Ruder-" compounds split
    ("Ruderclub" as "Ruder Club"), stemmed as in `words`."""
    out = set()
    for p in re.findall(r"[a-z0-9]+", plain(name)):
        if p in FILLER or p.isdigit():
            continue
        if p.startswith("ruder") and len(p) > 5:
            out.add("ruder")
            p = p[5:]
        out.add(p[:-2] if p.endswith("er") and len(p) > 5 else p)
    return out


def rest_of(name: str, town: set[str]) -> str:
    """A name without its town, building, legal form, years and site words, run together."""
    out = []
    for p in re.findall(r"[a-z0-9]+", plain(name)):
        p = p[:-2] if p.endswith("er") and len(p) > 5 else p
        if p in town or p in SITE_WORDS or p.isdigit() or p in FILLER:
            continue
        out.append(p)
    return "".join(out)


def full_words(name: str) -> set[str]:
    """All of a name's words but "e.V." and years, stemmed as in `words`."""
    out = set()
    for p in re.findall(r"[a-z0-9]+", plain(name)):
        if p in {"e", "v", "ev", "r", "eingetragener"} or p.isdigit():
            continue
        out.add(p[:-2] if p.endswith("er") and len(p) > 5 else p)
    return out


def names_alike(club: str, feature: str) -> bool:
    """The feature's name is the club's, give or take "e.V." and a year."""
    return bool(full_words(feature)) and full_words(feature) == full_words(club)


def match(clubs: list[dict], features: list[dict]) -> dict[str, dict]:
    """Each club's place: best names first (likeness, then sameness), then the nearer.
    A feature another club matched better stays that club's ("Münchener Ruder-Club"
    does not take the "Münchener Ruderclub Bayern" when its own feature is missing,
    "Grasshopper Club Zürich" not the "Seeclub Zürich"); clubs that match a feature
    equally well share it, and so does a club whose name holds the feature's whole name
    (the school crew "SRR Domschulruderclub Schleswig" at the "Domschulruderclub Schleswig")."""
    names = {c["id"]: c["name"] for c in clubs}
    pairs = sorted(((like, near, c["id"], f) for c in clubs for like, near, f in candidates(c, features)),
                   key=lambda x: (-x[0][0], -x[0][1], x[1], x[2]))
    places: dict[str, dict] = {}
    taken: dict[str, tuple[float, float]] = {}  # feature -> (likeness, sameness) of the club that took it
    for like, _near, club_id, f in pairs:
        if club_id in places:
            continue
        held = taken.get(f["osm"], like)
        if held > like and not (held[0] == like[0] and spelled_out(f["name"]) <= spelled_out(names[club_id])):
            continue
        places[club_id] = f
        taken[f["osm"]] = like
    return places


def kind(tags: dict) -> str:
    """The tags that say what a feature is, e.g. "sport=rowing leisure=sports_centre"."""
    return " ".join(f"{k}={tags[k]}" for k in ("sport", "club", "leisure", "building", "amenity") if k in tags)


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
        rowing = "rowing" in tags.get("sport", "") or bool(re.search(CLUB_NAME, name))
        out.append({"name": name, "lat": round(c["lat"], 6), "lon": round(c["lon"], 6), "osm": f"{e['type']}/{e['id']}",
                    "rowing": rowing, "kind": kind(tags)})
    return out


def query(clubs: list[dict], report: bool = False) -> list[dict]:
    """The rowing club features within MAX_M of these clubs' points; for the
    report, within REPORT_M, plus any named club or sports place within REPORT_ANY_M."""
    parts = []
    for club in clubs:
        for lat, lon in club["points"]:
            near = f"(around:{REPORT_M if report else MAX_M:.0f},{lat:.5f},{lon:.5f})"
            parts += [
                f'nwr["sport"="rowing"]["name"]{near};',
                f'nwr["club"]["name"~"{CLUB_NAME}"]{near};',
                f'nwr["leisure"]["name"~"{CLUB_NAME}"]{near};',
                f'nwr["building"]["name"~"{CLUB_NAME}"]{near};',
            ]
            # Clubs named with no rowing word ("Seeclub Biel", "Société Nautique Etoile Bienne").
            close = f"(around:{CLOSE_M:.0f},{lat:.5f},{lon:.5f})"
            parts += [f'nwr["club"]["name"]{close};', f'nwr["sport"]["name"]{close};',
                      f'nwr["leisure"~"sports_centre|marina"]["name"]{close};']
            if report:
                close = f"(around:{REPORT_ANY_M:.0f},{lat:.5f},{lon:.5f})"
                parts += [
                    f'nwr["club"]["name"]{close};',
                    f'nwr["leisure"~"sports_centre|sports_hall|pitch|marina|slipway"]["name"]{close};',
                    f'nwr["sport"]["name"]{close};',
                ]
    q = "[out:json][timeout:90];\n(\n" + "\n".join(parts) + "\n);\nout center tags;"
    result = overpass(q, timeout=120)
    if "remark" in result:  # timeouts and memory limits, with a partial result
        raise OSError(f"Overpass: {result['remark']}")
    return result["elements"]


def query_with_retries(clubs: list[dict], tries: int = TRIES, pause: float = RETRY_AFTER,
                       report: bool = False) -> list[dict] | None:
    """`query`, tried again after a pause; None when every try failed."""
    for attempt in range(1, tries + 1):
        try:
            return query(clubs, report) if report else query(clubs)
        except OSError as error:
            print(f"    try {attempt} of {tries} failed: {error}")
            if attempt < tries:
                time.sleep(pause)
    return None


def town_of(address: str) -> set[str]:
    """The town's words from an address like "Uferstraße 16, 50996 Köln-Rodenkirchen"."""
    found = re.search(r"\b\d{4,5}\s+(.+)$", address or "")
    return words(found.group(1)) if found else set()


def clubs_to_place() -> list[dict]:
    from rowfrog import locations

    out = []
    for c in locations.load().clubs.values():
        points = [(c.launch_point.lat, c.launch_point.lon)]
        if c.clubhouse:
            points.append((c.clubhouse.lat, c.clubhouse.lon))
        out.append({"id": c.id, "name": c.name, "shortName": c.short_name, "points": points, "town": town_of(c.address)})
    return out


def old_places() -> dict[str, dict]:
    if not OUT.exists():
        return {}
    return json.loads(OUT.read_text(encoding="utf-8")).get("places", {})


def report_rows(clubs: list[dict], features: list[dict]) -> list[dict]:
    """Per club, up to three features nearest first (or one empty row): what
    could be its place, and why the matching left it out."""
    rows = []
    for club in clubs:
        near = sorted(((min(distance_m((f["lat"], f["lon"]), p) for p in club["points"]), f) for f in features),
                      key=lambda x: x[0])
        near = [(d, f) for d, f in near if d <= REPORT_M][:3]
        base = {"club": club["id"], "club name": club["name"], "lat": club["points"][0][0], "lon": club["points"][0][1]}
        if not near:
            rows.append({**base, "rank": "", "osm name": "", "osm": "", "what": "", "metres": "", "likeness": "",
                         "why not": "nothing named like a rowing club within 1.5 km"})
        for rank, (d, f) in enumerate(near, 1):
            like = max(likeness(club["name"], f["name"]), likeness(club.get("shortName") or "", f["name"]))
            why = ("further than 700 m" if d > MAX_M else "name shares no telling word" if like == 0
                   else "name too different" if like < 0.5
                   else "another club or sport (only the town alike, or no rowing word and not its very name)"
                   if not candidates(club, [f]) else "taken by another club that matches it better")
            rows.append({**base, "rank": rank, "osm name": f["name"], "osm": f"https://www.openstreetmap.org/{f['osm']}",
                         "what": f.get("kind", ""), "metres": round(d), "likeness": round(like, 2), "why not": why})
    return rows


def report(path: Path) -> int:
    have = old_places()
    clubs = sorted((c for c in clubs_to_place() if c["id"] not in have), key=lambda c: c["points"][0])
    batches = [clubs[i:i + CLUBS_PER_QUERY // 2] for i in range(0, len(clubs), CLUBS_PER_QUERY // 2)]
    print(f"{len(clubs)} clubs without a place, {len(batches)} queries")
    features: dict[str, dict] = {}
    missed = 0
    for n, batch in enumerate(batches, 1):
        elements = query_with_retries(batch, report=True)
        if elements is None:
            missed += len(batch)
        else:
            for f in features_from(elements):
                features[f["osm"]] = f
        print(f"  query {n} of {len(batches)}: {len(features)} features so far")
        time.sleep(3)
    rows = report_rows(clubs, list(features.values()))
    with path.open("w", newline="", encoding="utf-8") as out:
        writer = csv.DictWriter(out, fieldnames=list(rows[0]) if rows else ["club"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows)} rows for {len(clubs)} clubs to {path}" + (f" ({missed} clubs not looked up)" if missed else ""))
    return 1 if missed else 0


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--report":
        return report(Path(sys.argv[2]))
    clubs = sorted(clubs_to_place(), key=lambda c: c["points"][0])  # neighbours share a query
    batches = [clubs[i:i + CLUBS_PER_QUERY] for i in range(0, len(clubs), CLUBS_PER_QUERY)]
    print(f"{len(clubs)} clubs in {len(batches)} queries")
    features: dict[str, dict] = {}
    failed: set[str] = set()
    in_a_row = 0
    for n, batch in enumerate(batches, 1):
        # Overpass down altogether: stop instead of waiting through every batch.
        elements = query_with_retries(batch) if in_a_row < STOP_AFTER else None
        in_a_row = in_a_row + 1 if elements is None else 0
        if elements is None:
            failed |= {c["id"] for c in batch}
        else:
            for f in features_from(elements):
                features[f["osm"]] = f
        print(f"  query {n} of {len(batches)}: {len(features)} features so far, {len(failed)} clubs not looked up")
        time.sleep(3)  # be gentle with the public Overpass servers
    if len(failed) == len(clubs):
        sys.exit("every query failed; keeping the old file")

    looked_up = [c for c in clubs if c["id"] not in failed]
    places = {club_id: {"at": [f["lat"], f["lon"]], "name": f["name"], "osm": f["osm"]}
              for club_id, f in match(looked_up, list(features.values())).items()}
    # Clubs whose query failed keep what the last run found.
    kept = {k: v for k, v in old_places().items() if k in failed}
    places = dict(sorted({**kept, **places}.items()))
    print(f"{len(places)} of {len(clubs)} clubs have a place in OpenStreetMap"
          + (f" ({len(kept)} kept from the last run, {len(failed)} clubs not looked up)" if failed else ""))
    if len(places) < len(looked_up) // 4:
        sys.exit("too few places found; keeping the old file")
    OUT.write_text(json.dumps({
        "comment": "Each club's own place in OpenStreetMap (scripts/osm_club_places.py): where the map draws the "
                   "club's name. The website puts the club's pin there once zoomed in, unless a clubhouse checked "
                   "by hand lies more than 80 m away.",
        "source": "© OpenStreetMap contributors, ODbL",
        "updated": datetime.now(UTC).date().isoformat(),
        "places": places,
    }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
