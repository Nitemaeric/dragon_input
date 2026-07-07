#!/usr/bin/env bash
#
# Run the dragon_input smoke suite under DragonRuby's mruby-patched interpreter.
#
# The standalone `mruby` CLI has no `require`/`require_relative` (DragonRuby
# provides those in its engine), so we preload every file with -r in dependency
# order: the lib sub-files exactly as lib/dragon_input.rb requires them (never
# dragon_input.rb itself, whose require_relatives would raise), then the test
# support (fakes + assertion harness). test/run.rb is the main script and holds
# the assertions.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MRUBY="$ROOT/tmp/mruby/bin/mruby"
if [ ! -x "$MRUBY" ]; then
  "$ROOT/script/build-mruby.sh"
fi

# Order mirrors lib/dragon_input.rb (support last so it can reference nothing).
preload=(
  lib/dragon_input/version.rb
  lib/dragon_input/config.rb
  lib/dragon_input/storage.rb
  lib/dragon_input/backend.rb
  lib/dragon_input/glyphs.rb
  lib/dragon_input/rebind.rb
  lib/dragon_input/ruby_backend.rb
  lib/dragon_input/steam_backend.rb
  lib/dragon_input/iga.rb
  test/support.rb
)

mruby_args=()
for file in "${preload[@]}"; do
  mruby_args+=(-r "$file")
done

exec "$MRUBY" "${mruby_args[@]}" test/run.rb
