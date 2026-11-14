#!/bin/bash
# App screenshots on the Mac while GitHub is down (Nov 2026): runs screenshots.yml's own
# steps ("Start the backend with live data", "Build the app", "Take screenshots") on a
# branch, in a separate checkout, then saves the set as one commit under
# refs/screenshots/<branch> (as the workflow does) and pushes it to the Pi.
# Changes to the workflow's text, each checked: its backend runs on port 8765 (your own
# backend on 8000 is left alone, the app is pointed at 8765 with -RWAPIBaseURL), and
# its final "pkill -f uvicorn" stops only that backend; the app starts in English (en_US), as on
# GitHub's runners, so a German Mac does not turn the English shots German.
#   scripts/local/screenshots.sh [-o REGEX] [-b BRANCH] [--ipad | --device NAME] [--no-push]
#   --device: "iPhone 13 mini" or "iPhone SE" (the workflow's device choices; their own folder in the set)
#   -o: only the screens whose name matches (the workflow's `only`); owner rule: changed screens only
# The pictures: RowFrog/log/screenshots/<branch>/ ; log: RowFrog/log/screenshots-<branch>.log
set -euo pipefail
top=$(git rev-parse --show-toplevel)
here=$(cd "$(dirname "$0")" && pwd)
only=""; branch=$(git -C "$top" symbolic-ref -q --short HEAD || echo main); device=iPhone; push=1
while [ $# -gt 0 ]; do
  case $1 in
    -o|--only) only=$2; shift 2 ;;
    -b|--branch) branch=$2; shift 2 ;;
    --ipad) device=iPad; shift ;;
    --device) device=$2; shift 2 ;;
    --no-push) push=0; shift ;;
    *) echo "usage: $0 [-o REGEX] [-b BRANCH] [--ipad | --device NAME] [--no-push]"; exit 2 ;;
  esac
done
export VENV="$top/backend/.venv"
export PATH="$VENV/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PORT=8765
if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then echo "Port $PORT is in use"; exit 1; fi
sha=$(git -C "$top" rev-parse --verify "$branch^{commit}")
safe=${branch//\//-}
log="$top/log/screenshots-$safe.log"
out="$top/log/screenshots/$safe"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/rowfrog-shots.XXXXXX")
wt="$tmp/checkout"   # its own per run, so two sessions never remove each other's
mkdir -p "$top/log"
cleanup() {
  pkill -f "uvicorn rowfrog.api:app --port $PORT" 2>/dev/null || true
  git -C "$top" worktree remove --force "$wt" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT
git -C "$top" worktree add -q --detach "$wt" "$sha"
flow="$wt/.github/workflows/screenshots.yml"
step() { python3 "$here/workflow_step.py" "$flow" screenshots "$@"; }
run() { bash --noprofile --norc -eo pipefail "$1"; }
echo "Screenshots of $branch (${sha:0:9}) on $device, only: ${only:-all}; log $log"
shots() {
  set -e
  # The earlier set of this branch, else main's, so a run with -o keeps the other screens.
  mkdir -p "$wt/docs/screenshots"
  for ref in "refs/screenshots/$branch" refs/screenshots/main; do
    if git -C "$top" rev-parse -q --verify "$ref" >/dev/null; then
      git -C "$top" archive "$ref" | tar -x -C "$wt/docs/screenshots"; echo "Started from $ref"; break
    fi
  done
  cd "$wt"
  export PYTHONPATH="$wt/backend" GITHUB_ENV="$tmp/github.env" GITHUB_REF_NAME="$branch" RUNNER_TEMP="$tmp"
  : > "$GITHUB_ENV"
  echo "== Start the backend with live data (port $PORT)"
  step "Start the backend with live data" \
    'nohup uvicorn rowfrog.api:app --port 8000=>nohup "$VENV/bin/uvicorn" rowfrog.api:app --port "$PORT"' \
    'localhost:8000=>localhost:$PORT' > "$tmp/backend.sh"
  run "$tmp/backend.sh"
  echo "== Build the app"
  step "Build the app" 'brew install xcodegen=>:' 'xcrun simctl boot "$UDID"=>xcrun simctl boot "$UDID" || true' > "$tmp/build.sh"
  (cd ios && DEVICE="$device" XCODE_INPUT="" run "$tmp/build.sh" 2>&1 | grep -E "error|BUILD (SUCCEEDED|FAILED)|Using" ; exit "${PIPESTATUS[0]}")
  set -a; . "$GITHUB_ENV"; set +a
  echo "== Take screenshots on $UDID into $SHOTS"
  step "Take screenshots" \
    'localhost:8000=>localhost:$PORT' \
    'pkill -f uvicorn=>pkill -f "uvicorn rowfrog.api:app --port $PORT"' \
    'xcrun simctl launch "$UDID" com.rowfrog.RowFrog=>xcrun simctl launch "$UDID" com.rowfrog.RowFrog -RWAPIBaseURL "http://localhost:$PORT" -AppleLanguages "(en)" -AppleLocale en_US' \
    > "$tmp/shoot.sh"
  ONLY_INPUT="$only" run "$tmp/shoot.sh"
  xcrun simctl shutdown "$UDID" || true
}
set +e
( shots ) > "$log" 2>&1
rc=$?
set -e
[ "$rc" = 0 ] || { echo "Failed, see $log"; tail -20 "$log"; exit 1; }

# The set as one commit, outside every branch's history (as the workflow's last step).
mkdir -p "$out"; rsync -a --delete "$wt/docs/screenshots/" "$out/"
commit=$(cd "$wt/docs/screenshots" && GIT_DIR=$(git -C "$top" rev-parse --absolute-git-dir) GIT_WORK_TREE=. \
  GIT_INDEX_FILE="$tmp/screenshots.index" sh -c 'git add -A -f . && tree=$(git write-tree) && git commit-tree "$tree" -m "Screenshots of '"$branch"' at '"${sha:0:7}"'"')
git -C "$top" update-ref "refs/screenshots/$branch" "$commit"
echo "Saved refs/screenshots/$branch = ${commit:0:9} ($(ls "$out" | grep -c '\.png$') pictures in $out)"
if [ "$push" = 1 ]; then git -C "$top" push -q pi "+refs/screenshots/$branch:refs/screenshots/$branch" && echo "Pushed to pi"; fi
