"""Takes a launch point suggested from the app (a GitHub issue with the label
"launch point suggestion", filed by cloudflare/suggestions) into the
hand-checked list, after the owner answered "/accept" on the issue.

It writes the point to data/catalogs/hand-checked.json (under the club's
country, keeping a clubhouse or address already checked there) and moves the
club's launch point in its catalog the way club_import.apply_hand_checked
does on the next import, so the next forecast run uses it. The workflow
"Accept launch point" (accept-launch-point.yml) runs it and opens a pull
request for the owner to merge.

    python3 scripts/accept_launch_point.py ISSUE_NUMBER < issue-body.md

"/accept 47.91234, 11.30012" takes that point instead of the suggested one
(the owner nudged it on the satellite view); the workflow passes it as
ACCEPT_AT.
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ROOT / "data" / "catalogs"
HAND_CHECKED = CATALOGS / "hand-checked.json"
BASE_LIST = ROOT / "data" / "locations.json"

# The lines cloudflare/suggestions/src/index.js writes (launchPointBody).
CLUB_LINE = re.compile(r"^- Club id: `([a-z0-9][a-z0-9-]{0,99})`$", re.M)
POINT_LINE = re.compile(r"^- Launch point: (-?\d{1,2}\.\d+), (-?\d{1,3}\.\d+)\b", re.M)
POINT = re.compile(r"^\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*$")


def parse(body: str) -> tuple[str, float, float]:
    """The club id and the suggested point from the issue's text."""
    body = body.replace("\r", "")
    club, point = CLUB_LINE.search(body), POINT_LINE.search(body)
    if not club or not point:
        raise ValueError("The issue has no \"- Club id:\" and \"- Launch point:\" lines from the app.")
    return club.group(1), *checked_point(point.group(1), point.group(2))


def parse_override(text: str) -> tuple[float, float] | None:
    """The point after "/accept", when the owner gave one."""
    text = text.strip()
    if not text:
        return None
    match = POINT.match(text)
    if not match:
        raise ValueError(f"\"/accept {text}\" is not a point; use \"/accept\" or \"/accept 47.91234, 11.30012\".")
    return checked_point(match.group(1), match.group(2))


def checked_point(lat: str, lon: str) -> tuple[float, float]:
    la, lo = float(lat), float(lon)
    if not (abs(la) <= 90 and abs(lo) <= 180):
        raise ValueError(f"{lat}, {lon} is not a point on Earth.")
    return round(la, 6), round(lo, 6)


def _write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def catalogs_with(club_id: str, root: Path = ROOT) -> list[Path]:
    """The country catalogs (de-drv.json, at-osm.json, ...) that list the club."""
    found = []
    for path in sorted((root / "data" / "catalogs").glob("??-*.json")):
        if any(c.get("id") == club_id for c in json.loads(path.read_text(encoding="utf-8")).get("clubs", [])):
            found.append(path)
    return found


def accept(club_id: str, lat: float, lon: float, issue: int, today: date | None = None, root: Path = ROOT) -> str:
    """Puts the point into the hand-checked list and the club's catalogs.
    Returns the club's name for the pull request."""
    today = today or date.today()
    base = json.loads((root / "data" / "locations.json").read_text(encoding="utf-8"))
    if any(c.get("id") == club_id for c in base.get("clubs", [])):
        raise ValueError(f"{club_id} is in data/locations.json, where the launch points are confirmed; change it there by hand.")
    paths = catalogs_with(club_id, root)
    if not paths:
        raise ValueError(f"No catalog lists the club {club_id}.")
    country = paths[0].name[:2]

    hand_path = root / "data" / "catalogs" / "hand-checked.json"
    hand = json.loads(hand_path.read_text(encoding="utf-8"))
    if club_id in hand.get("remove", []):
        raise ValueError(f"{club_id} is on the hand-checked list's \"remove\" list.")
    entry = hand.setdefault(country, {}).get(club_id, {})
    if "sameAs" in entry:
        raise ValueError(f"{club_id} takes its values from {entry['sameAs']} (\"sameAs\"); change that club instead.")
    # Keep a clubhouse and address checked earlier; the launch point is new.
    entry = {k: v for k, v in entry.items() if k in ("address", "club")}
    entry.update({"launchPoint": [lat, lon], "checked": today.isoformat(), "suggestion": f"#{issue}"})
    hand[country][club_id] = entry
    _write(hand_path, hand)

    name = club_id
    for path in paths:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        for club in catalog.get("clubs", []):
            if club.get("id") == club_id:
                name = club.get("name", name)
                # As club_import.apply_hand_checked writes it.
                club["launchPoint"] = {"lat": round(lat, 5), "lon": round(lon, 5),
                                       "precision": f"launch point checked by hand on the satellite view ({today.isoformat()})",
                                       "verified": False}
        _write(path, catalog)
    return name


def main() -> int:
    issue = int(sys.argv[1])
    try:
        club_id, lat, lon = parse(sys.stdin.read())
        override = parse_override(os.environ.get("ACCEPT_AT", ""))
        if override:
            lat, lon = override
        name = accept(club_id, lat, lon, issue)
    except ValueError as error:
        print(f"::error::{error}")
        out = os.environ.get("GITHUB_OUTPUT")
        if out:
            with open(out, "a", encoding="utf-8") as f:
                f.write(f"error={error}\n")
        return 1
    print(f"{name} ({club_id}): launch point {lat}, {lon}")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write(f"club={club_id}\nname={name}\nlat={lat}\nlon={lon}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
