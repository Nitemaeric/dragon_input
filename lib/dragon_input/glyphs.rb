module DragonInput
  # Best-effort generic glyphs for the Ruby backend. Resolves an action to a
  # sprite path under a bundled style folder. On Steam, exact per-device glyphs
  # come from the native backend instead (capability :exact_glyphs).
  #
  # Bundled styles live at `<root>/<style>/<button>.png`, where <style> is
  # :xbox / :playstation / :switch / :keyboard and <root> is auto-detected:
  # drenv (>= 0.13) vendors the art to `vendor/dragon_input/sprites/...`, while a
  # direct copy keeps it at `sprites/dragon_input/glyphs`. Override with
  # `c.glyph_root('...')` in setup.
  #
  # The library ships the resolution logic and a keycap text fallback; drop your
  # own art (e.g. a Kenney input pack) into the folders above, or call
  # `render(args, ...)` which draws a labeled keycap when the sprite is absent.
  class Glyphs
    # Where the drenv-vendored bundled art lands (drenv >= 0.13 `include`).
    VENDORED_ROOT = 'vendor/dragon_input/sprites/dragon_input/glyphs'.freeze

    # A consumer's own art, and the library's own path when run un-vendored.
    LOCAL_ROOT = 'sprites/dragon_input/glyphs'.freeze

    STYLES = [:xbox, :playstation, :switch, :keyboard].freeze

    # Keyboard bindings with no per-key art reuse a cluster glyph. There's no
    # Kenney WASD glyph, so a :wasd directional binding shows the arrows cluster.
    KEYBOARD_GLYPH_ALIASES = { wasd: :arrows }.freeze

    # Human-facing short labels for the keycap fallback, per style.
    BUTTON_LABELS = {
      xbox: {
        a: 'A', b: 'B', x: 'X', y: 'Y', l1: 'LB', r1: 'RB', l2: 'LT', r2: 'RT',
        l3: 'LS', r3: 'RS', start: 'MENU', select: 'VIEW',
        up: 'U', down: 'D', left: 'L', right: 'R',
        left_analog: 'LS', right_analog: 'RS'
      },
      playstation: {
        a: 'X', b: 'O', x: '[]', y: '/\\', l1: 'L1', r1: 'R1', l2: 'L2', r2: 'R2',
        l3: 'L3', r3: 'R3', start: 'OPT', select: 'SHARE',
        up: 'U', down: 'D', left: 'L', right: 'R',
        left_analog: 'L', right_analog: 'R'
      },
      switch: {
        a: 'A', b: 'B', x: 'X', y: 'Y', l1: 'L', r1: 'R', l2: 'ZL', r2: 'ZR',
        l3: 'LS', r3: 'RS', start: '+', select: '-',
        up: 'U', down: 'D', left: 'L', right: 'R',
        left_analog: 'L', right_analog: 'R'
      }
    }.freeze

    def initialize(config)
      @config = config
      @path_cache = {}
    end

    # Roots searched per glyph, highest priority first: an explicit override, a
    # consumer's own `sprites/`, then the drenv-vendored bundled set. A specific
    # glyph resolves to the first root that actually has it — so games can
    # override individual glyphs and still fall back to the bundled art.
    def roots
      @roots ||= [@config.glyph_root, LOCAL_ROOT, VENDORED_ROOT].compact
    end

    # The primary (highest-priority) root — the nominal home for glyphs.
    def root
      roots.first
    end

    # Sprite path for an action's glyph in a given style. Prefers a keyboard
    # glyph when the pad is keyboard-only. Uses the action's :glyph hint if set,
    # otherwise the controller (or keyboard) binding button name.
    def path(_pad, action, style, backend = nil)
      button = glyph_button(action, style)
      return nil unless button

      resolve("#{style}/#{button}.png")
    end

    # Sprite path (or nil) for a raw button symbol in a style, following the same
    # root resolution as #path. The key-level counterpart of #path, which resolves
    # per action; keyboard cluster aliases still apply (e.g. :wasd -> :arrows).
    def key_glyph(style, button)
      return nil unless button

      button = KEYBOARD_GLYPH_ALIASES[button] || button if style == :keyboard
      resolve("#{style}/#{button}.png")
    end

    # Text label used when no sprite art is present. Handy for a keycap fallback.
    # Uses the raw binding (not the glyph alias) so e.g. :wasd reads "WASD".
    def label(action, style)
      button = raw_button(action, style)
      return '?' unless button

      if style == :keyboard
        button.to_s.upcase
      else
        table = BUTTON_LABELS[style] || BUTTON_LABELS[:xbox]
        table[button] || button.to_s.upcase
      end
    end

    # Path to the whole-device icon for a style (device/<style>.png), resolved
    # across the same roots. nil in-engine when the art is absent.
    def device_path(style)
      resolve("device/#{style}.png")
    end

    # Draw the device icon into rect; falls back to a short text label.
    def render_device(args, style, rect)
      icon = device_path(style)
      if icon
        args.outputs.sprites << rect.merge(path: icon)
      else
        render_keycap(args, style.to_s[0, 2].upcase, rect)
      end
    end

    # Convenience renderer: draws the glyph sprite when the art exists (in-engine
    # `path` returns nil when it doesn't), otherwise a labeled keycap fallback.
    # `rect` is { x:, y:, w:, h: }.
    def render(args, pad, action, style, rect)
      sprite_path = path(pad, action, style)
      if sprite_path
        args.outputs.sprites << rect.merge(path: sprite_path)
      else
        render_keycap(args, label(action, style), rect)
      end
    end

    # Coarse controller-type detection from whatever identity DragonRuby exposes.
    def self.style_from_controller(controller)
      return :xbox unless controller

      name = controller_name(controller)
      return :xbox unless name

      n = name.to_s.downcase
      return :playstation if n.include?('dualsense') || n.include?('dualshock') ||
                             n.include?('playstation') || n.include?('ps4') || n.include?('ps5')
      return :switch if n.include?('switch') || n.include?('nintendo') || n.include?('joy-con')

      :xbox
    end

    def self.controller_name(controller)
      return controller.name if controller.respond_to?(:name) && controller.name
      return controller.type if controller.respond_to?(:type) && controller.type

      nil
    rescue StandardError
      nil
    end

    private

    # Resolve `<style>/<button>.png` to a full path, searching roots in priority
    # order and falling back to the vendored bundled assets. In-engine we probe
    # for the file and return the first root that has it; if none do (or we're
    # off-engine and can't probe), we return the primary root's path so the
    # caller's own missing-sprite handling (a drawn keycap) still applies.
    # Cached per relative path.
    def resolve(rel)
      return @path_cache[rel] if @path_cache.key?(rel)

      @path_cache[rel] = pick_root(rel)
    end

    def pick_root(rel)
      if $gtk
        # In-engine we can check for real: return the first root that has the
        # file, or nil so the caller draws a keycap. (Don't guess a path —
        # DragonRuby renders a missing sprite as a checkerboard placeholder.)
        hit = roots.find { |r| $gtk.read_file("#{r}/#{rel}") }
        return hit && "#{hit}/#{rel}"
      end
      # Off-engine (can't probe): best-guess primary path for API callers.
      "#{root}/#{rel}"
    end

    # The binding a glyph represents, before any glyph aliasing. When a binding
    # lists several inputs (e.g. [:wasd, :arrows]), the first one names the glyph.
    def raw_button(action, style)
      return action.glyph_hint if action.glyph_hint

      button = if style == :keyboard
                 action.binding_for(:keyboard) || action.binding_for(:controller)
               else
                 action.binding_for(:controller) || action.binding_for(:keyboard)
               end
      button.is_a?(Array) ? button.first : button
    end

    # The button used to pick the sprite file (keyboard clusters aliased to their
    # available cluster glyph, e.g. :wasd -> :arrows).
    def glyph_button(action, style)
      button = raw_button(action, style)
      return nil unless button

      style == :keyboard ? (KEYBOARD_GLYPH_ALIASES[button] || button) : button
    end

    def render_keycap(args, text, rect)
      args.outputs.sprites << rect.merge(path: :solid, r: 40, g: 40, b: 48)
      args.outputs.borders << rect.merge(r: 200, g: 200, b: 210)
      args.outputs.labels << {
        x: rect[:x] + rect[:w] / 2,
        y: rect[:y] + rect[:h] / 2,
        text: text,
        size_px: keycap_text_size(text, rect),
        alignment_enum: 1,
        vertical_alignment_enum: 1,
        r: 235, g: 235, b: 240
      }
    end

    # Size the label to fit both the box height and its width, so multi-char
    # labels ("WASD", "SHARE") don't overflow the way a single "A" wouldn't.
    def keycap_text_size(text, rect)
      by_height = rect[:h] - 10
      len = [text.to_s.length, 1].max
      by_width = ((rect[:w] - 10).to_f / (len * 0.62)).to_i
      size = by_height < by_width ? by_height : by_width
      size < 10 ? 10 : size
    end
  end
end
