#!/usr/bin/env python3
"""Prints one step's `run` script from a GitHub workflow, so the Mac and the Pi can run
the workflow's own commands while GitHub is down (Nov 2026), with the workflow files
untouched. Optional substitutions OLD=>NEW must each match, so a changed workflow
fails loudly instead of running something else.

    workflow_step.py .github/workflows/app-size.yml size "Release archive (unsigned)" ['OLD=>NEW' ...]
"""

import sys

import yaml


def main() -> int:
    path, job, step, *subs = sys.argv[1:]
    with open(path, encoding="utf-8") as f:
        flow = yaml.safe_load(f)
    steps = flow["jobs"][job]["steps"]
    found = [s for s in steps if s.get("name") == step]
    if len(found) != 1:
        print(f"{path}: job {job} has no single step named {step!r}", file=sys.stderr)
        return 2
    text = found[0]["run"]
    for sub in subs:
        old, new = sub.split("=>", 1)
        if old not in text:
            print(f"{path}, {step!r}: {old!r} not found; the workflow changed", file=sys.stderr)
            return 3
        text = text.replace(old, new)
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
