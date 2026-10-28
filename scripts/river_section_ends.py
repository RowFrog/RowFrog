#!/usr/bin/env python3
"""Research only: sums up an 80 km run of river_section_survey.py (survey.json).

For every stretch and direction: the next weir or lock (up to 80 km), where
the river ends or joins a bigger one, the larger rivers joining or branching
off, and the harbours passed. Then applies the proposed rule and prints how
long the sections get:
  1. to the next weir or lock, if it is within REACH_KM;
  2. else to the first hard end beyond MIN_KM: the river's mouth, a big river
     joining or branching off (BIG_KM of named line in the box), a big
     harbour (BIG_HARBOUR_KM2), or the line ending;
  3. else a cap: CAP_UP_KM upstream, CAP_DOWN_KM downstream.
"""

from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict

REACH_KM, MIN_KM = 25.0, 3.0
BIG_KM, BIG_HARBOUR_KM2 = 40, 0.1
CAP_UP_KM, CAP_DOWN_KM = 12.0, 8.0
BARRIERS = ("weir", "dam", "lock_gate", "waterfall", "lock")


def side(r, key, cap):
    b = r.get(key + "Barrier")
    if b and b[0] <= REACH_KM:
        return b[0], "weir/lock", b[1]
    hard = []
    for d, label, extra in r.get(key + "Events") or []:
        if d < MIN_KM or d > REACH_KM:
            continue
        if label.startswith("harbour") and (extra or 0) >= BIG_HARBOUR_KM2:
            hard.append((d, "harbour", f"{label} {extra} km²"))
        elif not label.startswith("harbour") and (extra or 0) >= BIG_KM:
            hard.append((d, "river joins/branches", f"{label} ({extra} km)"))
    for d, label in r.get(key + "Stops") or []:
        if MIN_KM <= d <= REACH_KM and label.startswith("joins"):
            hard.append((d, "river ends", label))
    if hard:
        return min(hard)
    return cap, "cap", ""


def main() -> None:
    rows = [r for r in json.load(open(sys.argv[1])) if "error" not in r]
    print(f"{len(rows)} stretches, {sum(len(r['clubs']) for r in rows)} clubs")
    kinds, lengths, per_river = Counter(), defaultdict(list), defaultdict(Counter)
    for r in rows:
        n = len(r["clubs"])
        up = side(r, "up", CAP_UP_KM)
        down = side(r, "down", CAP_DOWN_KM)
        both = up[1] == down[1] == "weir/lock"
        group = "both weir/lock" if both else ("one side weir/lock" if "weir/lock" in (up[1], down[1]) else "no weir/lock")
        kinds[(group, up[1] if up[1] != "weir/lock" else down[1])] += n
        lengths[group].append((round(up[0] + down[0], 1), n))
        per_river[r["river"]][group] += n
        nb = lambda key: (r.get(key + "Barrier") or [None])[0]  # noqa: E731
        big = lambda d, l, x: d <= 40 and (x or 0) >= (BIG_HARBOUR_KM2 if l.startswith("harbour") else BIG_KM)  # noqa: E731
        ev = lambda key: "; ".join(f"{d} {l} {x}" for d, l, x in [e for e in (r.get(key + "Events") or []) if big(*e)][:4])  # noqa: E731
        if both and up[0] + down[0] >= 3:
            print("ROWW " + json.dumps([r["river"], len(r["clubs"]), up[0], down[0]], ensure_ascii=False))
            continue
        print("ROW " + json.dumps({"lakeId": r["lakeId"], "river": r["river"], "clubs": r["clubs"], "at": r["at"],
              "up": [up[0], up[1], up[2], nb("up"), r.get("upReach")], "down": [down[0], down[1], down[2], nb("down"), r.get("downReach")],
              "upEv": ev("up"), "downEv": ev("down"), "upStops": r.get("upStops"), "downStops": r.get("downStops"), "w": r.get("widthM"), "snap": r.get("snapM")}, ensure_ascii=False))
    print("CLUBS BY GROUP AND END:")
    for k, v in sorted(kinds.items()):
        print(f"  {k}: {v}")
    print("SECTION LENGTH (club-weighted):")
    for g, ls in lengths.items():
        flat = sorted(x for x, n in ls for _ in range(n))
        print(f"  {g}: clubs {len(flat)}, min {flat[0]}, median {flat[len(flat)//2]}, max {flat[-1]}")


if __name__ == "__main__":
    main()
