#!/usr/bin/env bash
# Writes backend/requirements-publish.txt from backend/uv.lock, the one place
# where the backend's package versions are kept (see docs/handbook.md, "Package
# updates"). The Pi scripts and the Mac's update.sh still install with
# `pip install -c backend/requirements-publish.txt`, so this file must always
# match the lock. CI (ci.yml, backend job) runs this script with --check and
# fails when the two differ.
#   scripts/export_pins.sh           (rewrite the file after `uv lock`)
#   scripts/export_pins.sh --check   (only compare)
set -euo pipefail
cd "$(dirname "$0")/../backend"
out=requirements-publish.txt
new=$(mktemp)
trap 'rm -f "$new"' EXIT
{
  cat <<'HEAD'
# GENERATED from backend/uv.lock by scripts/export_pins.sh: do not edit by hand.
# Change a version with `uv lock --upgrade-package <name>` (or a Dependabot PR),
# then run scripts/export_pins.sh; CI fails if this file and the lock differ.
# Every version the backend uses anywhere (forecast job, tests, lint, river
# sections), as constraints: pip install -c backend/requirements-publish.txt
# -e "backend[satellite]". Python: see .python-version.
HEAD
  uv export --frozen --all-extras --no-emit-project --no-hashes --no-annotate --no-header
} > "$new"
if [ "${1:-}" = --check ]; then
  if ! diff -u "$out" "$new"; then
    echo "backend/requirements-publish.txt does not match backend/uv.lock: run scripts/export_pins.sh" >&2
    exit 1
  fi
  echo "backend/requirements-publish.txt matches backend/uv.lock"
else
  cp "$new" "$out"
fi
