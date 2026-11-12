#!/bin/bash
# How hard the Mac merge queue may work right now (owner's plan, 12 Nov 2026).
#   quiet: 22:00-07:00, on battery or with a thermal/performance warning, or when the owner said "quiet".
#          Low priority (taskpolicy -b), one Simulator, xcodebuild -jobs half the cores.
#   busy:  otherwise. Two Simulators for the per-hand-in iOS checks (branch tip + main in parallel),
#          up to MAX_SIMS for big screenshot sets, limited by free memory (about 4 GB per extra
#          Simulator, at least 8 GB left over) and fewer while Xcode.app is open.
#   The owner's "full speed" / "quiet" overrides the clock until the next 07:00 or 22:00 switch
#   ("auto" ends it at once).
# Usage:
#   loadmode.sh mode            quiet | busy (and why, on stderr)
#   loadmode.sh sims [checks|shots]   how many Simulators to use at once
#   loadmode.sh jobs            value for xcodebuild -jobs
#   loadmode.sh prefix          "taskpolicy -b" in quiet mode, empty in busy mode
#   loadmode.sh set full|quiet|auto   the owner's override
#   loadmode.sh boost           lift the queue's running xcodebuild/Simulator/test processes out of low priority
set -u
conf="${ROWFROG_LOADMODE_FILE:-$HOME/.config/rowfrog/loadmode}"
MAX_SIMS=${MAX_SIMS:-4}
QUIET_FROM=${QUIET_FROM:-22}
QUIET_TO=${QUIET_TO:-7}
cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)

hour() { date +%H | sed 's/^0//'; }
night() { local h; h=$(hour); [ "$h" -ge "$QUIET_FROM" ] || [ "$h" -lt "$QUIET_TO" ]; }
# The override holds until the next switch of the clock (07:00 or 22:00).
override() {
  [ -f "$conf" ] || return 1
  local what until; read -r what until < "$conf" || return 1
  [ -n "${until:-}" ] && [ "$(date +%s)" -lt "$until" ] && echo "$what"
}
next_switch() {
  local now today7 today22
  now=$(date +%s); today7=$(date -j -f "%H:%M:%S" "$(printf %02d "$QUIET_TO"):00:00" +%s); today22=$(date -j -f "%H:%M:%S" "$QUIET_FROM:00:00" +%s)
  for t in "$today7" "$today22" $((today7 + 86400)); do [ "$t" -gt "$now" ] && { echo "$t"; return; }; done
}
on_battery() { pmset -g batt 2>/dev/null | head -1 | grep -q "Battery Power"; }
hot() { pmset -g therm 2>/dev/null | grep -qiE "warning level[^\n]*[1-9]|CPU_Speed_Limit *= *[0-9]{1,2}$"; }
free_gb() { vm_stat | awk -v ps="$(pagesize)" '/Pages free|Pages inactive|Pages speculative/ {gsub("\\.","",$NF); n+=$NF} END {printf "%d", n*ps/1073741824}'; }
xcode_open() { pgrep -xq Xcode; }

mode() {
  local o; o=$(override)
  if [ "$o" = full ]; then echo "busy"; echo "owner said full speed" >&2; return; fi
  if [ "$o" = quiet ]; then echo "quiet"; echo "owner said quiet" >&2; return; fi
  if night; then echo quiet; printf "quiet hours %02d:00-%02d:00\n" "$QUIET_FROM" "$QUIET_TO" >&2; return; fi
  if on_battery; then echo quiet; echo "on battery" >&2; return; fi
  if hot; then echo quiet; echo "thermal warning" >&2; return; fi
  echo busy; echo "day, on power, no warning" >&2
}

sims() {
  local kind=${1:-checks} m free n
  m=$(mode 2>/dev/null)
  [ "$m" = quiet ] && { echo 1; return; }
  free=$(free_gb)
  if [ "$kind" = checks ]; then n=2; else n=$MAX_SIMS; fi
  # About 4 GB per Simulator beyond the first, with 8 GB left over.
  while [ "$n" -gt 1 ] && [ $((free - 4 * (n - 1))) -lt 8 ]; do n=$((n - 1)); done
  xcode_open && [ "$n" -gt 2 ] && n=2
  echo "$n"
}

case "${1:-mode}" in
  mode) mode ;;
  sims) sims "${2:-checks}" ;;
  jobs) if [ "$(mode 2>/dev/null)" = quiet ]; then echo $(( (cores + 1) / 2 )); else echo "$cores"; fi ;;
  prefix) [ "$(mode 2>/dev/null)" = quiet ] && echo "taskpolicy -b" ;;
  set)
    mkdir -p "$(dirname "$conf")"
    case "${2:-}" in
      full|quiet) echo "$2 $(next_switch)" > "$conf"; echo "override: $2 until $(date -r "$(next_switch)" '+%F %H:%M')" ;;
      auto) rm -f "$conf"; echo "override cleared" ;;
      *) echo "usage: $0 set full|quiet|auto" >&2; exit 2 ;;
    esac ;;
  boost)
    n=0
    for pid in $(pgrep -f "xcodebuild|XCTRunner|RowFrog.app/RowFrog|simctl|node --test|pytest"); do
      taskpolicy -B -p "$pid" 2>/dev/null && n=$((n + 1))
    done
    echo "lifted $n processes" ;;
  *) echo "usage: $0 mode|sims [checks|shots]|jobs|prefix|set full|quiet|auto|boost" >&2; exit 2 ;;
esac
