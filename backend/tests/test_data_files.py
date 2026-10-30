"""Checks on the hand-kept and imported data files in data/, so a bad catalog
import or a typo in a launch point fails here instead of showing a club in the
wrong place."""

import json
import math
from pathlib import Path

from rowfrog import api, outlines

DATA = Path(__file__).resolve().parents[2] / "data"
LOCATIONS = api._locations  # every club and water the API serves, catalogs included

# A launch point further than this from its water's outline is on the wrong water.
SHORE_KM = 1.5
# Known exceptions, each with why; remove an entry once its data is fixed.
FAR_FROM_OUTLINE = {
    # On the Main east of Offenbach, about 4 km past the end of the river-main-frankfurt section.
    "wassersportverein-1926-ev-offenbach-am-main-buergel",
}
# Outline files for no water in the catalogs (harbours and a river left over from earlier imports).
UNUSED_OUTLINES = {"fischerhafen", "hafen-friedrichshafen", "rodl"}


def _segment_km(p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    """Distance from p to the segment a-b, all (lon, lat), on a flat local map."""
    k = 111.195
    c = math.cos(math.radians(p[1]))
    px, py, ax, ay, bx, by = p[0] * k * c, p[1] * k, a[0] * k * c, a[1] * k, b[0] * k * c, b[1] * k
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = 0 if length2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length2))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def test_every_club_is_on_a_known_water_in_europe():
    for club in LOCATIONS.clubs.values():
        assert club.lake_id in LOCATIONS.lakes, f"{club.id}: unknown water {club.lake_id}"
        p = club.launch_point
        assert 35 < p.lat < 72 and -25 < p.lon < 45, f"{club.id}: launch point {p} is outside Europe"
    for lake in LOCATIONS.lakes.values():
        assert 35 < lake.center.lat < 72 and -25 < lake.center.lon < 45, f"{lake.id}: centre outside Europe"


def test_launch_points_lie_on_their_waters_outline():
    far = []
    for club in LOCATIONS.clubs.values():
        rings = outlines.load(club.lake_id)
        if not rings:
            continue
        p = (club.launch_point.lon, club.launch_point.lat)
        d = min(_segment_km(p, r[i], r[(i + 1) % len(r)]) for r in rings for i in range(len(r)))
        if d > SHORE_KM:
            far.append(f"{club.id} is {d:.1f} km from {club.lake_id}")
    unexpected = [f for f in far if f.split(" ")[0] not in FAR_FROM_OUTLINE]
    assert not unexpected, unexpected
    fixed = FAR_FROM_OUTLINE - {f.split(" ")[0] for f in far}
    assert not fixed, f"now on their water, take them off FAR_FROM_OUTLINE: {fixed}"


def test_outline_files_belong_to_known_waters():
    stems = {p.stem for p in (DATA / "outlines").glob("*.geojson")}
    assert stems - set(LOCATIONS.lakes) == UNUSED_OUTLINES
    for stem in stems:
        assert outlines.load(stem), f"{stem}.geojson has no outline"


def test_side_files_name_only_known_clubs_and_waters():
    depths = json.loads((DATA / "lake-depths.json").read_text())["meanDepthM"]
    assert set(depths) <= set(LOCATIONS.lakes), set(depths) - set(LOCATIONS.lakes)
    levels = json.loads((DATA / "lake-levels.json").read_text())["lakes"]
    assert set(levels) <= set(LOCATIONS.lakes), set(levels) - set(LOCATIONS.lakes)
    gauges = json.loads((DATA / "river-gauges.json").read_text())["clubs"]
    assert set(gauges) <= set(LOCATIONS.clubs), set(gauges) - set(LOCATIONS.clubs)
    for club_id in gauges:
        assert LOCATIONS.lakes[LOCATIONS.clubs[club_id].lake_id].kind == "river", f"{club_id} has a gauge but no river"
    overrides = json.loads((DATA / "river-section-overrides.json").read_text())
    for country, clubs in overrides.items():
        if country == "comment":
            continue
        assert set(clubs) <= set(LOCATIONS.clubs), set(clubs) - set(LOCATIONS.clubs)
    extra = json.loads((DATA / "catalogs" / "extra-sites.json").read_text())
    for country, sites in extra.items():
        if country == "comment":
            continue
        for site_id, site in sites.items():
            assert site_id in LOCATIONS.clubs, f"extra site {site_id} is not in the catalogs"
            assert site["of"] in LOCATIONS.clubs, f"extra site {site_id}: no club {site['of']}"


def test_catalog_ids_are_unique_within_each_file():
    for path in sorted((DATA / "catalogs").glob("*.json")):
        raw = json.loads(path.read_text())
        for key in ("lakes", "clubs"):
            ids = [x["id"] for x in raw.get(key, []) if isinstance(x, dict) and "id" in x]
            doubles = {i for i in ids if ids.count(i) > 1}
            assert not doubles, f"{path.name}: {key} listed twice: {sorted(doubles)}"
