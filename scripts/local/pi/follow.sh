#!/bin/bash
# Follows GitHub's main on the Pi once GitHub is the code home again (owner, 14 Nov 2026):
# fetches github/main into the Pi's bare repo with the read-only deploy key, and moves the
# Pi's main forward only when it is a fast-forward AND the bare repo's own push gate
# (hooks/pre-receive: backend tests in ~/venv-check) passes on exactly that commit.
# Never follows a force-push; never runs during a forecast run.
#   ~/rowfrog-pi/follow.sh [--dry-run]     (--dry-run: fetch and test, never move main)
# Started by rowfrog-follow.timer (:07, :22, :37, :52). Log: journalctl -u rowfrog-follow
set -euo pipefail
dry=0; [ "${1:-}" = --dry-run ] && dry=1
export GIT_DIR=$HOME/git/rowfrog.git
export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/github_rowfrog -o IdentitiesOnly=yes -o BatchMode=yes"
if systemctl is-active --quiet rowfrog-publish.service; then echo "follow: forecast run active, skipped"; exit 0; fi
exec 9>"$HOME/rowfrog-pi/follow.lock"
flock -n 9 || { echo "follow: another follow run holds the lock, skipped"; exit 0; }
git fetch -q github
old=$(git rev-parse refs/heads/main); new=$(git rev-parse refs/remotes/github/main)
if [ "$new" = "$old" ]; then echo "follow: up to date ${old:0:9}"; exit 0; fi
if ! git merge-base --is-ancestor "$old" "$new"; then
  echo "follow: not a fast-forward, kept ${old:0:9} (github/main ${new:0:9})"; exit 1
fi
# The same gate a push to the Pi's main runs (it extracts and tests the commit in its own temporary copy).
if out=$(printf '%s %s refs/heads/main\n' "$old" "$new" | "$GIT_DIR/hooks/pre-receive" 2>&1); then
  if [ $dry = 1 ]; then echo "follow: dry run, gate passed for ${new:0:9}, main stays ${old:0:9}"; echo "$out" | tail -3; exit 0; fi
  git update-ref refs/heads/main "$new" "$old"
  echo "follow: main ${old:0:9} -> ${new:0:9}, gate passed"
else
  echo "follow: gate failed for ${new:0:9}, kept ${old:0:9}"; echo "$out" | tail -8; exit 1
fi
