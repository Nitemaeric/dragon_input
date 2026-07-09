module DragonInput
  # Native Steam Input backend. This is the Ruby half that *detects* and
  # *delegates to* the optional native shim (a separate Pro-only package,
  # e.g. dragon_input-steam) exposing the ISteamInput flat C API through
  # `$gtk.dlopen`. dragon_input never depends on it — the shim is discovered at
  # runtime; if it's absent (or SteamAPI_Init fails), we return false from
  # `available?` and DragonInput falls back to the Ruby backend.
  #
  # The shim is expected to register a module `SteamInput` responding to (at
  # least): init, shutdown, run_frame, connected_controllers,
  # activate_action_set(handle, set), digital_action_data(handle, action) ->
  # {down:, held:, up:}, analog_action_data(handle, action) -> {x:, y:},
  # trigger_vibration(handle, l, r), action_glyph(handle, action) -> path,
  # show_binding_panel(handle), capabilities -> [syms].
  #
  # Until the native package exists, none of that is present, so this backend
  # stays dormant by design.
  class SteamBackend
    # Full capability surface — the point of the native path. Actual set is
    # confirmed from the shim at runtime; this is the ceiling.
    CAPABILITIES = [
      :actions, :action_sets, :analog, :rumble, :gyro, :trackpad,
      :adaptive_triggers, :leds, :exact_glyphs,
      :steam_overlay_rebind, :community_configs
    ].freeze

    # True only when the native shim loaded AND SteamAPI_Init succeeded.
    def self.available?(config)
      shim = detect_shim(config)
      return false unless shim

      shim.respond_to?(:init) && shim.init
    rescue StandardError => e
      warn_once("Steam shim present but init failed: #{e}")
      false
    end

    # Locate the native shim. It self-registers a top-level `SteamInput` module
    # when its dylib/dll/so is `dlopen`'d. The shim package (or the game) is
    # responsible for that dlopen; we only *detect* the result — so a Ruby-only
    # build stays completely dormant with no dlopen noise at boot.
    def self.detect_shim(_config)
      return ::SteamInput if Object.const_defined?(:SteamInput)

      nil
    end

    def self.warn_once(msg)
      @warned ||= {}
      return if @warned[msg]

      @warned[msg] = true
      puts("[dragon_input] #{msg}")
    end

    def initialize(config, storage: nil)
      @config = config
      @shim = self.class.detect_shim(config)
      @handles = []
      @active_set = {}
      @config.pads.each_key { |pad| @active_set[pad] = @config.default_set }
    end

    def name
      :steam
    end

    # Capabilities as an Array used set-style (mruby has no bundled Set gem).
    def capabilities
      @shim.respond_to?(:capabilities) ? @shim.capabilities : CAPABILITIES
    end

    def tick(_args)
      @shim.run_frame if @shim.respond_to?(:run_frame)
      @handles = @shim.connected_controllers if @shim.respond_to?(:connected_controllers)
    end

    def digital(pad, action_name)
      handle = handle_for(pad)
      return Backend::INACTIVE_DIGITAL unless handle

      data = @shim.digital_action_data(handle, action_name.to_s)
      return Backend::INACTIVE_DIGITAL unless data

      {
        down: !!data[:down], held: !!data[:held], up: !!data[:up], active: true
      }
    end

    def analog(pad, action_name)
      handle = handle_for(pad)
      return Backend::INACTIVE_ANALOG unless handle

      data = @shim.analog_action_data(handle, action_name.to_s)
      return Backend::INACTIVE_ANALOG unless data

      { x: data[:x].to_f, y: data[:y].to_f, active: true }
    end

    def glyph(pad, action_name)
      handle = handle_for(pad)
      return nil unless handle && @shim.respond_to?(:action_glyph)

      @shim.action_glyph(handle, action_name.to_s)
    end

    # Steam supplies exact per-device glyphs; there's no single "style".
    def glyph_style(_pad)
      :steam
    end

    # Steam glyphs are per-action origins; there's no bundled per-button art to
    # resolve from a raw symbol, so the key-level lookup is unavailable here.
    def key_glyph(_pad_or_style, _button)
      nil
    end

    def render_glyph(args, pad, action_name, rect)
      path = glyph(pad, action_name)
      args.outputs.sprites << rect.merge(path: path) if path
    end

    # Steam has no bundled whole-device icon (glyphs are per-action/origin).
    def device_glyph(_pad)
      nil
    end

    def render_device_glyph(_args, _pad, _rect)
      nil
    end

    def rumble(pad, low_freq, high_freq)
      handle = handle_for(pad)
      return false unless handle && @shim.respond_to?(:trigger_vibration)

      @shim.trigger_vibration(handle, low_freq, high_freq)
      true
    end

    def activate_set(pad, set_name)
      handle = handle_for(pad)
      return false unless handle

      @active_set[pad] = set_name
      @shim.activate_action_set(handle, set_name.to_s) if @shim.respond_to?(:activate_action_set)
      true
    end

    def open_rebind(pad)
      handle = handle_for(pad)
      return false unless handle && @shim.respond_to?(:show_binding_panel)

      @shim.show_binding_panel(handle)
      true
    end

    def shutdown
      @shim.shutdown if @shim.respond_to?(:shutdown)
    end

    private

    # Map a logical pad to a Steam controller handle. Pads are ordered slots;
    # :one -> first connected controller, and so on.
    def handle_for(pad)
      slot = { one: 0, two: 1, three: 2, four: 3 }[pad]
      return nil unless slot

      @handles[slot]
    end
  end
end
