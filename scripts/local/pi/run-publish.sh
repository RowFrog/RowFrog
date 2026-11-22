#!/usr/bin/env bash
# One forecast run on the Raspberry Pi (stopgap while GitHub is away, Nov 2026).
# Does what .github/workflows/publish-backend.yml did on GitHub:
#   1. takes the newest code from the Pi's own git repository (~/git/rowfrog.git),
#   2. installs exactly backend/uv.lock when it changed (keeping the old set if that fails),
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
prev=$(git -C "$REPO" rev-parse -q --verify HEAD || true)   # the code the last run used
git -C "$REPO" fetch -q origin "$BRANCH"
git -C "$REPO" checkout -q --detach "origin/$BRANCH"
echo "Code: $(git -C "$REPO" log --oneline -1)"

# 2. Packages: exactly backend/uv.lock on the Python in .python-version, the
#    same versions CI tested. Each lock gets its own environment in ~/venvs/<hash>;
#    ~/venv is a link to the one in use and moves only after the new one installed
#    completely. If the install fails, this run goes back to the last commit that
#    published (state/good.commit) with its environment, so code and packages
#    never mix, and the failure is in the log (journalctl -u rowfrog-publish).
export PYTHONPATH="$REPO/backend"
if [ -f "$REPO/backend/uv.lock" ]; then
  deps=$(cat "$REPO/backend/uv.lock" "$REPO/backend/pyproject.toml" "$REPO/.python-version" | sha256sum | cut -c1-16)
  env="$HOME_DIR/venvs/$deps"
  if [ "$(readlink "$VENV" 2>/dev/null)" != "$env" ]; then
    echo "Installing the locked Python packages into $env"
    rm -rf "$env"
    if (cd "$REPO/backend" && UV_PROJECT_ENVIRONMENT="$env" "$UV" sync -q --locked \
          --managed-python --python "$(cat "$REPO/.python-version")" --extra satellite); then
      [ -d "$VENV" ] && [ ! -L "$VENV" ] && mv "$VENV" "$VENV.before-lock"   # once: the old pip-made venv
      ln -sfn "$env" "$VENV.new" && mv -T "$VENV.new" "$VENV"
      # Keep the one in use and the one before it; delete older ones.
      ls -1dt "$HOME_DIR"/venvs/*/ 2>/dev/null | tail -n +3 | xargs -r rm -rf
    else
      rm -rf "$env"
      good=$(cat "$STATE/good.commit" 2>/dev/null || echo "$prev")
      echo "INSTALL FAILED for $(git -C "$REPO" log --oneline -1); going back to ${good:0:9} and its packages"
      [ -n "$good" ] || exit 1
      git -C "$REPO" checkout -q --detach "$good"
    fi
  fi
else
  # A commit from before the lock (before 21 Nov 2026): the old way.
  deps=$(cat "$REPO/backend/requirements-publish.txt" "$REPO/backend/pyproject.toml" | sha256sum | cut -c1-16)
  if [ "$deps" != "$(cat "$STATE/deps.hash" 2>/dev/null || true)" ]; then
    echo "Installing the pinned Python packages"
    "$UV" pip install -q --python "$VENV/bin/python" -c "$REPO/backend/requirements-publish.txt" -e "$REPO/backend[satellite]"
    echo "$deps" > "$STATE/deps.hash"
  fi
fi

# Same versions as pinned (owner, 21 Nov 2026): one line per run in the log,
# "DIFF" when the Pi's Python or packages differ from .python-version/uv.lock.
# ~/venv is the link to the environment in use. Never stops the run.
if [ -f "$REPO/scripts/check_versions.py" ]; then
  if out=$("$VENV/bin/python" "$REPO/scripts/check_versions.py" --env "$VENV" --extras satellite 2>&1); then
    echo "VERSIONS: same as pinned"
  else
    echo "VERSIONS: DIFF"; echo "$out" | grep -v '^same' || true
  fi
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
# Each file goes online a few seconds after it is written (PUBLISH_UPLOAD); the early
# copy of all club files (PUBLISH_CLUBS_DONE) is no longer set (Pi speed-up #4, Nov 2026).
export PUBLISH_UPLOAD="rclone copy $SITE/v1 r2:$BUCKET/v1 --files-from-raw {files} --no-check-dest --transfers 8 --stats 0 --log-level NOTICE"
cd "$REPO"
"$VENV/bin/python" scripts/publish_static.py "$SITE/v1" --clubs "$CLUBS" --state "$STATE/publish.pickle"

# 4. Upload. Only files whose checksum differs are sent; files gone from the
#    Pi are deleted from the bucket, so the bucket always matches ~/site/v1.
rclone sync "$SITE/v1" "r2:$BUCKET/v1" --checksum --fast-list --transfers 8 --stats 0 --log-level NOTICE
git -C "$REPO" rev-parse HEAD > "$STATE/good.commit"
echo "Published $(date -u +%Y-%m-%dT%H:%MZ)"
