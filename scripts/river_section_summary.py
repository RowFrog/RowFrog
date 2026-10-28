#!/usr/bin/env python3
"""Research only: sums up river_section_survey.py shard files (paths as arguments)."""

from __future__ import annotations

import json
import sys
from collections import Counter

EACH, TOTAL = 10.0, 20.0


def main() -> None:
    rows = [r for f in sys.argv[1:] for r in json.load(open(f))]
    ok = [r for r in rows if "error" not in r]
    clubs = lambda rs: sum(len(r["clubs"]) for r in rs)  # noqa: E731
    print(f"stretches {len(rows)} (clubs {clubs(rows)}); surveyed {len(ok)} (clubs {clubs(ok)}); errors {len(rows) - len(ok)}")
    kinds, dirs = Counter(), Counter()

    def side(r, key):
        b = r.get(key + "Barrier")
        stops = r.get(key + "Stops") or []
        if b and b[0] <= EACH:
            return "weir/lock within 10 km"
        first = stops[0] if stops else None
        if first and first[0] <= EACH and not (b and b[0] <= first[0]) and (first[1].startswith("joins") or first[1] == "line ends"):
            return "river ends or joins another within 10 km"
        if b:
            return "weir/lock 10-25 km"
        return "nothing within 25 km"

    for r in ok:
        up, down = side(r, "up"), side(r, "down")
        dirs[up] += len(r["clubs"])
        dirs[down] += len(r["clubs"])
        u = (r.get("upBarrier") or [None])[0]
        d = (r.get("downBarrier") or [None])[0]
        closed = lambda x: x != "weir/lock 10-25 km" and x != "nothing within 25 km"  # noqa: E731
        if closed(up) and closed(down):
            k = "A rule enough: both ends within 10 km"
        elif u is not None and d is not None and u + d <= TOTAL:
            k = "B weirs/locks both ways, together within 20 km"
        elif u is not None and d is not None:
            k = "C weirs/locks both ways within 25 km, together over 20 km"
        elif u is None and d is None and not closed(up) and not closed(down):
            k = "E no weir/lock either way within 25 km"
        else:
            k = "D open one way (no weir/lock within 25 km)"
        r["class"] = k
        r["sides"] = [up, down]
        kinds[k] += len(r["clubs"])
    print("DIRECTIONS (club-weighted):", dict(dirs))
    print("CLUBS PER CLASS:")
    for k in sorted(kinds):
        print(f"  {k}: {kinds[k]} clubs, {sum(1 for r in ok if r['class'] == k)} stretches")
    print("ROWS:")
    for r in sorted(ok, key=lambda r: (r["class"], r["lakeId"])):
        print(json.dumps({k: r.get(k) for k in ("class", "sides", "lakeId", "river", "country", "clubs", "at", "upBarrier", "downBarrier", "upReach", "downReach", "upStops", "downStops", "riverKm", "widthM", "snapM", "bridged")}, ensure_ascii=False))
    for r in rows:
        if "error" in r:
            print("ERROR", r["lakeId"], r["clubs"][0], r["error"])


if __name__ == "__main__":
    main()
