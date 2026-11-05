#!/usr/bin/env bash
# Builds the web app and publishes it on Cloudflare Pages
# (finza.pages.dev). release.sh runs it after every Android release so
# both stay on the same version; it also works on its own.
# Needs Flutter in the PATH, Node 18 or newer for wrangler and a wrangler login
# for the Cloudflare account that owns the Pages project.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/budget"
project="finza"
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-7e9f0b051b89601a14b6dad6a5084f80}"
# This login lives apart from the default one, which belongs to another account
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config/wrangler-personal}"
# The Node that nvm points to globally is too old for wrangler
if [ -n "${APPDATA:-}" ] && command -v cygpath > /dev/null; then
  node24="$(cygpath -u "$APPDATA")/nvm/v24.15.0"
  [ -d "$node24" ] && export PATH="$node24:$PATH"
fi

(cd "$app" && flutter build web --release --no-wasm-dry-run)
# From the build folder so wrangler's cache stays out of the repo
(cd "$app/build" && npx -y wrangler@4.45.0 pages deploy "$app/build/web" \
  --project-name "$project" --branch main --commit-dirty=true)
echo "Web published: $(sed -n 's/^version: //p' "$app/pubspec.yaml")"
