#!/bin/bash
# Pictures from the website's smoke test hooks (RF_SHOT, RF_NIGHT_SHOT, …) for a commit.
# They come from the smoke test's staged sample data (a made-up model switch, a fixed clock),
# not from a real forecast, so every file name starts with "test-smoke-" (owner, 12 Nov 2026).
#   scripts/local/smoke-shots.sh COMMIT OUT_DIR [TEST_NAME_PATTERN]
set -eu
top=$(git rev-parse --show-toplevel)
commit=$(git -C "$top" rev-parse --verify "${1:?commit}^{commit}"); out=$(cd "${2:?out dir}" && pwd); pattern=${3:-}
wt=$(mktemp -d)/checkout
git -C "$top" worktree add -q --detach "$wt" "$commit"
trap 'git -C "$top" worktree remove --force "$wt"' EXIT
(cd "$wt" && "$top/backend/.venv/bin/python" scripts/build_web.py >/dev/null && ln -s "$top/node_modules" node_modules &&
  RF_NIGHT_SHOT="$out/test-smoke-web-48h" RF_SHOT="$out/test-smoke-shot.png" RF_SHOT_END="$out/test-smoke-shot-end.png" \
  node --test ${pattern:+--test-name-pattern="$pattern"} web/tests/browser/smoke.test.mjs | grep -E "^# (pass|fail)|^not ok")
ls "$out" | grep '^test-smoke-' || true
