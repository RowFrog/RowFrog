#!/bin/bash
# Stamps the build number and commit for the app (decision 0034):
# writes ios/BuildNumber.local.xcconfig (not in git) for the commit given (default HEAD),
# which ios/BuildNumber.xcconfig includes, so Xcode (⌘R) and xcodebuild both pick it up.
#
#   scripts/build_number.sh [commit]     writes the file, prints "Build 723 · 22a69ce"
#   scripts/build_number.sh --print [commit]   only prints "723 22a69ce"
#
# Build number = git rev-list --count <commit> (needs the full history; a shallow clone
# counts too few). Run it after every pull (update.sh) and before screenshots.
set -euo pipefail
print_only=0
[ "${1:-}" = --print ] && { print_only=1; shift; }
top=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
commit=$(git -C "$top" rev-parse --verify "${1:-HEAD}^{commit}")
count=$(git -C "$top" rev-list --count "$commit")
sha7=$(git -C "$top" rev-parse --short=7 "$commit")
if [ "$(git -C "$top" rev-parse --is-shallow-repository)" = true ]; then
  echo "warning: shallow clone, build number $count is too low" >&2
fi
if [ "$print_only" = 1 ]; then echo "$count $sha7"; exit 0; fi
cat > "$top/ios/BuildNumber.local.xcconfig" <<CONF
// Written by scripts/build_number.sh on $(date -u +%FT%TZ); not in git.
CURRENT_PROJECT_VERSION = $count
RW_COMMIT = $sha7
CONF
echo "Build $count · $sha7"
