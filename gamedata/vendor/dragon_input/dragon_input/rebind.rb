module DragonInput
  # Minimal in-game rebinding overlay owned by the Ruby backend (there is no
  # Steam overlay to defer to). Open it with DragonInput.open_rebind(pad); it
  # renders during DragonInput.tick and captures the next input for the selected
  # action, then persists the override through the backend.
  #
  # Controls while open:
  #   up / down (keyboard or D-pad)  -> move selection
  #   enter / A                      -> start capture for the selected action
  #   (any controller button)        -> becomes the new binding while capturing
  #   escape / B                     -> cancel capture, or close the overlay
  class Rebind
    # Controller buttons we can capture, in priority order.
    CAPTURABLE = [
      :a, :b, :x, :y, :l1, :r1, :l2, :r2, :l3, :r3,
      :start, :select, :up, :down, :left, :right
    ].freeze

    def initialize(backend, config)
      @backend = backend
      @config = config
      @pad = nil
      @index = 0
      @capturing = false
      @nav_cooldown = 0
    end

    def open(pad)
      @pad = pad
      @index = 0
      @capturing = false
      @nav_cooldown = 8
      true
    end

    def close
      @pad = nil
      @capturing = false
    end

    def active?
      !@pad.nil?
    end

    def tick(args)
      return unless active?

      actions = current_actions
      if actions.empty?
        close
        return
      end

      if @capturing
        handle_capture(args, actions[@index])
      else
        handle_navigation(args, actions)
      end

      render(args, actions)
    end

    private

    def current_actions
      set_name = @backend.active_set(@pad)
      set = @config.set(set_name)
      return [] unless set

      set.digitals.values
    end

    def handle_navigation(args, actions)
      @nav_cooldown -= 1 if @nav_cooldown > 0
      kb = args.inputs.keyboard
      pad = first_controller(args)

      if @nav_cooldown <= 0
        if down_pressed?(kb, pad)
          @index = (@index + 1) % actions.size
          @nav_cooldown = 8
        elsif up_pressed?(kb, pad)
          @index = (@index - 1) % actions.size
          @nav_cooldown = 8
        end
      end

      if confirm_pressed?(kb, pad)
        @capturing = true
        @nav_cooldown = 8
      elsif cancel_pressed?(kb, pad)
        close
      end
    end

    def handle_capture(args, action)
      # Give the player a beat so the button that opened capture isn't grabbed.
      @nav_cooldown -= 1 if @nav_cooldown > 0
      return if @nav_cooldown > 0

      kb = args.inputs.keyboard
      if kb.key_down.escape
        @capturing = false
        return
      end

      button = captured_controller_button(args)
      return unless button

      @backend.set_override(@pad, action.name, :controller, button)
      @capturing = false
    end

    def captured_controller_button(args)
      @config.sources_for(@pad).each do |src_key|
        next unless src_key.to_s.start_with?('controller_')

        obj = @backend.source_object(src_key)
        next unless obj

        CAPTURABLE.each do |btn|
          return btn if obj.key_down.send(btn)
        end
      end
      nil
    end

    # ---- Input helpers --------------------------------------------------

    def first_controller(args)
      @config.sources_for(@pad).each do |src_key|
        next unless src_key.to_s.start_with?('controller_')

        obj = @backend.source_object(src_key)
        return obj if obj
      end
      nil
    end

    def down_pressed?(kb, pad)
      kb.key_down.down || kb.key_down.s || (pad && pad.key_down.down)
    end

    def up_pressed?(kb, pad)
      kb.key_down.up || kb.key_down.w || (pad && pad.key_down.up)
    end

    def confirm_pressed?(kb, pad)
      kb.key_down.enter || (pad && pad.key_down.a)
    end

    def cancel_pressed?(kb, pad)
      kb.key_down.escape || (pad && pad.key_down.b)
    end

    # ---- Render ---------------------------------------------------------

    def render(args, actions)
      args.outputs.sprites << { x: 0, y: 0, w: 1280, h: 720, path: :solid, r: 0, g: 0, b: 0, a: 200 }

      panel = { x: 340, y: 120, w: 600, h: 480 }
      args.outputs.sprites << panel.merge(path: :solid, r: 24, g: 24, b: 30)
      args.outputs.borders << panel.merge(r: 120, g: 120, b: 140)

      args.outputs.labels << {
        x: 640, y: 560, text: "Rebind — #{@backend.active_set(@pad)}",
        size_px: 28, alignment_enum: 1, r: 240, g: 240, b: 245
      }

      row_h = 40
      actions.each_with_index do |action, i|
        y = 500 - (i * row_h)
        selected = (i == @index)
        if selected
          args.outputs.sprites << { x: 360, y: y - 6, w: 560, h: row_h - 4,
                                    path: :solid, r: 60, g: 70, b: 110 }
        end
        binding = current_binding(action)
        args.outputs.labels << {
          x: 380, y: y + 18, text: humanize(action.name),
          size_px: 22, alignment_enum: 0,
          r: 235, g: 235, b: 240
        }
        args.outputs.labels << {
          x: 900, y: y + 18,
          text: @capturing && selected ? '[press a button]' : binding.to_s,
          size_px: 22, alignment_enum: 2,
          r: (@capturing && selected) ? 255 : 200,
          g: (@capturing && selected) ? 210 : 200,
          b: 120
        }
      end

      args.outputs.labels << {
        x: 640, y: 150,
        text: 'Up/Down: select   Enter/A: rebind   Esc/B: back',
        size_px: 16, alignment_enum: 1, r: 170, g: 170, b: 180
      }
    end

    def current_binding(action)
      # Reflect any override the backend already stored.
      @backend.send(:binding_for, @pad, action, :controller)
    end

    def humanize(sym)
      sym.to_s.split('_').map { |w| w[0].upcase + w[1..-1].to_s }.join(' ')
    end
  end
end
