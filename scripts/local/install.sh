#!/bin/bash
# Installs the Mac side of the GitHub-down setup (Nov 2026) into this clone:
# the git hooks (pre-push checks, inbox/main.bundle, weekly backup) and the
# backup script in backups/, and keeps inbox/, log/, prs/, backups/ out of git.
# The Pi's push gate: scp scripts/local/pi/pre-receive rowfrog:git/rowfrog.git/hooks/
# (needs ~/venv-check on the Pi; see docs/handbook.md, "While GitHub is down").
set -euo pipefail
top=$(git rev-parse --show-toplevel)
hooks=$(git rev-parse --git-path hooks)
for h in pre-push write-main-bundle post-commit post-merge; do
  install -m 755 "$top/scripts/local/hooks/$h" "$hooks/$h"
done
mkdir -p "$top/inbox/done" "$top/log" "$top/prs" "$top/backups"
install -m 755 "$top/scripts/local/backup.sh" "$top/backups/make-backup.sh"
exclude=$(git rev-parse --git-path info/exclude)
for d in /inbox/ /log/ /prs/ /backups/; do grep -qxF "$d" "$exclude" || echo "$d" >> "$exclude"; done
echo "Installed: hooks in $hooks, backups/make-backup.sh; inbox/ log/ prs/ backups/ excluded from git"
