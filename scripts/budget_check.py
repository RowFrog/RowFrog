#!/usr/bin/env python3
"""Daily check of the outside services' call totals against their free limits.

Usage (from the repository root, after `pip install -e backend`, with RW_USAGE_KEY set,
and CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID for the Cloudflare figures;
on the Pi the report also lists the sizes of the published files, see published_sizes):
    python3 scripts/budget_check.py OUT.md

Writes the report to OUT.md (and the job summary on GitHub) and exits with
2 when something needs attention (warning or alert), else 0.
"""

from __future__ import annotations

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from rowfrog import cloudflare_usage, limits, published_sizes, source_status, usage


def main() -> int:
    # What the requests say about each service (sources-status.json, only where SOURCES_STATUS is set: the Pi).
    source_status.start("budget-check")
    out = Path(sys.argv[1])
    today = datetime.now(timezone.utc).date()
    rows = usage.budget(days=35)
    if rows is None:
        text = f"# Usage limits, {today.isoformat()}\n\nThe usage counter did not answer, or RW_USAGE_KEY is not set."
        level = "warn"
    else:
        cloudflare = cloudflare_usage.daily(today)
        r2 = cloudflare_usage.r2_daily(today)
        findings = limits.check(rows + (cloudflare or []) + (r2 or []), today)
        if cloudflare is None:
            findings.append(limits.Finding("cloudflare", "warn", "cloudflare: Worker and D1 figures could not be read (token or analytics answer)."))
        if r2 is None:
            findings.append(limits.Finding("cloudflare-r2", "warn", "cloudflare-r2: R2 figures could not be read (token needs Account Analytics read)."))
        text = limits.report(findings, today)
        level = limits.worst(findings)
    # The sizes a phone downloads, for the data-per-user estimate (Pi only: its published folder).
    published = published_sizes.folder()
    if published:
        text += published_sizes.report(published_sizes.measure(published))
    out.write_text(text + "\n", encoding="utf-8")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text + "\n")
    print(text)
    return 2 if level != "ok" else 0


if __name__ == "__main__":
    sys.exit(main())
