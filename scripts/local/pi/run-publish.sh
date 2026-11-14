#!/usr/bin/env bash
# One forecast run on the Raspberry Pi (stopgap while GitHub is away, Nov 2026).
# Does what .github/workflows/publish-backend.yml did on GitHub:
#   1. takes the newest code from the Pi's own git repository (~/git/rowfrog.git),
#   2. reinstalls the Python packages when the pinned versions changed,
#   3. runs scripts/publish_static.py into ~/site/v1,
#   4. copies the changed files to the Cloudflare R2 bucket that api.rowfrog.com reads.
# Started every 30 minutes by rowfrog-publish.timer. By hand:
#   sudo systemctl start rowfrog-publish            (normal run)
#   CLUBS=all ~/rowfrog-pi/run-publish.sh           (all clubs, in your shell)
set -euo pipefail

HOME_DIR=${HOME_DIR:-/home/rowfrog}
REPO=${REPO:-$HOME_DIR/rowfrog}
BRANCH=${BRANCH:-main}
VENV=${VENV:-$HOME_DIR/venv}
SITE=${SITE:-$HOME_DIR/site}
STATE=${STATE:-$HOME_DIR/state}
BUCKET=${BUCKET:-rowfrog-api}
UV=${UV:-$HOME_DIR/.local/bin/uv}
export PATH="$HOME_DIR/.local/bin:$PATH"

mkdir -p "$SITE/v1" "$STATE"

# 1. Newest code (whatever was last pushed to the Pi's repository).
git -C "$REPO" fetch -q origin "$BRANCH"
git -C "$REPO" checkout -q --detach "origin/$BRANCH"
echo "Code: $(git -C "$REPO" log --oneline -1)"

# 2. Packages, only when the pins changed (exactly the versions CI tested).
deps=$(cat "$REPO/backend/requirements-publish.txt" "$REPO/backend/pyproject.toml" | sha256sum | cut -c1-16)
if [ ! -x "$VENV/bin/python" ]; then
  "$UV" venv -q --python 3.12 "$VENV"
fi
if [ "$deps" != "$(cat "$STATE/deps.hash" 2>/dev/null || true)" ]; then
  echo "Installing the pinned Python packages"
  "$UV" pip install -q --python "$VENV/bin/python" -c "$REPO/backend/requirements-publish.txt" -e "$REPO/backend[satellite]"
  echo "$deps" > "$STATE/deps.hash"
fi

# 3. Which clubs: the same plan as the Cloudflare timer (cloudflare/timer/),
#    all clubs in the first half of 04, 10, 16 and 22 UTC (05, 11, 17, 23 German winter time).
if [ -z "${CLUBS:-}" ]; then
  if [[ " 04 10 16 22 " == *" $(date -u +%H) "* ]] && [ "$(date -u +%M)" -lt 30 ]; then
    CLUBS=all
  else
    CLUBS=confirmed
  fi
fi
echo "Clubs: $CLUBS"
# Once the club forecasts are written, publish_static.py runs this (before the
# lake views, which take 30-50 minutes in some runs), so the apps get them at
# once. `copy`, not `sync`: nothing is deleted here; the full sync below does that.
export PUBLISH_CLUBS_DONE="rclone copy $SITE/v1/clubs r2:$BUCKET/v1/clubs --checksum --fast-list --transfers 8 --stats 0 --log-level NOTICE"
export PUBLISH_UPLOAD="rclone copy $SITE/v1 r2:$BUCKET/v1 --files-from-raw {files} --no-check-dest --transfers 8 --stats 0 --log-level NOTICE"
cd "$REPO"
"$VENV/bin/python" scripts/publish_static.py "$SITE/v1" --clubs "$CLUBS" --state "$STATE/publish.pickle"

# 4. Upload. Only files whose checksum differs are sent; files gone from the
#    Pi are deleted from the bucket, so the bucket always matches ~/site/v1.
rclone sync "$SITE/v1" "r2:$BUCKET/v1" --checksum --fast-list --transfers 8 --stats 0 --log-level NOTICE
echo "Published $(date -u +%Y-%m-%dT%H:%MZ)"
