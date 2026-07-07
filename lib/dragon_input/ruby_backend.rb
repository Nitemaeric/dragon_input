module DragonInput
  # Pure-Ruby backend over `args.inputs.*`. Works on any DragonRuby tier, in or
  # out of Steam, with zero build step. Owns its own rebinding + persisted
  # overrides (there is no Steam overlay here).
  class RubyBackend
    CAPABILITIES = [
      :actions, :action_sets, :analog, :in_game_rebind
    ].freeze

    BINDINGS_FILE = 'dragon_input_bindings.json'.freeze

    # Which raw source object each source key maps to, and its type.
    SOURCE_TYPES = {
      controller_one:   :controller,
      controller_two:   :controller,
      controller_three: :controller,
      controller_four:  :controller,
      keyboard:         :keyboard,
      mouse:            :mouse
    }.freeze

    # Named keyboard analog clusters -> { up:, down:, left:, right: } keys.
    ANALOG_CLUSTERS = {
      wasd:   { up: :w,  down: :s,    left: :a,    right: :d },
      arrows: { up: :up, down: :down, left: :left, right: :right }
    }.freeze

    def self.available?(_config)
      true # the fallback is always available
    end

    def initialize(config, storage: nil)
      @config = config
      @storage = storage || Storage.default
      @active_set = {}
      @active_device = {}
      @config.pads.each_key do |pad|
        @active_set[pad] = @config.default_set
        @active_device[pad] = default_device(pad)
      end
      # overrides[set][action_name][source_type] = raw binding
      @overrides = load_overrides
      @glyphs = Glyphs.new(@config)
      @rebind = Rebind.new(self, @config)
      @args = nil
    end

    def name
      :ruby
    end

    # Capabilities as an Array used set-style (mruby has no bundled Set gem).
    def capabilities
      CAPABILITIES
    end

    def tick(args)
      @args = args
      @config.pads.each_key { |pad| update_active_device(pad) }
      @rebind.tick(args)
    end

    # ---- Digital --------------------------------------------------------

    def digital(pad, action_name)
      action = resolve(pad, action_name)
      return Backend::INACTIVE_DIGITAL unless action && action.digital?

      down = false
      held = false
      up = false
      @config.sources_for(pad).each do |src_key|
        src_type = SOURCE_TYPES[src_key]
        binding = binding_for(pad, action, src_type)
        next unless binding

        state = read_digital(src_key, src_type, binding)
        down ||= state[:down]
        held ||= state[:held]
        up   ||= state[:up]
      end
      { down: down, held: held, up: up, active: true }
    end

    # ---- Analog ---------------------------------------------------------

    def analog(pad, action_name)
      action = resolve(pad, action_name)
      return Backend::INACTIVE_ANALOG unless action && action.analog?

      best_x = 0.0
      best_y = 0.0
      best_mag = 0.0
      @config.sources_for(pad).each do |src_key|
        src_type = SOURCE_TYPES[src_key]
        binding = binding_for(pad, action, src_type)
        next unless binding

        x, y = read_analog(src_key, src_type, binding)
        mag = (x * x) + (y * y)
        # Prefer the source currently pushed hardest (stick over idle keys).
        if mag > best_mag
          best_mag = mag
          best_x = x
          best_y = y
        end
      end
      { x: clamp_unit(best_x), y: clamp_unit(best_y), active: true }
    end

    # ---- Glyphs / haptics / sets ---------------------------------------

    def glyph(pad, action_name)
      action = resolve(pad, action_name)
      return nil unless action

      @glyphs.path(pad, action, active_style(pad), self)
    end

    # Style to draw prompts in for a pad, following the *last device the player
    # used*: :keyboard when they last used keyboard/mouse, else the detected
    # controller style (:xbox/:playstation/:switch). This is what makes prompts
    # swap the instant a player switches input device.
    def glyph_style(pad)
      active_style(pad)
    end

    # Which device the pad last received input from (:keyboard or :controller).
    def active_device(pad)
      @active_device[pad] || default_device(pad)
    end

    # Draw the glyph (sprite if present, else a keycap fallback) into rect.
    def render_glyph(args, pad, action_name, rect)
      action = resolve(pad, action_name)
      return unless action

      @glyphs.render(args, pad, action, active_style(pad), rect)
    end

    # Whole-device icon for the pad's current device.
    def device_glyph(pad)
      @glyphs.device_path(active_style(pad))
    end

    def render_device_glyph(args, pad, rect)
      @glyphs.render_device(args, active_style(pad), rect)
    end

    # No controller rumble in stock DragonRuby — honest no-op. `:rumble` is
    # deliberately absent from CAPABILITIES so games gate on supports?(:rumble).
    def rumble(_pad, _low_freq, _high_freq)
      false
    end

    def activate_set(pad, set_name)
      return false unless @config.set(set_name)

      @active_set[pad] = set_name
      true
    end

    def active_set(pad)
      @active_set[pad]
    end

    def open_rebind(pad)
      @rebind.open(pad)
    end

    def rebinding?
      @rebind.active?
    end

    # ---- Rebind support (used by Rebind) -------------------------------

    # Record a new binding for (active set of pad, action, source type) and
    # persist. Passing nil clears the override back to the config default.
    def set_override(pad, action_name, source_type, binding)
      set_name = @active_set[pad]
      @overrides[set_name] ||= {}
      @overrides[set_name][action_name] ||= {}
      if binding.nil?
        @overrides[set_name][action_name].delete(source_type)
      else
        @overrides[set_name][action_name][source_type] = binding
      end
      save_overrides
    end

    def reset_overrides
      @overrides = {}
      save_overrides
    end

    # Read the first raw source object matching a type, for capture during
    # rebinding (e.g. "press any controller button").
    def source_object(src_key)
      return nil unless @args

      case src_key
      when :controller_one   then @args.inputs.controller_one
      when :controller_two   then @args.inputs.controller_two
      when :controller_three then @args.inputs.controller_three
      when :controller_four  then @args.inputs.controller_four
      when :keyboard         then @args.inputs.keyboard
      when :mouse            then @args.inputs.mouse
      end
    end

    private

    def resolve(pad, action_name)
      set_name = @active_set[pad]
      set = @config.set(set_name)
      set && set.action(action_name)
    end

    def binding_for(pad, action, source_type)
      set_name = @active_set[pad]
      ov = @overrides[set_name]
      if ov && ov[action.name] && ov[action.name].key?(source_type)
        return ov[action.name][source_type]
      end

      action.binding_for(source_type)
    end

    # ---- Raw reads ------------------------------------------------------

    def read_digital(src_key, src_type, binding)
      obj = source_object(src_key)
      return { down: false, held: false, up: false } unless obj

      case src_type
      when :controller, :keyboard
        {
          down: !!obj.key_down.send(binding),
          held: !!obj.key_held.send(binding),
          up:   !!obj.key_up.send(binding)
        }
      when :mouse
        read_mouse_digital(obj, binding)
      else
        { down: false, held: false, up: false }
      end
    end

    def read_mouse_digital(mouse, binding)
      case binding
      when :left
        { down: !!mouse.click, held: !!mouse.button_left, up: !!mouse.up }
      when :right
        { down: false, held: !!mouse.button_right, up: false }
      else
        { down: false, held: false, up: false }
      end
    end

    def read_analog(src_key, src_type, binding)
      obj = source_object(src_key)
      return [0.0, 0.0] unless obj

      case src_type
      when :controller
        read_controller_analog(obj, binding)
      when :keyboard
        read_keyboard_analog(obj, binding)
      else
        [0.0, 0.0]
      end
    end

    def read_controller_analog(controller, binding)
      case binding
      when :left_analog
        apply_deadzone(controller.left_analog_x_perc, controller.left_analog_y_perc)
      when :right_analog
        apply_deadzone(controller.right_analog_x_perc, controller.right_analog_y_perc)
      else
        [0.0, 0.0]
      end
    end

    # A keyboard analog binding is a named cluster (:wasd/:arrows), a custom
    # { up:, down:, left:, right: } hash, or an Array of any of those (so one
    # action can respond to, e.g., both WASD and the arrow keys).
    def read_keyboard_analog(keyboard, binding)
      bindings = binding.is_a?(Array) ? binding : [binding]
      held = keyboard.key_held
      x = 0.0
      y = 0.0
      bindings.each do |b|
        cluster = ANALOG_CLUSTERS[b] || (b.is_a?(Hash) ? b : nil)
        next unless cluster

        x += (held.send(cluster[:right]) ? 1.0 : 0.0) - (held.send(cluster[:left]) ? 1.0 : 0.0)
        y += (held.send(cluster[:up]) ? 1.0 : 0.0) - (held.send(cluster[:down]) ? 1.0 : 0.0)
      end
      [clamp_unit(x), clamp_unit(y)]
    end

    def apply_deadzone(x, y)
      x = x.to_f
      y = y.to_f
      mag = Math.sqrt((x * x) + (y * y))
      dz = @config.deadzone
      return [0.0, 0.0] if mag < dz
      return [x, y] if dz <= 0.0 || mag.zero?

      # Rescale so the deadzone edge maps to 0 and full deflection stays 1.
      scaled = (mag - dz) / (1.0 - dz)
      scaled = 1.0 if scaled > 1.0
      [x / mag * scaled, y / mag * scaled]
    end

    def clamp_unit(v)
      return -1.0 if v < -1.0
      return 1.0 if v > 1.0

      v
    end

    # Best-effort controller identity for glyph selection. DragonRuby exposes
    # little here, so this is intentionally coarse.
    def controller_style(pad)
      src = @config.sources_for(pad).find { |s| SOURCE_TYPES[s] == :controller }
      return :keyboard unless src

      obj = source_object(src)
      Glyphs.style_from_controller(obj)
    end

    # ---- Device awareness ----------------------------------------------

    # Resolve the glyph style from the last-used device.
    def active_style(pad)
      active_device(pad) == :controller ? controller_style(pad) : :keyboard
    end

    # Before any input, prefer keyboard if the pad has one, else controller.
    def default_device(pad)
      @config.sources_for(pad).any? { |s| SOURCE_TYPES[s] == :keyboard } ? :keyboard : :controller
    end

    # Flip the pad's active device when a bound input fires on it this frame.
    # Controller wins ties (a held stick shouldn't read as keyboard). Idle
    # frames leave the previous device sticky.
    def update_active_device(pad)
      set = @config.set(@active_set[pad])
      return unless set

      if bound_source_active?(pad, set, :controller)
        @active_device[pad] = :controller
      elsif bound_source_active?(pad, set, :keyboard) || bound_source_active?(pad, set, :mouse)
        @active_device[pad] = :keyboard
      end
    end

    def bound_source_active?(pad, set, target_type)
      @config.sources_for(pad).each do |src_key|
        next unless SOURCE_TYPES[src_key] == target_type

        return true if source_has_activity?(pad, src_key, target_type, set)
      end
      false
    end

    # Any bound digital held/pressed, or any bound analog past the deadzone.
    def source_has_activity?(pad, src_key, src_type, set)
      set.digitals.each_value do |action|
        binding = binding_for(pad, action, src_type)
        next unless binding

        state = read_digital(src_key, src_type, binding)
        return true if state[:down] || state[:held]
      end
      set.analogs.each_value do |action|
        binding = binding_for(pad, action, src_type)
        next unless binding

        x, y = read_analog(src_key, src_type, binding)
        return true if ((x * x) + (y * y)) > 0.0001
      end
      false
    end

    # ---- Persistence ----------------------------------------------------

    def load_overrides
      raw = @storage.read(BINDINGS_FILE)
      return {} unless raw && !raw.empty?

      parsed = parse_json(raw)
      return {} unless parsed.is_a?(Hash)

      symbolize_overrides(parsed)
    rescue StandardError
      {}
    end

    def save_overrides
      @storage.write(BINDINGS_FILE, encode_json(stringify_overrides(@overrides)))
    end

    # Read JSON through $gtk in DragonRuby, else the stdlib (tests run on MRI).
    def parse_json(str)
      if $gtk
        $gtk.parse_json(str)
      else
        require 'json'
        JSON.parse(str)
      end
    end

    # Minimal JSON writer. mruby has no bundled `json` gem and no core #to_json,
    # so we encode by hand. The overrides tree is only nested Hashes of strings.
    def encode_json(obj)
      case obj
      when Hash
        '{' + obj.map { |k, v| "#{encode_json(k.to_s)}:#{encode_json(v)}" }.join(',') + '}'
      when Array
        '[' + obj.map { |v| encode_json(v) }.join(',') + ']'
      when nil
        'null'
      when true, false
        obj.to_s
      when Numeric
        obj.to_s
      else
        '"' + obj.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"') + '"'
      end
    end

    def symbolize_overrides(hash)
      out = {}
      hash.each do |set, actions|
        out[set.to_sym] = {}
        actions.each do |action, sources|
          out[set.to_sym][action.to_sym] = {}
          sources.each do |src_type, binding|
            out[set.to_sym][action.to_sym][src_type.to_sym] = symbolize_binding(binding)
          end
        end
      end
      out
    end

    def symbolize_binding(binding)
      binding.is_a?(String) ? binding.to_sym : binding
    end

    def stringify_overrides(hash)
      out = {}
      hash.each do |set, actions|
        out[set.to_s] = {}
        actions.each do |action, sources|
          out[set.to_s][action.to_s] = {}
          sources.each do |src_type, binding|
            out[set.to_s][action.to_s][src_type.to_s] = binding.to_s
          end
        end
      end
      out
    end
  end
end
