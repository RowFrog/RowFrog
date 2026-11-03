"""Writes test coverage as Markdown for a CI run's summary page.

  python scripts/coverage_summary.py pytest coverage.json "Backend"
  python scripts/coverage_summary.py node node-test.log "Cloudflare Workers"
  python scripts/coverage_summary.py xccov xccov.json "iOS app (unit tests)"

pytest: the JSON from pytest-cov (--cov-report=json). node: the output of
`node --test --experimental-test-coverage`. xccov: `xcrun xccov view --report
--only-targets --json`. Prints the total and the files tested least, so a gap
shows without opening the logs. Information only: it never fails the job.
"""
import json
import re
import sys

LOWEST = 8


def table(rows):
    lines = ["| File | Lines covered |", "|---|---|"]
    lines += [f"| `{name}` | {pct:.0f} % |" for name, pct in rows]
    return "\n".join(lines)


def pytest_report(path):
    data = json.load(open(path))
    total = data["totals"]["percent_covered"]
    files = sorted(((name, f["summary"]["percent_covered"]) for name, f in data["files"].items()
                    if f["summary"]["num_statements"] >= 20), key=lambda r: r[1])
    return total, files[:LOWEST]


def node_report(path):
    text = open(path, encoding="utf-8").read()
    rows, total, folders = [], None, []
    for line in text.splitlines():
        # "ℹ   index.js   | 85.12 | 70.00 | 90.00 | uncovered lines", folders on
        # their own lines above, one space deeper per level ("# " with tap).
        body = re.sub(r"^\s*[ℹ#] ", "", line)
        cells = [c.strip() for c in body.split("|")]
        if len(cells) < 4 or cells[0] in ("", "file"):
            continue
        depth = len(body) - len(body.lstrip(" "))
        folders[depth:] = []
        if not re.fullmatch(r"\d+(\.\d+)?", cells[1]):
            folders.append(cells[0])
            continue
        name = "/".join(folders + [cells[0]])
        if cells[0] == "all files":
            total = float(cells[1])
        elif "/tests/" not in f"/{name}/" and not name.endswith(".test.mjs"):
            rows.append((name, float(cells[1])))
    return total, sorted(rows, key=lambda r: r[1])[:LOWEST]


def xccov_report(path):
    targets = json.load(open(path))
    targets = targets.get("targets", targets) if isinstance(targets, dict) else targets
    rows = [(t["name"], 100 * t["lineCoverage"]) for t in targets if "Tests" not in t["name"]]
    lines = sum(t.get("executableLines", 0) for t in targets if "Tests" not in t["name"])
    covered = sum(t.get("coveredLines", 0) for t in targets if "Tests" not in t["name"])
    return (100 * covered / lines if lines else None), rows


def main():
    kind, path, title = sys.argv[1:4]
    try:
        total, rows = {"pytest": pytest_report, "node": node_report, "xccov": xccov_report}[kind](path)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"### Test coverage: {title}\n\nNo coverage numbers ({error}).\n")
        return
    print(f"### Test coverage: {title}\n")
    print(f"**{total:.0f} %** of lines run by the tests.\n" if total is not None else "No total.\n")
    if rows:
        print(("Targets:" if kind == "xccov" else "Tested least:") + "\n")
        print(table(rows) + "\n")


if __name__ == "__main__":
    main()
