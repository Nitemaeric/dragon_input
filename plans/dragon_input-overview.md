# dragon_input — plan

> Standalone DragonRuby input library: one action-based API, swappable backends
> (pure-Ruby fallback + native Steam Input). This doc is self-contained so a
> fresh session can pick it up cold.

Status: **Milestones 1, 2 & 4 implemented** (pure-Ruby core, capability surface
+ graceful degradation, config→IGA generation); Steam backend detection scaffold
in place, native shim (Milestone 3) + Conjuration glue (Milestone 5) still to do.
Owner: Nitemaeric (individual).

---

## Background (context a new session needs)

- **DragonRuby GTK** is a commercial game engine that runs **mruby** (a minimal
  Ruby). Games have `mygame/app/main.rb` with a `def tick args` loop. Built-in
  controller input is read each frame via `args.inputs.controller_one`, etc.
- DragonRuby comes in tiers: **standard** (itch.io), **indie**, **pro**
  (dragonruby.org). **Native C/C++ extensions require Pro** and are loaded with
  `$gtk.dlopen 'name'`, expecting a compiled binary in `native/<platform>/`
  (e.g. `native/macos/name.dylib`, `native/windows-amd64/name.dll`,
  `native/linux-amd64/name.so`). `dragonruby-bind` (mkbind) helps generate the
  mruby glue from C headers.
- **mruby has no FFI** (no Fiddle / no `ffi` gem, and you can't add mruby gems to
  the prebuilt VM). `$gtk.dlopen` is **not** a general FFI — it loads a
  purpose-built extension, not arbitrary C functions by signature. So the only
  way to reach a native library is a compiled shim that registers mruby methods.
- **Steam Input** = Valve's controller-abstraction API (`ISteamInput`, formerly
  `ISteamController`) in the Steamworks SDK. You bind abstract **actions**, and
  Steam maps any controller (Xbox / DualSense / Switch / Steam Deck / generic)
  onto them, plus remapping overlay, community configs, exact per-device glyphs,
  gyro/trackpad, haptics, LEDs, adaptive triggers. It's backed by the Steam
  client + the native `steam_api` library (talks over IPC) — **cannot be
  reimplemented in Ruby**; you can only *bind* to it.
  - Steamworks ships a **flat C ABI** (`steam_api_flat.h`, e.g.
    `SteamAPI_ISteamInput_GetDigitalActionData(...)`) intended for non-C++
    bindings — this is what the native shim should call.
  - Action config is authored as an **In-Game Actions (IGA)** file (VDF).
- **Reference implementation**: `github:Lyniat/oservice` binds Steam *networking*
  (`ISteamNetworking`/UNet) to DragonRuby the same way — C++ shim, `$gtk.dlopen`,
  `native/<platform>/` binaries, Steam sidecars (`steam_api64.dll`,
  `libsteam_api.*`). Note it ships **no prebuilt binaries** (build-from-source
  only). dragon_input's Steam shim should learn from it but **publish prebuilt
  release binaries** so it's consumable.

## Why this is its own library (the decision)

Conjuration (Nitemaeric's DragonRuby **framework**) could host this, but we
decided to **split it out** so users needing just input aren't forced to adopt
the whole framework. Conjuration and dragon_input should interoperate well but
**must not be coupled**.

**Dependency direction — everything points *into* dragon_input; it depends on
nothing:**

- Conjuration → (optionally) depends on → **dragon_input**
- Steam native shim → discovered at runtime by → **dragon_input**
- **dragon_input** → depends on neither

## Architecture — three artifacts

1. **`dragon_input`** (this repo) — **pure Ruby**, standalone. The unified
   action-based API + the Ruby backend + a bundled generic glyph set. Works on
   any tier, in or out of Steam, with zero build step. Anyone can `drenv add` it.
2. **Steam native shim** (separate package, e.g. `dragon_input-steam`) —
   **optional, Pro/Steam only**. A thin C/C++ extension over the `ISteamInput`
   flat C API, `dlopen`'d, placed in `native/<platform>/`. Runtime-*detected* by
   dragon_input; never required by it. Ships prebuilt per-platform binaries as
   release assets.
3. **Conjuration ↔ dragon_input glue** (optional, lives on Conjuration's side or
   a tiny bridge) — hooks dragon_input into Conjuration's tick/scene lifecycle so
   framework users get first-class input. Depends on dragon_input, not vice
   versa.

## Public API (game code only touches this)

```ruby
DragonInput.setup(config)                 # pick backend at boot, graceful fallback
DragonInput.tick(args)                    # pump each frame (RunFrame / read raw)
DragonInput.pressed?(pad, :fire)          # digital action -> bool
DragonInput.axis(pad, :move)              # analog action -> {x:, y:} in [-1,1]
DragonInput.glyph(pad, :fire)             # sprite path (exact on Steam, generic on Ruby)
DragonInput.rumble(pad, left, right)
DragonInput.supports?(:gyro)             # capability query — the key seam
DragonInput.open_rebind(pad)             # Steam binding overlay OR our in-game UI
```

## Backend contract (both backends implement)

```
digital(pad, action)   -> { pressed?, active? }
analog(pad, action)    -> { x, y, active? }
glyph(pad, action)     -> sprite path
rumble(pad, l, r)
activate_set(pad, set)
capabilities           -> Set of symbols
open_rebind(pad)
tick(args)             -> pump the backend for this frame
```

Backend selection:

```ruby
def self.pick_backend(config)
  SteamBackend.available? ? SteamBackend.new(config) : RubyBackend.new(config)
end
```

`SteamBackend.available?` = native shim `dlopen`'d **and** `SteamAPI_Init`
succeeded. Otherwise the pure-Ruby backend. Same game binary works for Steam and
non-Steam players; a Standard-tier dev simply never ships the shim.

## Capability tiers (`supports?`) — don't flatten to lowest common denominator

The core action model is portable; Steam has extras the Ruby backend can't
match. Gate those and degrade gracefully.

| Feature                     | Ruby backend                  | Steam backend        |
| --------------------------- | ----------------------------- | -------------------- |
| Actions, action sets, analog| full                          | full                 |
| Rebinding                   | our in-game UI                | Steam overlay (`ShowBindingPanel`) |
| Glyphs                      | best-effort (bundled generic) | exact per-device     |
| Gyro / trackpad / adaptive  | none                          | yes                  |
| Community/official configs  | none                          | yes                  |
| Controller coverage         | DragonRuby raw input          | Steam device DB      |

This delivers the intended story: **Standard users get keymapping; upgrading to
a Pro+Steam build lights up the rest with zero game-code changes.**

## Ruby backend notes

- Implemented over `args.inputs.controller_one`/`controller_two`/… (buttons,
  sticks, triggers, keyboard). Map raw inputs → actions via config.
- Owns its **own remapping UI + persisted config** (there's no Steam overlay).
- Glyphs: bundle a generic sprite set (Xbox / PlayStation / Switch / keyboard);
  pick by whatever device identity DragonRuby exposes (limited — best effort).
- No native code, so it can live anywhere and ships everywhere.

## Steam backend notes

- Thin native shim over `ISteamInput` **flat C API**; keep it minimal (raw
  calls: `get_connected_controllers`, `activate_action_set`,
  `get_digital_action_data`, `get_analog_action_data`, `trigger_vibration`,
  glyph/origin lookups, motion). Put ergonomics in Ruby (shared across backends).
- Flow: `Init` → `RunFrame` each tick → `GetConnectedControllers` → per pad
  `ActivateActionSet` → read digital/analog → glyphs/haptics/motion → `Shutdown`.
- Package like oservice but **publish prebuilt release binaries** per platform.
  Requires DragonRuby **Pro** to build. Steam sidecars (`steam_api*`) must sit in
  the right places.

## One config, one source of truth

Define action sets once (Ruby DSL or TOML). The Ruby backend reads it directly;
for Steam, **generate the IGA (VDF) file from the same config** so you never
hand-maintain two mappings.

## Distribution / drenv angle

- The pure-Ruby `dragon_input` is a normal `drenv add github:Nitemaeric/dragon_input`
  target once it follows drenv's entrypoint convention (`lib/dragon_input.rb`, or
  a `[package]` in its root `drenv.toml`). See drenv's dependency model.
- **The Steam shim is a native extension — drenv does NOT support native deps
  today** (drenv vendors `.rb` + generates `require`; native libs need
  per-platform binaries in `native/<platform>/` + `$gtk.dlopen`, no require).
  Tracking idea only; unrelated to shipping the Ruby lib. (This is a known drenv
  gap discussed in the drenv repo.)

## Naming

- Library: **`dragon_input`** (reads standalone; deliberately NOT `conjuration-*`
  so it doesn't imply coupling).
- Ruby namespace: `DragonInput` (final call TBD).
- Steam shim package name TBD (e.g. `dragon_input-steam`).

## Open questions / decisions to make

- [ ] Config format: Ruby DSL vs TOML/JSON. (Leaning: Ruby DSL for authoring,
      able to emit IGA VDF.)
- [ ] Exact `supports?` capability vocabulary — lock this early (it's the seam).
- [x] Glyph asset set + license: **Kenney "Input Prompts" (CC0)**, pulled in via
      `tools/import_kenney_glyphs.rb` into `sprites/dragon_input/glyphs/<style>/<button>.png`;
      keycap fallback when art is absent. Controller type detected best-effort
      from `controller.name`/`.type` (`Glyphs.style_from_controller`).
- [ ] Multi-controller / local-multiplayer model (per-`pad` handles).
- [ ] How Conjuration's glue attaches (tick hook? scene component?).
- [ ] Where the Steam shim lives + its binary-publishing pipeline (CI release
      assets per platform).

## Suggested first milestones

1. [x] **Pure-Ruby core, runnable today** — `DragonInput.setup/tick/pressed?/axis`,
   action-set config, `RubyBackend` over `args.inputs.controller_*`, a minimal
   in-game rebind screen, generic glyphs. No native code. Ship + `drenv add`.
2. [x] **Capability surface + graceful degradation** — `supports?`, `open_rebind`
   dispatch, glyph fallback.
3. [ ] **Steam shim (separate package)** — thin C binding over the flat API,
   `dlopen`, prebuilt release binaries; `SteamBackend` detects + delegates.
   (Ruby-side detection + delegation is done in `lib/dragon_input/steam_backend.rb`;
   the native package is the remaining work.)
4. [x] **Config → IGA generation** — one source of truth (`DragonInput.to_iga`).
5. [ ] **Conjuration glue** — optional first-class integration.

## Decisions locked during implementation

- **Config format**: Ruby DSL (`Config`/`ActionSet`/`Action`), able to emit IGA
  VDF via `DragonInput::IGA`.
- **Namespace**: `DragonInput`.
- **Capability vocabulary** (the seam): `:actions`, `:action_sets`, `:analog`,
  `:rumble`, `:gyro`, `:trackpad`, `:adaptive_triggers`, `:leds`,
  `:exact_glyphs`, `:in_game_rebind`, `:steam_overlay_rebind`,
  `:community_configs`.
- **Pads**: logical handles `:one`..`:four` + `:keyboard`; `:one` merges
  controller one + keyboard + mouse by default, overridable via `c.pad(...)`.
- **Persistence**: rebinds saved through a `Storage` seam (`$gtk` file API in
  DragonRuby, in-memory in tests) to `dragon_input_bindings.json`.
- **Steam shim contract**: self-registers a `SteamInput` mruby module; surface
  documented in `README.md` / `lib/dragon_input/steam_backend.rb`.

## drenv packaging notes (learned running the `demo/`)

- `drenv.toml` declares `root = "lib"` + `entrypoint = "dragon_input.rb"` so drenv
  vendors **only `lib/`** into `vendor/dragon_input/` (not the whole repo). The
  library's internal requires use **`require_relative`** so they resolve wherever
  drenv puts them. Consumers `require 'app/drenv_bundle.rb'` (drenv-generated).
- **mruby gotchas fixed**: no `defined?` (dispatched as a method in DRGTK mruby —
  guard globals with bare `$gtk`, constants with `Object.const_defined?`); no
  `Set` / `require 'set'` (capabilities are Arrays used set-style); no core
  `#to_json` (hand-rolled `encode_json`); `args.outputs.solids` is deprecated in
  7.13 → use `sprites << { path: :solid }`.
- **Assets** (drenv >= 0.13): `drenv.toml` declares `include = ["sprites"]`;
  drenv copies them to `mygame/vendor/dragon_input/sprites/...` alongside the
  code. The bundled CC0 glyphs are **committed** in the repo so they ship to
  consumers automatically — no per-project import. `Glyphs` resolves each glyph
  across roots in priority order (config `c.glyph_root` → local
  `sprites/dragon_input/glyphs` → vendored bundled set), **falling back to the
  vendored assets** per glyph, so games can override individual glyphs and
  inherit the rest. (Engine can't follow dir symlinks, so vendoring is the path.)
- **Ancestor path dep**: because `demo/` is inside this repo, `drenv add path:..`
  must pass `-n dragon_input` (drenv otherwise mis-derives the name from `../..`
  and writes malformed TOML).
- Runnable sample lives in `demo/` (DragonRuby **Pro 7.13**); launch with
  `drenv run`. Verified: clean boot, glyphs resolve to 64×64 Kenney sprites.
- Demo thesis: **device-aware prompts** — `glyph_style`/`glyph`/`render_glyph`
  follow the *last device the player used* (RubyBackend tracks per-pad active
  device from bound-input activity; `active_style` → :keyboard vs controller
  brand). This is the library's most distinctive, demonstrable feature.
