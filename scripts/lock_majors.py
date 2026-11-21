#!/usr/bin/env python3
"""Lists the packages that move to a new major version between two uv.lock files.

    python3 scripts/lock_majors.py OLD_LOCK NEW_LOCK

Prints one line per package ("numpy 2.5.4 -> 3.0.0") and exits 1 if there is
any, 0 if every change stays within its major version. A major is the first
number that is not 0 (0.17 -> 0.18 counts as major, as in semantic versioning),
and a date-style version (certifi 2026.10.23) counts as minor when only the
date moves. The Dependabot merge workflow (dependabot-merge.yml) uses it, so a
major update always waits for the owner's OK (owner rule, 20 Nov 2026).
"""
from __future__ import annotations

import re
import sys
import tomllib


def versions(path: str) -> dict[str, str]:
    with open(path, "rb") as f:
        lock = tomllib.load(f)
    return {p["name"]: p["version"] for p in lock.get("package", []) if "version" in p}


def major(version: str) -> tuple[int, ...]:
    numbers = [int(n) for n in re.findall(r"\d+", version.split("+")[0])[:3]]
    if numbers and numbers[0] >= 1900:  # calendar versions: the year is not a major
        return ()
    for i, n in enumerate(numbers):
        if n != 0:
            return tuple(numbers[: i + 1])
    return tuple(numbers)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    old, new = versions(argv[1]), versions(argv[2])
    majors = [
        f"{name} {old[name]} -> {new[name]}"
        for name in sorted(old.keys() & new.keys())
        if old[name] != new[name] and major(old[name]) != major(new[name])
    ]
    for line in majors:
        print(line)
    return 1 if majors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
