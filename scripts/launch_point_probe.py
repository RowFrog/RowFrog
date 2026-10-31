"""Which water lies at each launch point that is not on its own water's outline.

For every club whose launch point is more than 25 m outside its water's
outline, or whose water has no outline, asks OpenStreetMap (Overpass) for the
waters, harbours and basins within 400 m, with their names and distances. The
report sorts the clubs into: just off the bank (snap onto the water), on
another water (wrong water or a basin/harbour to add), or nothing found.
Research only: nothing is stored. Writes the report to stdout and, on GitHub,
to the job summary, plus launch-points.json for the run's download.
"""

from __future__ import annotations

import json
import math
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, "backend")
sys.path.insert(0, "scripts")
from fetch_lake_outline import overpass  # noqa: E402
from rowfrog import api, outlines  # noqa: E402

AROUND_M = 400
EDGE_M = 25


def inside(pt, rings) -> bool:
    x, y = pt
    c = False
    for r in rings:
        for i in range(len(r)):
            (x1, y1), (x2, y2) = r[i], r[i - 1]
            if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                c = not c
    return c


def seg_m(p, a, b) -> float:
    k = 111_195
    c = math.cos(math.radians(p[1]))
    px, py, ax, ay, bx, by = p[0] * k * c, p[1] * k, a[0] * k * c, a[1] * k, b[0] * k * c, b[1] * k
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def misfits() -> list[dict]:
    out = []
    locs = api._locations
    for c in locs.clubs.values():
        lake = locs.lakes[c.lake_id]
        rings = outlines.load(c.lake_id)
        p = (c.launch_point.lon, c.launch_point.lat)
        if rings:
            if inside(p, rings):
                continue
            d = min(seg_m(p, r[i], r[i - 1]) for r in rings for i in range(len(r)))
            if d <= EDGE_M:
                continue
        else:
            d = None
        out.append({"club": c.id, "name": c.short_name or c.name, "water": c.lake_id, "waterName": lake.name,
                    "kind": lake.kind, "lat": p[1], "lon": p[0], "outsideM": None if d is None else round(d)})
    return out


def nearby(lat: float, lon: float) -> list[dict]:
    dl = AROUND_M / 111_195 * 1.5
    dn = dl / math.cos(math.radians(lat))
    box = f"{lat - dl},{lon - dn},{lat + dl},{lon + dn}"
    a = f"around:{AROUND_M},{lat},{lon}"
    q = f"""
    [out:json][timeout:40];
    (
      way({a})["natural"="water"];
      relation({a})["natural"="water"];
      way({a})["waterway"~"^(river|canal|riverbank|dock|stream)$"];
      way({a})["landuse"="basin"];
      way({a})["harbour"];
      relation({a})["harbour"];
      way({a})["leisure"="marina"];
    );
    out tags geom({box});
    """
    found = []
    for el in overpass(q, timeout=60).get("elements", []):
        tags = el.get("tags", {})
        name = (tags.get("name") or "").lower()
        if tags.get("water") in ("fountain", "pond", "reflecting_pool") or "brunnen" in name or tags.get("amenity") == "fountain":
            continue
        lines = []
        if "geometry" in el:
            lines.append([(g["lon"], g["lat"]) for g in el["geometry"] if g])
        for m in el.get("members", []):
            if m.get("geometry"):
                lines.append([(g["lon"], g["lat"]) for g in m["geometry"] if g])
        d = min((seg_m((lon, lat), ln[i], ln[i + 1]) for ln in lines for i in range(len(ln) - 1)), default=None)
        polys = [ln for ln in lines if len(ln) > 3 and ln[0] == ln[-1]]
        if polys and inside((lon, lat), polys):
            d = 0
        kind = (tags.get("waterway") or tags.get("water") or tags.get("harbour") and "harbour"
                or tags.get("landuse") or tags.get("leisure") or tags.get("natural"))
        found.append({"osm": f"{el['type']}/{el['id']}", "name": tags.get("name"), "kind": kind,
                      "distanceM": None if d is None else round(d)})
    found.sort(key=lambda f: (f["distanceM"] is None, f["distanceM"] or 0))
    return found


def verdict(club: dict, found: list[dict]) -> str:
    named = [f for f in found if f["name"] and f["distanceM"] is not None]
    if not named:
        return "nothing named nearby"
    own = club["waterName"].lower()
    first = named[0]
    mine = [f for f in named if f["name"].lower() in own or own in f["name"].lower()]
    if mine and (mine[0] is first or mine[0]["distanceM"] <= 150):
        return f"own water nearby: snap onto it ({mine[0]['distanceM']} m)"
    if first["kind"] in ("harbour", "basin", "dock", "marina", "yes") or "hafen" in first["name"].lower():
        return f"harbour/basin: {first['name']}"
    return f"other water: {first['name']}"


def main() -> int:
    clubs = misfits()
    print(f"{len(clubs)} launch points off their water's outline or without one")
    shard, shards = (int(x) for x in os.environ.get("SHARD", "0/1").split("/"))
    clubs = clubs[shard::shards]
    print(f"shard {shard}/{shards}: {len(clubs)} clubs")
    for i, club in enumerate(clubs):
        try:
            club["nearby"] = nearby(club["lat"], club["lon"])[:6]
        except OSError as e:
            club["nearby"] = []
            club["error"] = str(e)[:200]
        club["verdict"] = "Overpass failed" if "error" in club else verdict(club, club["nearby"])
        print(f"[{i + 1}/{len(clubs)}] {club['club']}: {club['verdict']}", flush=True)
        Path("launch-points.json").write_text(json.dumps(clubs[: i + 1], ensure_ascii=False, indent=1), encoding="utf-8")
        time.sleep(1.5)
    Path("launch-points.json").write_text(json.dumps(clubs, ensure_ascii=False, indent=1), encoding="utf-8")
    lines = ["| Club | Water | Off by (m) | Verdict | Nearest waters (m) |", "|---|---|---|---|---|"]
    for c in sorted(clubs, key=lambda c: (c["verdict"].split(":")[0], -(c["outsideM"] or 10_000))):
        near = "; ".join(f"{f['name'] or '?'} ({f['kind']}) {f['distanceM']}" for f in c["nearby"][:4])
        lines.append(f"| {c['name']} | {c['waterName']} | {c['outsideM'] if c['outsideM'] is not None else 'no outline'} "
                     f"| {c['verdict']} | {near} |")
    report = "\n".join(lines)
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as f:
            f.write(f"## Launch points off their water ({len(clubs)})\n\n{report}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
