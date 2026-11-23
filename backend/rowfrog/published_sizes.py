"""Sizes of the published files a phone downloads, for the daily Usage limits report.

The data-per-user estimate on the budgets page multiplies these sizes by a
typical day of use. Read from the published folder on the Pi (see folder()), never from api.rowfrog.com: a download there would count as
use. Sizes are given as stored and gzip-compressed, which is about what
Cloudflare sends to the app.
"""

from __future__ import annotations

import gzip
import os
from pathlib import Path
from statistics import median

# What the app and website load, by pattern under v1/.
KINDS = {
    "Club forecast": "clubs/*/forecast",
    "Club forecast, other model": "clubs/*/models/*/forecast",
    "Lake view": "lakes/*/view",
    "Lake list": "lakes/index",
    "Satellite picture info": "lakes/*/satellite",
}


def folder() -> Path | None:
    """The published v1 folder, or None where there is none (GitHub, a laptop).

    PUBLISHED_DIR when set; else the Pi's folders: ~/data/rowfrog/site/v1 on the
    managed Pi card (since 22 Nov 2026), ~/site/v1 before."""
    given = os.environ.get("PUBLISHED_DIR")
    home = Path.home()
    candidates = [Path(given)] if given else [home / "data" / "rowfrog" / "site" / "v1", home / "site" / "v1"]
    return next((p for p in candidates if p.is_dir()), None)


def measure(root: Path) -> list[dict]:
    rows = []
    for name, pattern in KINDS.items():
        files = [p for p in root.glob(pattern) if p.is_file()]
        if not files:
            continue
        raw = [p.stat().st_size for p in files]
        packed = [len(gzip.compress(p.read_bytes(), 6)) for p in files]
        rows.append({
            "kind": name, "files": len(files),
            "median_kb": median(raw) / 1000, "largest_kb": max(raw) / 1000,
            "median_gzip_kb": median(packed) / 1000, "largest_gzip_kb": max(packed) / 1000,
        })
    return rows


def report(rows: list[dict]) -> str:
    if not rows:
        return ""
    lines = [
        "", "## Download sizes (published files)", "",
        "| File | Files | Median KB | Largest KB | Median gzip KB | Largest gzip KB |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    lines += [
        f"| {r['kind']} | {r['files']} | {r['median_kb']:,.1f} | {r['largest_kb']:,.1f} | {r['median_gzip_kb']:,.1f} | {r['largest_gzip_kb']:,.1f} |"
        for r in rows
    ]
    return "\n".join(lines)
