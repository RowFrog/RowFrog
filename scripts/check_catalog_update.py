#!/usr/bin/env python3
"""Run by the catalog workflows before they commit to main: drops lake outlines
this run fetched for a water no club ended up on (the import found a harbour,
then water-fixes.json moved the club to the river), then runs the data file
tests. A failing test stops the commit, so a broken catalog never lands on
main (as on 2026-11-04, when an import undid 50 shore points).

    python3 scripts/check_catalog_update.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from rowfrog import locations  # noqa: E402


def main() -> int:
    known = set(locations.load().lakes)
    new = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "data/outlines"],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
    for name in new:
        path = ROOT / name
        if path.suffix == ".geojson" and path.stem not in known:
            print(f"dropping {name}: no club is on that water")
            path.unlink()
    return subprocess.run([sys.executable, "-m", "pytest", "-q", "tests/test_data_files.py"], cwd=ROOT / "backend").returncode


if __name__ == "__main__":
    sys.exit(main())
