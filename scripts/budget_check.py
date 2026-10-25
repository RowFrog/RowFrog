#!/usr/bin/env python3
"""Daily check of the outside services' call totals against their free limits.

Usage (from the repository root, after `pip install -e backend`, with RW_USAGE_KEY set):
    python3 scripts/budget_check.py OUT.md

Writes the report to OUT.md (and the job summary on GitHub) and exits with
2 when something needs attention (warning or alert), else 0.
"""

from __future__ import annotations

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from rowfrog import limits, usage


def main() -> int:
    out = Path(sys.argv[1])
    today = datetime.now(timezone.utc).date()
    rows = usage.budget(days=35)
    if rows is None:
        text = f"# Usage limits, {today.isoformat()}\n\nThe usage counter did not answer, or RW_USAGE_KEY is not set."
        level = "warn"
    else:
        findings = limits.check(rows, today)
        text = limits.report(findings, today)
        level = limits.worst(findings)
    out.write_text(text + "\n", encoding="utf-8")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text + "\n")
    print(text)
    return 2 if level != "ok" else 0


if __name__ == "__main__":
    sys.exit(main())
