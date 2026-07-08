#!/usr/bin/env bash
#
# Build the demo's HTML5 (WASM) export and deploy it to the `gh-pages` branch,
# which GitHub Pages serves at https://nitemaeric.github.io/dragon_input/.
#
# This is a LOCAL step: it needs DragonRuby Pro (the engine + dragonruby-publish
# live under demo/), which is licensed and not committed, so CI can't do it.
# `gh-pages` is an orphan deploy branch, force-pushed fresh each time — it never
# touches main. Publishing the WASM build is the intended distribution path for a
# DragonRuby game (it ships no dev toolkit / SDK).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="$ROOT/demo"
PUBLISH="$DEMO/dragonruby-publish"

if [ ! -x "$PUBLISH" ]; then
  echo "error: $PUBLISH not found — this needs the DragonRuby Pro engine in demo/." >&2
  exit 1
fi

cd "$DEMO"
drenv bundle >/dev/null 2>&1 || true       # vendor the lib + glyphs (path dep)
rm -f builds/dragon-input-demo-html5.zip
"$PUBLISH" --platforms=html5 --package mygame

site="$(mktemp -d)"
trap 'rm -rf "$site"' EXIT
unzip -q builds/dragon-input-demo-html5.zip -d "$site"
touch "$site/.nojekyll"                     # don't let Pages run Jekyll on the build

rev="$(git -C "$ROOT" rev-parse --short HEAD)"
remote="$(git -C "$ROOT" remote get-url origin)"

cd "$site"
git init -q
git checkout -q -b gh-pages
git add -A
git -c user.name="deploy-bot" -c user.email="deploy@local" \
    commit -q -m "Deploy demo html5 (main@${rev})"
git remote add origin "$remote"
git push -q -f origin gh-pages

echo "Deployed. If Pages is enabled for the gh-pages branch:"
echo "  https://nitemaeric.github.io/dragon_input/"
