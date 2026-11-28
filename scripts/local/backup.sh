#!/bin/bash
# Full backup of the RowFrog repository while GitHub is down (owner's choice, 11 Nov 2026):
# a `git bundle --all` snapshot in RowFrog/backups/, the last 8 kept.
# Started by the main-bundle hook once a week (when the newest snapshot is 7 days old);
# by hand: bash backups/make-backup.sh. Log: RowFrog/log/backup.log.
# The Mac's tool folders (MacPorts, Homebrew or uv's installer), see scripts/local/tool-path.sh.
. "$(dirname "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)")/scripts/local/tool-path.sh"
top=$(git -C "$(dirname "$0")" rev-parse --show-toplevel) || exit 1
dir="$top/backups"; log="$top/log/backup.log"
mkdir -p "$dir" "$top/log"
name="rowfrog-$(date +%Y-%m-%d_%H%M).bundle"
{
  echo "$(date '+%F %T') start"
  if git -C "$top" bundle create -q "$dir/.$name.tmp" --all && git -C "$top" bundle verify -q "$dir/.$name.tmp"; then
    mv -f "$dir/.$name.tmp" "$dir/$name"
    echo "$(date '+%F %T') wrote $name ($(du -h "$dir/$name" | cut -f1)), main at $(git -C "$top" rev-parse --short main)"
    ls -1t "$dir"/rowfrog-*.bundle | tail -n +9 | while read -r old; do rm -f "$old"; echo "removed $(basename "$old")"; done
  else
    rm -f "$dir/.$name.tmp"; echo "$(date '+%F %T') FAILED"; exit 1
  fi
} >> "$log" 2>&1
