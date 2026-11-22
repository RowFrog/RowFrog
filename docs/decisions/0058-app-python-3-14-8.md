# 0058. The app runs on Python 3.14.8

- Date: 2026-11-22
- Status: decided (owner, thread "Keep software versions the same everywhere", 22 Nov 2026 04:15 CET (03:15 UTC), card "Go: 3.14.8 now"; the Pi project agreed in the shared versions doc)
- Where: `.python-version`; used by GitHub (setup-python, and uv on the Mac runners), the Pi (pi-fleet and `run-publish.sh`, uv) and the Mac (update.sh, uv).

## Why

The app ran on 3.12.15, which gets security fixes only. 3.14 gets bugfixes until Oct 2027. Checked on 22 Nov 2026 (research doc "Python version for RowFrog: research 22 Nov 2026"):

- 3.14.8 is the highest 3.14 patch that all three systems install: GitHub's setup-python manifest (Linux x64/arm64, macOS arm64), and uv 0.13.4 from MacPorts on the Mac, which the Pi also uses since pi-fleet #100.
- All 47 packages in `backend/uv.lock` have cp314 wheels for Linux x86_64, Linux aarch64 and macOS arm64; nothing builds from source.
- The backend tests pass on 3.14.8 (391 passed, 1 skipped), as on 3.12.15, 3.13.16 and 3.15.0.

## Decision

- `.python-version` is 3.14.8. `requires-python` stays `>=3.12`, and ruff's target stays py312, because the Pi runs `source_status.py` and its issue job on Debian's own Python 3.13.
- The Pi's system Python (monitors, pi-fleet) is a separate decision of the Pi project and stays on Debian's 3.13.

## Turned down

- 3.15.0: works too, but it is a .0 release, and the Mac's uv offers no later 3.15 patch yet. To be looked at again once MacPorts' uv offers 3.15.2 or newer.
- 3.13.16: bugfixes ended Oct 2026, so it brings little over 3.12.
- Staying on 3.12.15.
