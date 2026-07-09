# require_relative so the entrypoint's siblings resolve relative to this file
# regardless of where it lives — symlinked at mygame/lib, vendored by drenv at
# vendor/dragon_input/lib, or loaded directly under MRI.
require_relative 'dragon_input/version'
require_relative 'dragon_input/config'
require_relative 'dragon_input/storage'
require_relative 'dragon_input/backend'
require_relative 'dragon_input/glyphs'
require_relative 'dragon_input/rebind'
require_relative 'dragon_input/ruby_backend'
require_relative 'dragon_input/steam_backend'
require_relative 'dragon_input/iga'

# Standalone DragonRuby input library: one action-based API, swappable backends
# (pure-Ruby fallback + optional native Steam Input). Game code only ever touches
# the DragonInput.* facade below.
#
#   def tick args
#     DragonInput.setup do |c|             # once — safe to guard with tick_count
#       c.action_set :gameplay do |s|
#         s.digital :fire, controller: :r2, keyboard: :space
#         s.analog  :move, controller: :left_analog, keyboard: :wasd
#       end
#     end if Kernel.tick_count == 0
#
#     DragonInput.tick args                # pump the active backend each frame
#     player.x += DragonInput.axis(:one, :move)[:x] * 5
#     shoot if DragonInput.just_pressed?(:one, :fire)
#   end
module DragonInput
  class << self
    attr_reader :backend, :config

    # Configure action sets and pick a backend. Pass a Config, or a block that
    # receives a fresh Config builder. Steam is used when the native shim is
    # present and initializes; otherwise the pure-Ruby backend (same game code
    # either way). `storage:` overrides persistence (tests inject in-memory).
    def setup(config = nil, storage: nil, &block)
      @config = config || Config.new
      block.call(@config) if block
      @backend = pick_backend(@config, storage)
      @backend
    end

    def pick_backend(config, storage = nil)
      if SteamBackend.available?(config)
        SteamBackend.new(config, storage: storage)
      else
        RubyBackend.new(config, storage: storage)
      end
    end

    # Pump the active backend for this frame. Call once per tick.
    def tick(args)
      ensure_setup!
      @backend.tick(args)
    end

    # ---- Digital queries ------------------------------------------------

    # Currently held (down or held). The everyday "is the button on" query.
    def pressed?(pad, action)
      d = digital(pad, action)
      d[:held] || d[:down]
    end

    # Edge: pressed this tick only.
    def just_pressed?(pad, action)
      digital(pad, action)[:down]
    end

    # Edge: released this tick only.
    def just_released?(pad, action)
      digital(pad, action)[:up]
    end

    # Raw digital hash { down:, held:, up:, active: }.
    def digital(pad, action)
      ensure_setup!
      @backend.digital(pad, action)
    end

    # ---- Analog ---------------------------------------------------------

    # Analog action -> { x:, y:, active: } with x/y in [-1, 1].
    def axis(pad, action)
      ensure_setup!
      @backend.analog(pad, action)
    end

    # ---- Glyphs / haptics / sets / rebind -------------------------------

    # Sprite path for an action's glyph (exact on Steam, generic on Ruby).
    def glyph(pad, action)
      ensure_setup!
      @backend.glyph(pad, action)
    end

    # Detected glyph style for a pad (:xbox/:playstation/:switch/:keyboard on
    # Ruby; :steam on the native backend). Useful for showing the right prompts.
    def glyph_style(pad)
      ensure_setup!
      @backend.glyph_style(pad)
    end

    # Sprite path (or nil) for a raw button symbol's glyph, in an explicit style
    # (:xbox/:playstation/:switch/:keyboard) or a pad's current device style. The
    # key-level counterpart of #glyph, which resolves per action.
    def key_glyph(pad_or_style, button)
      ensure_setup!
      @backend.key_glyph(pad_or_style, button)
    end

    # Convenience: draw an action's glyph into `rect` ({ x:, y:, w:, h: }),
    # using the sprite when the art exists and a drawn keycap fallback otherwise.
    def render_glyph(args, pad, action, rect)
      ensure_setup!
      @backend.render_glyph(args, pad, action, rect)
    end

    # Sprite path for the whole-device icon of the pad's current device
    # (keyboard / controller brand). nil when no art is available.
    def device_glyph(pad)
      ensure_setup!
      @backend.device_glyph(pad)
    end

    # Convenience: draw the current-device icon into `rect`.
    def render_device_glyph(args, pad, rect)
      ensure_setup!
      @backend.render_device_glyph(args, pad, rect)
    end

    def rumble(pad, low_freq, high_freq)
      ensure_setup!
      @backend.rumble(pad, low_freq, high_freq)
    end

    def activate_set(pad, set)
      ensure_setup!
      @backend.activate_set(pad, set)
    end

    # Capability query — the key seam. Returns true if the active backend
    # supports a feature symbol (see the locked vocabulary in Backend).
    def supports?(capability)
      ensure_setup!
      @backend.capabilities.include?(capability)
    end

    # Steam binding overlay on the Steam backend; our in-game rebind UI on Ruby.
    def open_rebind(pad)
      ensure_setup!
      @backend.open_rebind(pad)
    end

    # Which backend is active (:ruby or :steam) — handy for diagnostics.
    def backend_name
      ensure_setup!
      @backend.name
    end

    # Emit the Steam IGA (VDF) file text from the current config.
    def to_iga
      ensure_setup!
      IGA.generate(@config)
    end

    private

    def ensure_setup!
      raise 'DragonInput.setup must be called before use' unless @backend
    end
  end
end
