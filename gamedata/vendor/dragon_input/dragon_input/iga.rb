module DragonInput
  # Generate a Steam In-Game Actions (IGA) file from the *same* Config the Ruby
  # backend uses, so the two mappings are never hand-maintained separately.
  #
  # The output is Valve's VDF (KeyValues) format expected by ISteamInput:
  # digital actions become "Button" entries, analog actions become
  # "StickPadGyro" joystick_move entries, and a localization block supplies the
  # human titles Steam shows in its binding overlay.
  #
  #   vdf = DragonInput::IGA.generate(config)
  #   $gtk.write_file('game_actions_480.vdf', vdf)   # (in DragonRuby)
  module IGA
    # extend self (not the bare `module_function` directive, whose no-arg form
    # doesn't carry to later defs in mruby) so these are callable as IGA.*.
    extend self

    def generate(config)
      tokens = {}
      root = {
        'In Game Actions' => {
          'actions' => action_sets_block(config, tokens),
          'localization' => { 'english' => tokens }
        }
      }
      VDF.dump(root)
    end

    def action_sets_block(config, tokens)
      sets = {}
      config.each_set do |set|
        set_token = "Set_#{camelize(set.name)}"
        tokens[set_token] = humanize(set.name)

        block = { 'title' => "##{set_token}" }

        unless set.analogs.empty?
          block['StickPadGyro'] = stick_block(set.analogs.values, tokens)
        end
        unless set.digitals.empty?
          block['Button'] = button_block(set.digitals.values, tokens)
        end

        sets[set.name.to_s] = block
      end
      sets
    end

    def button_block(actions, tokens)
      out = {}
      actions.each do |action|
        token = action_token(action, tokens)
        out[action.name.to_s] = { 'title' => "##{token}" }
      end
      out
    end

    def stick_block(actions, tokens)
      out = {}
      actions.each do |action|
        token = action_token(action, tokens)
        out[action.name.to_s] = {
          'title' => "##{token}",
          'input_mode' => 'joystick_move'
        }
      end
      out
    end

    def action_token(action, tokens)
      token = "Action_#{camelize(action.name)}"
      tokens[token] = humanize(action.name)
      token
    end

    def humanize(sym)
      sym.to_s.split('_').map { |w| w[0].upcase + w[1..-1].to_s }.join(' ')
    end

    def camelize(sym)
      sym.to_s.split('_').map { |w| w[0].upcase + w[1..-1].to_s }.join
    end

    # Minimal VDF / KeyValues serializer. Emits tab-indented nested blocks with
    # quoted keys and string values — the shape Steam expects for IGA files.
    module VDF
      extend self

      def dump(hash)
        render(hash, 0)
      end

      def render(hash, depth)
        indent = "\t" * depth
        out = ''
        hash.each do |key, value|
          if value.is_a?(Hash)
            out << "#{indent}\"#{escape(key)}\"\n#{indent}{\n"
            out << render(value, depth + 1)
            out << "#{indent}}\n"
          else
            out << "#{indent}\"#{escape(key)}\"\t\t\"#{escape(value)}\"\n"
          end
        end
        out
      end

      def escape(str)
        str.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
      end
    end
  end
end
