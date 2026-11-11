#!/bin/bash
# App size on the Mac while GitHub is down (Nov 2026): runs app-size.yml's own steps
# (unsigned Release archive, the size table, the largest files) on a commit, in a
# separate checkout, with the Mac's Xcode. Usage: scripts/local/app-size.sh [commit or branch, default main]
# Report: RowFrog/log/app-size-<commit>.md (what GitHub put in the run summary).
set -euo pipefail
top=$(git rev-parse --show-toplevel)
here=$(cd "$(dirname "$0")" && pwd)
export PATH="$top/backend/.venv/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
ref=${1:-main}
sha=$(git -C "$top" rev-parse --verify "$ref^{commit}")
export RUNNER_TEMP; RUNNER_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/rowfrog-app-size.XXXXXX")
wt="$RUNNER_TEMP/checkout"
export GITHUB_STEP_SUMMARY="$top/log/app-size-${sha:0:9}.md"
mkdir -p "$top/log"; : > "$GITHUB_STEP_SUMMARY"
cleanup() { git -C "$top" worktree remove --force "$wt" >/dev/null 2>&1 || true; rm -rf "$RUNNER_TEMP"; }
trap cleanup EXIT
git -C "$top" worktree add -q --detach "$wt" "$sha"
flow="$wt/.github/workflows/app-size.yml"
step() { python3 "$here/workflow_step.py" "$flow" size "$@"; }
cd "$wt/ios"
xcodegen >/dev/null
echo "App size of ${sha:0:9} with $(xcodebuild -version | head -1)"
for name in "Release archive (unsigned)" "Measure" "Largest files in the app"; do
  echo "== $name"
  step "$name" > "$RUNNER_TEMP/step.sh"
  bash --noprofile --norc -eo pipefail "$RUNNER_TEMP/step.sh"
done | tee -a "$top/log/app-size-${sha:0:9}.log"
echo "Report: $GITHUB_STEP_SUMMARY"
