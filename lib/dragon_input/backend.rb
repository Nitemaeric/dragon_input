module DragonInput
  # The contract both backends implement. Game code never touches a backend
  # directly — it goes through the DragonInput.* facade, which delegates here.
  #
  # Digital reads return a small hash so callers can distinguish edges:
  #   { down:, held:, up:, active: }
  #     down   - pressed this tick (edge)
  #     held   - currently pressed
  #     up     - released this tick (edge)
  #     active - the action exists in the pad's active set
  #
  # Analog reads return:
  #   { x:, y:, active: }  with x/y in [-1, 1]
  class Backend
    INACTIVE_DIGITAL = { down: false, held: false, up: false, active: false }.freeze
    INACTIVE_ANALOG  = { x: 0.0, y: 0.0, active: false }.freeze

    def digital(_pad, _action)
      raise NotImplementedError
    end

    def analog(_pad, _action)
      raise NotImplementedError
    end

    def glyph(_pad, _action)
      raise NotImplementedError
    end

    def key_glyph(_pad_or_style, _button)
      raise NotImplementedError
    end

    def rumble(_pad, _low_freq, _high_freq)
      raise NotImplementedError
    end

    def activate_set(_pad, _set)
      raise NotImplementedError
    end

    # Returns a Set of capability symbols. Locked vocabulary (the seam):
    #   :actions :action_sets :analog :rumble :gyro :trackpad
    #   :adaptive_triggers :leds :exact_glyphs :in_game_rebind
    #   :steam_overlay_rebind :community_configs
    def capabilities
      raise NotImplementedError
    end

    def open_rebind(_pad)
      raise NotImplementedError
    end

    def tick(_args)
      raise NotImplementedError
    end

    def name
      raise NotImplementedError
    end
  end
end
