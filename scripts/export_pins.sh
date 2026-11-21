#!/usr/bin/env bash
# Writes backend/requirements-publish.txt from backend/uv.lock, the one place
# where the backend's package versions are kept (see docs/handbook.md, "Same
# versions everywhere"). The file is generated, never kept in git (.gitignore):
# GitHub workflows make it with .github/actions/backend-pins before
# `pip install -c backend/requirements-publish.txt …`. The Pi and the Mac install
# straight from the lock with `uv sync --locked` and don't need it.
set -euo pipefail
cd "$(dirname "$0")/../backend"
{
  cat <<'HEAD'
# GENERATED from backend/uv.lock by scripts/export_pins.sh; not in git.
# Every version the backend uses anywhere, as constraints:
# pip install -c backend/requirements-publish.txt -e "backend[satellite]".
HEAD
  uv export --frozen --all-extras --no-emit-project --no-hashes --no-annotate --no-header
} > requirements-publish.txt.new
mv requirements-publish.txt.new requirements-publish.txt
echo "backend/requirements-publish.txt written from backend/uv.lock"
