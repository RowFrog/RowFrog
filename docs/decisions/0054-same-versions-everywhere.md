# 0054. One lock file per kind of software; every system installs from it

- Date: 2026-11-20
- Status: step 1 of 6 (owner, thread "Keep software versions the same everywhere", 20 Nov 2026: option A 23:40 CET (22:40 UTC); monthly bumps with 7-day cooldown, security at once 23:40 CET; exact Python patch 23:46 CET; majors and Python 3.14 23:49 CET, each major with the owner's OK; research doc https://claude.ai/artifact/28e1gY5aonPHkRnmVExeg6)
- Where: `backend/uv.lock` + `backend/pyproject.toml` (`[tool.uv] required-environments`), `backend/requirements-publish.txt` (export, `scripts/export_pins.sh`), `.python-version`, `.nvmrc`, `.github/dependabot.yml`, `.github/workflows/dependabot-merge.yml` + `scripts/lock_majors.py`, `ci.yml` (lock check). Handbook "Same versions everywhere".

## Why

GitHub CI, the Mac and the Pi installed the 29 backend pins from one file, but the test tools (pytest, pytest-cov, httpx2), the Python patch level, Node, xcodegen and one workflow's packages (shapely, osmium) were whatever was newest on the day, `pip install -c` never removed packages, and the Mac never refreshed npm. Two systems could run different code without anyone noticing.

## Decision

- One file per kind: `backend/uv.lock` for every Python package (forecast, tests, lint, river sections), `package-lock.json` for npm, `.python-version` (exact patch) for Python, `.nvmrc` for Node. A bump is one PR that changes that file; CI tests it; the Mac and the Pi take it from main.
- The lock must have a build for Linux x86_64 (GitHub), Linux aarch64 (Pi) and macOS arm64 (Mac), or `uv lock` fails.
- Dependabot: monthly, one grouped PR per kind for minor and patch updates, each major its own PR, 7-day cooldown; security fixes at once (grouped). Backend minor/patch and security PRs merge themselves when CI is green; majors, npm and Actions wait for the owner's OK.
- The monthly dependency check (3rd of the month) compares Python, Node, xcodegen and uv with the newest releases, checks that a newer Python has builds of every locked package for all three systems, and asks the owner about each waiting major.
- Order: (1) lock with the versions in use on 20 Nov (this step, no version changes); (2) Pi scripts and Mac update.sh install from the lock (`uv sync --locked`), the Pi gate fails when an install fails, a failed install keeps the last good setup; (3) a version check script on all systems; (4) newest minor/patch versions; (5) Python 3.14 (3.15 is blocked: eccodeslib and eckitlib 2.50.0.33 have no 3.15 builds, PyPI 20 Nov 23:50 CET); (6) one PR per major.

## Turned down

- B: keep `requirements-publish.txt` as the source and close the gaps (two files to keep in step, no check for the Pi's and the Mac's platforms).
- C: leave as is.
- Python 3.15 now: not every package has builds for it yet.
