#!/bin/bash
# The website in real WebKit: Mobile Safari in the iPhone Simulator, headless (simctl only; never the
# Simulator app, the Claude app's Simulator tool or computer use). Owner, 12 Nov 2026.
#   scripts/local/safari-sim.sh [-c COMMIT] [-r ROUTE] [-p PIN] [-b BACKGROUND] [-t TILES] [-s light|dark|both] OUT_DIR
#     -c  the commit to build (default: pi/main)          -r  route hash (default #/club/mrc-1880)
#     -p  CSS selector to scroll to and pin (default .hourly-card; "none" = page top)
#     -b  rf.background (default sample:alpine-lake; "none" = plain)   -t  rf.tileStyle (frosted|solid|plain)
#     -s  appearance (default both)
# Pictures: OUT_DIR/safari-sim-<appearance>.png. The site is built in a temporary checkout and served on
# :8780 by scripts/local/safari-sim-server.mjs, with the API from a local backend on :8765 (live data).
# The local server has no password lock (that lives in web/functions, which only runs on Cloudflare
# Pages) and no Content Security Policy. Its seed page (/seed) and scroll script exist only in that
# server, never in web/dist. Load mode: one Simulator; in quiet mode the backend runs with taskpolicy -b.
set -eu
top=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")  # the main checkout, also from a worktree
here=$(cd "$(dirname "$0")" && pwd)
commit=refs/remotes/pi/main route="#/club/mrc-1880" pin=".hourly-card" bg="sample:alpine-lake" tiles=frosted looks="light dark"
while getopts c:r:p:b:t:s: o; do case $o in
  c) commit=$OPTARG ;; r) route=$OPTARG ;; p) pin=$OPTARG ;; b) bg=$OPTARG ;; t) tiles=$OPTARG ;;
  s) [ "$OPTARG" = both ] || looks=$OPTARG ;; *) sed -n 4,8p "$0"; exit 2 ;; esac; done
shift $((OPTIND - 1)); out=${1:?OUT_DIR}; mkdir -p "$out"; out=$(cd "$out" && pwd)
sha=$(git -C "$top" rev-parse --verify "$commit^{commit}")
prefix=$("$here/loadmode.sh" prefix 2>/dev/null || true)
for port in 8765 8780; do lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1 && { echo "port $port is in use"; exit 1; }; done
# The newest runtime's iPhone Pro, as the pre-push check's slot 0.
dev=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
rt = sorted((r for r in json.load(sys.stdin)["devices"].items() if "iOS-" in r[0]),
            key=lambda r: [int(n) for n in r[0].rsplit("iOS-", 1)[-1].split("-") if n.isdigit()])
ph = [(r, d) for r, ds in rt for d in ds if d["name"].startswith("iPhone") and "Duo" not in d["name"]]
new = [d for r, d in ph if r == ph[-1][0]] if ph else []
new.sort(key=lambda d: (0 if d["name"].endswith(" Pro") else 1, d["name"]))
print(new[0]["udid"] if new else "")')
[ -n "$dev" ] || { echo "no iPhone Simulator"; exit 1; }
tmp=$(mktemp -d); wt=$tmp/checkout
cleanup() { pkill -f "safari-sim-server.mjs .* 8780" 2>/dev/null || true; pkill -f "uvicorn rowfrog.api:app --port 8765" 2>/dev/null || true
  xcrun simctl ui "$dev" appearance light 2>/dev/null || true; xcrun simctl shutdown "$dev" 2>/dev/null || true
  git -C "$top" worktree remove --force "$wt" 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT
git -C "$top" worktree add -q --detach "$wt" "$sha"
(cd "$wt" && "$top/backend/.venv/bin/python" scripts/build_web.py >/dev/null)
(cd "$top/backend" && nohup $prefix .venv/bin/uvicorn rowfrog.api:app --port 8765 > "$tmp/backend.log" 2>&1 &)
curl -s -o /dev/null -m 200 --retry 10 --retry-connrefused --retry-delay 2 http://localhost:8765/lakes
generated=$(curl -s -m 200 http://localhost:8765/clubs/mrc-1880/forecast | python3 -c 'import json,sys; print(json.load(sys.stdin).get("generatedAt"))')
(nohup node "$here/safari-sim-server.mjs" "$wt/web/dist" 8780 "$pin" "$route" > "$tmp/server.log" 2>&1 &)
sleep 2
xcrun simctl boot "$dev" 2>/dev/null || true; xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1
echo "Safari: ${sha:0:9}, route $route, pin $pin, background $bg, tiles $tiles, forecast $generated, device $dev"
for look in $looks; do
  xcrun simctl ui "$dev" appearance "$look"
  xcrun simctl terminate "$dev" com.apple.mobilesafari 2>/dev/null || true; sleep 1
  xcrun simctl openurl "$dev" "http://localhost:8780/seed?bg=$bg&tiles=$tiles&pin=$pin"
  sleep 35   # Safari's first start after boot, the live forecast and the pin script (12 s)
  xcrun simctl io "$dev" screenshot "$out/safari-sim-$look.png" >/dev/null 2>&1
  echo "$out/safari-sim-$look.png"
done
