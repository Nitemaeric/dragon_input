# Bundled glyphs

These files are the library's **committed** glyph set. drenv (>= 0.13) ships them
to consumers as an asset (`include` in `drenv.toml`), so games get them
automatically with `drenv add` — no per-project step. Layout:

```
<style>/<button>.png
```

- `<style>` — one of `xbox`, `playstation`, `switch`, `keyboard`
- `<button>` — the button name from the action's binding, e.g. `a`, `b`, `r2`,
  `left_analog`, `space`, `w`

At runtime `DragonInput::Glyphs` auto-detects the vendored root
(`vendor/dragon_input/sprites/dragon_input/glyphs`) or this plain path; override
with `c.glyph_root('...')`. When a specific sprite is missing, `#render` falls
back to a drawn keycap, so a partial set still works.

## Source: Kenney "Input Prompts" (CC0)

The art comes from [kenney.nl/assets/input-prompts](https://kenney.nl/assets/input-prompts)
— CC0 (public-domain), no attribution required, commercial use fine.
**Maintainers** regenerate the committed subset from the pack (consumers never
run this):

```
ruby tools/import_kenney_glyphs.rb /path/to/kenney_input-prompts
# optional 2nd arg targets a different sprites dir
```

The importer fuzzy-matches Kenney's filenames (they rename between versions),
prefers the plain 64px `Default` variant, and reports anything it couldn't find
(those just fall back to a keycap). It handles the Nintendo A/B positional swap
and renames keyboard arrows (`keyboard_arrow_up` → `up.png`) for you. If your
pack version uses different names and many glyphs are missing, adjust the
candidate lists at the top of [`tools/import_kenney_glyphs.rb`](../../../tools/import_kenney_glyphs.rb).

You can also drop in any other pack by hand using the `<style>/<button>.png`
convention.

On the Steam backend, glyphs come from Steam's exact per-device database instead
(capability `:exact_glyphs`) — these bundled files are only used by the Ruby
fallback.
