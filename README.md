# dragon_input

> Standalone DragonRuby input library: one action-based API, swappable backends
> (pure-Ruby fallback + optional native Steam Input).

`dragon_input` gives DragonRuby games a single, action-based input API. Bind
abstract **actions** (`:fire`, `:move`) once; the library reads them from
whatever's available. It ships a **pure-Ruby backend** that works on every
DragonRuby tier with zero build step, and detects an **optional native Steam
Input backend** at runtime to light up exact glyphs, gyro, haptics, the Steam
rebind overlay, and community configs — with **no game-code changes**.

The library depends on nothing. Conjuration (or any framework) may depend on it;
it never depends back.

## Install

```
drenv add github:Nitemaeric/dragon_input
```

drenv vendors the library under `mygame/vendor/dragon_input` and generates
`app/drenv_bundle.rb`. Add its require to the top of `app/main.rb`:

```ruby
require 'app/drenv_bundle.rb'
```

(The package declares `root = "lib"` / `entrypoint = "dragon_input.rb"`, and its
internal requires use `require_relative`, so it loads correctly from wherever
drenv vendors it.)

## Quick start

```ruby
require 'app/drenv_bundle.rb'   # loads dragon_input (see Install)

def tick args
  if Kernel.tick_count == 0
    DragonInput.setup do |c|
      c.default_set :gameplay
      c.action_set :gameplay do |s|
        s.digital :fire,  controller: :r2,          keyboard: :space, mouse: :left
        s.digital :jump,  controller: :a,           keyboard: :j
        s.analog  :move,  controller: :left_analog, keyboard: :wasd
      end
    end
  end

  DragonInput.tick args                      # pump the active backend each frame

  args.state.player.x += DragonInput.axis(:one, :move)[:x] * 5
  shoot(args) if DragonInput.just_pressed?(:one, :fire)
end
```

## Demo

A runnable DragonRuby project lives in [`demo/`](demo/mygame/app/main.rb). It has
one thesis: **bind actions once, and the prompts follow the device you last
touched.** Press keys or a controller (or move WASD vs the left stick) and every
button glyph swaps instantly between keyboard and controller art — with zero
per-device code in the game. From the `demo/` directory:

```
drenv add path:.. -n dragon_input   # one-time: vendor the library + its glyphs
drenv run
```

drenv (>= 0.13) vendors both the code and the bundled glyph art (declared via
`include` in the library's `drenv.toml`), so there's no separate asset step.
(`-n dragon_input` is needed because the demo lives inside this repo, so the path
dependency is an ancestor; drenv otherwise mis-derives the name from `../..`.)

## Public API

Game code only ever touches this facade.

| Call | Does |
| --- | --- |
| `DragonInput.setup(config) { \|c\| ... }` | Configure action sets, pick a backend (graceful fallback). |
| `DragonInput.tick(args)` | Pump the active backend each frame. |
| `DragonInput.pressed?(pad, :fire)` | Digital action currently on → bool. |
| `DragonInput.just_pressed?(pad, :fire)` | Pressed this tick only (edge). |
| `DragonInput.just_released?(pad, :fire)` | Released this tick only (edge). |
| `DragonInput.axis(pad, :move)` | Analog → `{ x:, y:, active: }` in `[-1, 1]`. |
| `DragonInput.glyph(pad, :fire)` | Sprite path for the action, in the pad's current device style. |
| `DragonInput.glyph_style(pad)` | Device-aware style the prompts should use — `:keyboard` / `:xbox` / `:playstation` / `:switch`, following the last device the player used. |
| `DragonInput.render_glyph(args, pad, :fire, rect)` | Draw the glyph (sprite, or a keycap fallback) into `rect`. |
| `DragonInput.device_glyph(pad)` / `render_device_glyph(args, pad, rect)` | Whole-device icon for the current device (keyboard / controller brand). |
| `DragonInput.rumble(pad, low, high)` | Haptics (Steam only; no-op on Ruby). |
| `DragonInput.activate_set(pad, :menu)` | Switch the pad's active action set. |
| `DragonInput.supports?(:gyro)` | Capability query — **the key seam**. |
| `DragonInput.open_rebind(pad)` | Steam overlay, or our in-game rebind UI. |
| `DragonInput.to_iga` | Emit the Steam IGA (VDF) file text from the config. |

**Pads** are logical handles: `:one`..`:four` and `:keyboard`. By default `:one`
merges controller one + keyboard + mouse (single-player friendly); `:two`..`:four`
each map to their own controller. Override with `c.pad(:one, [:controller_one])`.

## Capabilities — don't flatten to the lowest common denominator

The core action model is portable; Steam has extras the Ruby backend can't
match. Gate them with `supports?` and degrade gracefully.

| Feature | Ruby backend | Steam backend |
| --- | --- | --- |
| Actions, action sets, analog | full | full |
| Rebinding | our in-game UI (`:in_game_rebind`) | Steam overlay (`:steam_overlay_rebind`) |
| Glyphs | best-effort generic | exact per-device (`:exact_glyphs`) |
| Rumble / gyro / trackpad / adaptive triggers / LEDs | none | yes |
| Community / official configs | none | yes (`:community_configs`) |

Locked capability vocabulary (the seam): `:actions`, `:action_sets`, `:analog`,
`:rumble`, `:gyro`, `:trackpad`, `:adaptive_triggers`, `:leds`, `:exact_glyphs`,
`:in_game_rebind`, `:steam_overlay_rebind`, `:community_configs`.

```ruby
DragonInput.rumble(:one, 0.6, 0.6) if DragonInput.supports?(:rumble)
```

Same game binary works for Steam and non-Steam players; a Standard-tier dev
simply never ships the native shim and gets the Ruby backend automatically.

## One config, one source of truth

Action sets are defined once. The Ruby backend reads the config directly; for
Steam, generate the **In-Game Actions (IGA)** VDF from the *same* config so you
never hand-maintain two mappings:

```ruby
$gtk.write_file('game_actions_480.vdf', DragonInput.to_iga)   # in DragonRuby
```

Digital actions become `Button` entries, analog actions become `StickPadGyro`
`joystick_move` entries, with a `localization` block for the overlay titles.

## Glyphs

dragon_input **bundles** a glyph set (Kenney's
[Input Prompts](https://kenney.nl/assets/input-prompts), **CC0** — no attribution,
commercial-OK) and ships it as a drenv asset, so `drenv add` delivers the art
too — nothing to do per project. Each glyph resolves to `<root>/<style>/<button>.png`
(`style` ∈ `xbox`/`playstation`/`switch`/`keyboard`), searching roots in priority
order per glyph and **falling back to the vendored bundled art**:

1. `c.glyph_root('...')` if set,
2. the consumer's own `sprites/dragon_input/glyphs` (drop a file here to override
   one glyph),
3. the drenv-vendored bundled set.

If a specific glyph isn't found in any root, `render_glyph` draws a keycap. So
games can override individual glyphs and still inherit everything they don't.

**Device-aware:** the style follows the last device the player used (see
`glyph_style` above), so prompts swap between keyboard and controller art on the
fly. A whole-device icon per style lives at `<root>/device/<style>.png`
(`render_device_glyph`). Keyboard directional bindings with no per-key art reuse
a cluster glyph — e.g. `:wasd` shows the arrows cluster (its keycap label still
reads "WASD").

The bundled art is regenerated from the pack with the importer (maintainers only —
consumers never run this):

```
ruby tools/import_kenney_glyphs.rb /path/to/kenney_input-prompts   # -> sprites/dragon_input/glyphs
```

It fuzzy-matches Kenney's filenames, prefers the plain 64px `Default` variant,
handles the Nintendo A/B positional swap and keyboard arrow renaming, and reports
anything it couldn't find. Override the lookup dir with `c.glyph_root('...')`. See
[the glyphs README](sprites/dragon_input/glyphs/README.md).

## The optional Steam backend

`SteamBackend` is the Ruby half that **detects and delegates to** a separate,
Pro-only native package (e.g. `dragon_input-steam`) — a thin C/C++ shim over the
`ISteamInput` **flat C API**, `dlopen`'d and placed in `native/<platform>/`. When
that shim is present and `SteamAPI_Init` succeeds, `DragonInput.setup` picks it;
otherwise it stays dormant and the Ruby backend is used. `dragon_input` never
depends on the shim — the direction is one-way.

The shim self-registers a `SteamInput` module. Expected surface:

```
init, shutdown, run_frame, connected_controllers,
activate_action_set(handle, set), digital_action_data(handle, action) -> {down:,held:,up:},
analog_action_data(handle, action) -> {x:,y:}, trigger_vibration(handle, l, h),
action_glyph(handle, action) -> path, show_binding_panel(handle), capabilities -> [syms]
```

That package (with prebuilt per-platform release binaries) is tracked separately;
this repo is complete and useful on its own without it.

## Development

The library's logic and Ruby backend are covered by a smoke suite that fakes
`args` and runs under **DragonRuby's mruby-patched** interpreter (the real
runtime — so it catches mruby-only issues MRI would miss), no engine binary
needed:

```
script/test.sh
```

It builds `DragonRuby/mruby-patched` once (pinned commit, cached under `tmp/`),
then preloads the library + test support and runs `test/run.rb`. CI runs the
same on every push/PR.

## Status

- [x] Pure-Ruby core: `setup`/`tick`/`pressed?`/`just_pressed?`/`axis`, action
      sets, `RubyBackend` over `args.inputs.controller_*` + keyboard + mouse.
- [x] In-game rebind overlay + persisted overrides.
- [x] Capability surface (`supports?`) + graceful degradation + `open_rebind`
      dispatch + glyph fallback.
- [x] Config → IGA (VDF) generation.
- [x] `SteamBackend` runtime detection + delegation (dormant until the native
      shim ships).
- [ ] Native Steam shim package with prebuilt binaries (separate repo, Pro-only).
- [ ] Conjuration glue (optional, lives on Conjuration's side).

See [`plans/dragon_input-overview.md`](plans/dragon_input-overview.md) for the
full design rationale.
