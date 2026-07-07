module DragonInput
  # One source of truth for the action model. Authored as a small Ruby DSL; the
  # Ruby backend reads it directly and the Steam IGA (VDF) file is generated from
  # the same data (see DragonInput::IGA) so mappings are never maintained twice.
  #
  #   DragonInput.setup do |c|
  #     c.default_set :gameplay
  #     c.deadzone 0.2
  #
  #     c.action_set :gameplay do |s|
  #       s.digital :fire,  controller: :r2,           keyboard: :space, mouse: :left
  #       s.digital :jump,  controller: :a,            keyboard: :j
  #       s.digital :pause, controller: :start,        keyboard: :escape
  #       s.analog  :move,  controller: :left_analog,  keyboard: :wasd
  #       s.analog  :aim,   controller: :right_analog, keyboard: :arrows
  #     end
  #
  #     c.action_set :menu do |s|
  #       s.digital :confirm, controller: :a, keyboard: :enter
  #       s.digital :cancel,  controller: :b, keyboard: :escape
  #     end
  #   end
  class Config
    attr_reader :action_sets, :pads

    def initialize
      @action_sets = {}
      @default_set = nil
      @deadzone = 0.2
      @pads = default_pads
      @glyph_root = nil
    end

    # ---- DSL ------------------------------------------------------------

    def action_set(name)
      set = (@action_sets[name] ||= ActionSet.new(name))
      yield set if block_given?
      @default_set ||= name
      set
    end

    def default_set(name = :__read__)
      return @default_set if name == :__read__

      @default_set = name
    end

    def deadzone(value = :__read__)
      return @deadzone if value == :__read__

      @deadzone = value.to_f
    end

    # Override where the Ruby backend looks for bundled glyph art. By default it
    # auto-detects the drenv-vendored path or a plain `sprites/dragon_input/glyphs`.
    def glyph_root(path = :__read__)
      return @glyph_root if path == :__read__

      @glyph_root = path
    end

    # Redefine which raw input sources feed a logical pad. `sources` is an array
    # of source keys: :controller_one..:controller_four, :keyboard, :mouse.
    def pad(name, sources)
      @pads[name] = Array(sources)
    end

    # ---- Lookup ---------------------------------------------------------

    def set(name)
      @action_sets[name]
    end

    def sources_for(pad)
      @pads[pad] || []
    end

    def each_set(&blk)
      @action_sets.each_value(&blk)
    end

    private

    def default_pads
      {
        one:      [:controller_one, :keyboard, :mouse],
        two:      [:controller_two],
        three:    [:controller_three],
        four:     [:controller_four],
        keyboard: [:keyboard, :mouse]
      }
    end
  end

  # A named collection of actions. Actions with the same name may exist in more
  # than one set; the pad's *active* set decides which one a query resolves to.
  class ActionSet
    attr_reader :name, :digitals, :analogs

    def initialize(name)
      @name = name
      @digitals = {}
      @analogs = {}
    end

    def digital(name, controller: nil, keyboard: nil, mouse: nil, glyph: nil)
      @digitals[name] = Action.new(
        name, :digital,
        { controller: controller, keyboard: keyboard, mouse: mouse },
        glyph
      )
    end

    def analog(name, controller: nil, keyboard: nil, mouse: nil, glyph: nil)
      @analogs[name] = Action.new(
        name, :analog,
        { controller: controller, keyboard: keyboard, mouse: mouse },
        glyph
      )
    end

    def action(name)
      @digitals[name] || @analogs[name]
    end
  end

  # A single bindable action. `kind` is :digital or :analog. `bindings` maps a
  # source *type* (:controller/:keyboard/:mouse) to its raw binding.
  class Action
    attr_reader :name, :kind, :bindings, :glyph_hint

    def initialize(name, kind, bindings, glyph_hint = nil)
      @name = name
      @kind = kind
      @bindings = bindings
      @glyph_hint = glyph_hint
    end

    def binding_for(source_type)
      @bindings[source_type]
    end

    def digital?
      @kind == :digital
    end

    def analog?
      @kind == :analog
    end
  end
end
