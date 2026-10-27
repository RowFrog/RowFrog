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
    kinds = Counter()
    for r in ok:
        up, down = r.get("upBarrier"), r.get("downBarrier")
        u = up[0] if up else None
        d = down[0] if down else None
        if u is not None and d is not None and u <= EACH and d <= EACH:
            k = "A both ends at a weir/lock within 10 km"
        elif u is not None and d is not None and u + d <= TOTAL:
            k = "B both weirs/locks within 20 km in total, one beyond 10 km"
        elif u is not None and d is not None and u + d <= 40:
            k = "C both weirs/locks within 40 km in total"
        elif u is None and d is None:
            k = "E no weir/lock either way within 40 km"
        else:
            k = "D weir/lock only one way within 40 km"
        r["class"] = k
        kinds[k] += len(r["clubs"])
    print("CLUBS PER CLASS:")
    for k in sorted(kinds):
        print(f"  {k}: {kinds[k]} clubs, {sum(1 for r in ok if r['class'] == k)} stretches")
    print("ROWS:")
    for r in sorted(ok, key=lambda r: (r["class"], r["lakeId"])):
        print(json.dumps({k: r.get(k) for k in ("class", "lakeId", "river", "country", "clubs", "at", "upBarrier", "downBarrier", "upReach", "downReach", "upStops", "downStops", "riverKm", "widthM", "snapM", "bridged")}, ensure_ascii=False))
    for r in rows:
        if "error" in r:
            print("ERROR", r["lakeId"], r["clubs"][0], r["error"])


if __name__ == "__main__":
    main()
