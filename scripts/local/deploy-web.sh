#!/bin/bash
# Deploys the website (web/) from the Mac to Cloudflare Pages (project rowfrog-web,
# rowfrog.com and www) while GitHub is down: the same steps as the deploy job in
# .github/workflows/website.yml, run on exactly the commit given (default main).
#
#   scripts/local/deploy-web.sh [commit]
#
# Needs Node 22 or later with npm, python3 with Pillow, and
# ~/.config/rowfrog/cloudflare.env with CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID.
# Optional there: SITE_USER and SITE_PASSWORD (set as the site's password again, and
# used to check the login; without them the password already stored in the Pages
# project stays) and MAPTILER_KEY (satellite pictures, written to app/config.json).
# Log: log/deploy-web.log. Never touches DNS.
set -euo pipefail

top=$(git rev-parse --show-toplevel)
commit=$(git rev-parse --verify "${1:-main}^{commit}")
env_file="${ROWFROG_CLOUDFLARE_ENV:-$HOME/.config/rowfrog/cloudflare.env}"
# The backend venv's Python (with Pillow) when there is one, so a python3 without it on PATH does not stop the build.
py=python3; [ -x "$top/backend/.venv/bin/python" ] && py="$top/backend/.venv/bin/python"
project=rowfrog-web
mkdir -p "$top/log"
exec > >(tee -a "$top/log/deploy-web.log") 2>&1
echo "== $(date -u +%FT%TZ) deploying the website from ${commit:0:8}"

[ -r "$env_file" ] || { echo "Missing $env_file (CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID)"; exit 1; }
set -a; . "$env_file"; set +a
for name in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
  [ -n "${!name:-}" ] || { echo "Missing $name in $env_file"; exit 1; }
done
command -v npm >/dev/null || { echo "npm is missing (MacPorts: sudo port install nodejs22 npm10)"; exit 1; }
node -e 'process.exit(Number(process.versions.node.split(".")[0]) < 22 ? 1 : 0)' || { echo "Node 22 or later needed, found $(node -v)"; exit 1; }

# Exactly that commit, away from the working tree.
work=$(mktemp -d "${TMPDIR:-/tmp}/rowfrog-web.XXXXXX")
trap 'rm -rf "$work"' EXIT
git -C "$top" archive "$commit" | tar -x -C "$work"

# wrangler from package-lock.json, kept between runs and installed again only when the lock changes.
# No install scripts (the folder has no .npmrc, hence the flag); only esbuild and workerd run theirs.
tools="$HOME/.cache/rowfrog-tools"
mkdir -p "$tools"
if ! cmp -s "$work/package-lock.json" "$tools/package-lock.json" || [ ! -x "$tools/node_modules/.bin/wrangler" ]; then
  cp "$work/package.json" "$work/package-lock.json" "$tools/"
  (cd "$tools" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci --no-audit --no-fund --ignore-scripts && npm rebuild --ignore-scripts=false esbuild workerd)
fi
wrangler="$tools/node_modules/.bin/wrangler"

# git archive has no history: the build number and commit for the footer and About come from here.
(cd "$work" && ROWFROG_BUILD=$(git -C "$top" rev-list --count "$commit") ROWFROG_COMMIT=${commit:0:7} "$py" scripts/build_web.py)
cd "$work/web"

if ! "$wrangler" pages project list | grep -q "\b$project\b"; then
  "$wrangler" pages project create "$project" --production-branch main
fi
if [ -n "${SITE_USER:-}" ] && [ -n "${SITE_PASSWORD:-}" ]; then
  printf '%s' "$SITE_USER" | "$wrangler" pages secret put SITE_USER --project-name "$project"
  printf '%s' "$SITE_PASSWORD" | "$wrangler" pages secret put SITE_PASSWORD --project-name "$project"
else
  echo "No SITE_USER/SITE_PASSWORD in $env_file: the password stored in the Pages project stays"
fi
if [ -n "${MAPTILER_KEY:-}" ]; then
  "$py" -c 'import json, os; print(json.dumps({"maptilerKey": os.environ["MAPTILER_KEY"]}))' > dist/app/config.json
  echo "Satellite pictures on: config.json written"
fi
# From web/, so wrangler finds web/functions (the password check).
"$wrangler" pages deploy dist --project-name "$project" --branch main --commit-hash "$commit" \
  --commit-message "$(git -C "$top" log -1 --format=%s "$commit")" --commit-dirty=true

# The site must stay locked and hidden.
sleep 20
fail=0
for base in "https://$project.pages.dev" https://rowfrog.com https://www.rowfrog.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$base/app/" || true)
  echo "$base/app/ without password: $code"
  [ "$code" = 401 ] || { echo "ERROR: $base answered $code without a password"; fail=1; }
done
curl -sI "https://$project.pages.dev/app/" | grep -i '^x-robots-tag: noindex' || { echo "ERROR: noindex header missing"; fail=1; }
if [ -n "${SITE_USER:-}" ] && [ -n "${SITE_PASSWORD:-}" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' -u "$SITE_USER:$SITE_PASSWORD" "https://$project.pages.dev/app/")
  echo "With password: $code"
  [ "$code" = 200 ] || { echo "ERROR: the site answered $code with the password"; fail=1; }
fi
"$wrangler" pages deployment list --project-name "$project" --environment production 2>/dev/null | head -8 || true
[ "$fail" = 0 ] && echo "== deployed ${commit:0:8}" || { echo "== deploy of ${commit:0:8} needs a look"; exit 1; }
