#!/usr/bin/env bash
# Runs a GitHub workflow's job on the Raspberry Pi while GitHub is down (Nov 2026),
# with the same script and settings as the workflow, on the newest main of the Pi's
# repository (~/git/rowfrog.git), in a temporary copy, with the publishing job's
# Python environment (~/venv). Reports go to ~/reports/ instead of a GitHub issue.
#   run.sh model-check [model_check.py options]   (model-check.yml; timer 04:40 and 16:40 UTC)
#   run.sh budget-check                            (budget-check.yml; timer 06:10 UTC)
# Installed on the Pi as ~/rowfrog-pi/run.sh; timers in scripts/local/pi/systemd/.
set -euo pipefail
job=${1:?usage: run.sh model-check|budget-check}; shift
HOME_DIR=${HOME_DIR:-/home/rowfrog}
BARE=$HOME_DIR/git/rowfrog.git
VENV=$HOME_DIR/venv
REPORTS=$HOME_DIR/reports
export PATH="$HOME_DIR/.local/bin:$PATH"
mkdir -p "$REPORTS"
src=$(mktemp -d "/tmp/rowfrog-$job.XXXXXX")
trap 'rm -rf "$src"' EXIT
git -C "$BARE" archive main | tar -x -C "$src"
echo "Code: $(git -C "$BARE" log --oneline -1 main)"
export PYTHONPATH="$src/backend"
cd "$src"
case "$job" in
  model-check)
    # The stored forecasts live on the model-check branch, as on GitHub.
    store=$HOME_DIR/model-check-store
    [ -d "$store/.git" ] || git clone -q -b model-check "$BARE" "$store"
    git -C "$store" pull -q --ff-only origin model-check
    # The forecasts the publisher wrote (~/site/v1) are scored too, as model "app".
    app=()
    [ -d "$HOME_DIR/site/v1" ] && app=(--app-dir "$HOME_DIR/site/v1")
    "$VENV/bin/python" scripts/model_check.py "$store" "${app[@]}" "$@"
    cd "$store"
    git add -A
    if git diff --cached --quiet; then
      echo "Nothing new"
    else
      git -c user.name=RowFrog -c user.email=344322998+RowFrog@users.noreply.github.com \
        commit -q -m "Model check $(date -u +%Y-%m-%dT%H:%MZ)"
      git push -q origin HEAD:model-check
    fi
    cp report.md "$REPORTS/model-check-latest.md"
    # On GitHub the Monday 04:40 run posted the report on the "Model check" issue; here it is kept, dated.
    if [ "$(date -u +%u)" = 1 ] && [ "$(date -u +%H)" -lt 12 ]; then cp report.md "$REPORTS/model-check-$(date -u +%F).md"; fi
    echo "Report: $REPORTS/model-check-latest.md"
    ;;
  budget-check)
    out="$REPORTS/budget-$(date -u +%F).md"
    set +e
    "$VENV/bin/python" scripts/budget_check.py "$out"
    status=$?
    set -e
    cp "$out" "$REPORTS/budget-latest.md"
    # On GitHub a warning (or the 1st of the month) became a comment on the "Usage limits" issue.
    [ "$status" = 0 ] || echo "ATTENTION: a usage limit needs a look: $out"
    ;;
  *)
    echo "unknown job: $job (model-check, budget-check)"; exit 2 ;;
esac
