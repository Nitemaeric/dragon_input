# Smoke tests, run under DragonRuby's mruby-patched interpreter via
# `script/test.sh`. The standalone `mruby` CLI has no `require`/`require_relative`
# (DragonRuby provides those in-engine), so the library sub-files and test/support
# are preloaded with `mruby -r ...` in dependency order; this script only holds
# the assertions. See script/test.sh.

def build_config
  c = DragonInput::Config.new
  c.default_set :gameplay
  c.deadzone 0.2
  c.action_set :gameplay do |s|
    s.digital :fire,  controller: :r2,          keyboard: :space, mouse: :left
    s.digital :jump,  controller: :a,           keyboard: :j
    s.analog  :move,  controller: :left_analog, keyboard: :wasd
  end
  c.action_set :menu do |s|
    s.digital :confirm, controller: :a, keyboard: :enter
    s.digital :cancel,  controller: :b, keyboard: :escape
  end
  c
end

puts 'Config + Action model'
cfg = build_config
T.eq(cfg.default_set, :gameplay, 'default set recorded')
T.eq(cfg.set(:gameplay).action(:fire).kind, :digital, 'fire is digital')
T.eq(cfg.set(:gameplay).action(:move).kind, :analog, 'move is analog')
T.eq(cfg.set(:gameplay).action(:fire).binding_for(:keyboard), :space, 'fire keyboard binding')

puts "\nGlyph root resolution + vendored fallback"
gcfg = DragonInput::Config.new
T.eq(DragonInput::Glyphs.new(gcfg).roots,
     ['sprites/dragon_input/glyphs', 'vendor/dragon_input/sprites/dragon_input/glyphs'],
     'default: local, then vendored bundled as fallback')
T.eq(DragonInput::Glyphs.new(gcfg).root, 'sprites/dragon_input/glyphs',
     'primary root is local off-engine')
gcfg.glyph_root 'my/custom/glyphs'
T.eq(DragonInput::Glyphs.new(gcfg).roots,
     ['my/custom/glyphs', 'sprites/dragon_input/glyphs',
      'vendor/dragon_input/sprites/dragon_input/glyphs'],
     'override is highest priority; vendored remains a fallback')

puts "\nGlyph aliasing + device icons"
gl = DragonInput::Glyphs.new(build_config)
move_action = build_config.set(:gameplay).action(:move)
T.eq(gl.path(:one, move_action, :keyboard),
     'sprites/dragon_input/glyphs/keyboard/arrows.png',
     ':wasd keyboard glyph aliases to the arrows cluster')
T.eq(gl.label(move_action, :keyboard), 'WASD', 'label keeps the raw WASD text')
T.eq(gl.device_path(:keyboard),
     'sprites/dragon_input/glyphs/device/keyboard.png', 'device icon path')

puts "\nKey-level glyphs (raw button -> sprite path)"
T.eq(gl.key_glyph(:xbox, :a), 'sprites/dragon_input/glyphs/xbox/a.png',
     'raw controller button resolves under its style')
T.eq(gl.key_glyph(:keyboard, :wasd), 'sprites/dragon_input/glyphs/keyboard/arrows.png',
     'keyboard cluster alias applies (:wasd -> arrows)')
T.eq(gl.key_glyph(:keyboard, nil), nil, 'nil button -> nil')
# Backend + facade: a pad resolves through its current device style.
kgb = DragonInput::RubyBackend.new(build_config, storage: DragonInput::Storage::Memory.new)
T.eq(kgb.key_glyph(:one, :space), 'sprites/dragon_input/glyphs/keyboard/space.png',
     'pad resolves via its device style (keyboard by default)')
kargs = FakeArgs.new
kargs.inputs.controller_one = FakeController.new(down: [:a], held: [:a])
kgb.tick(kargs)
T.eq(kgb.key_glyph(:one, :a), 'sprites/dragon_input/glyphs/xbox/a.png',
     'after controller input the pad resolves in the controller style')
T.eq(kgb.key_glyph(:xbox, :b), 'sprites/dragon_input/glyphs/xbox/b.png',
     'an explicit style bypasses device detection')

puts "\nRuby backend — digital reads"
backend = DragonInput::RubyBackend.new(build_config, storage: DragonInput::Storage::Memory.new)
args = FakeArgs.new
# Press keyboard space (down this tick) -> fire on pad :one
args.inputs.keyboard = FakeKeyboard.new(down: [:space], held: [:space])
backend.tick(args)
d = backend.digital(:one, :fire)
T.assert(d[:down], 'fire down via keyboard space')
T.assert(d[:held], 'fire held via keyboard space')
T.assert(d[:active], 'fire active in gameplay set')

# Controller r2 held (not down) -> fire held true, down false
args.inputs.keyboard = FakeKeyboard.new
args.inputs.controller_one = FakeController.new(held: [:r2])
backend.tick(args)
d = backend.digital(:one, :fire)
T.assert(d[:held], 'fire held via controller r2')
T.assert(!d[:down], 'fire not down when only held')

# Action absent from active set -> inactive
d = backend.digital(:one, :confirm)
T.assert(!d[:active], 'confirm inactive while gameplay set active')

puts "\nRuby backend — analog + deadzone"
args.inputs.controller_one = FakeController.new.tap do |c|
  c.left_analog_x_perc = 1.0
  c.left_analog_y_perc = 0.0
end
backend.tick(args)
a = backend.analog(:one, :move)
T.assert(a[:x] > 0.99, 'full right stick -> x ~ 1')
T.eq(a[:y].round(3), 0.0, 'no vertical -> y 0')

# Below deadzone -> zeroed
args.inputs.controller_one = FakeController.new.tap do |c|
  c.left_analog_x_perc = 0.1
  c.left_analog_y_perc = 0.0
end
backend.tick(args)
a = backend.analog(:one, :move)
T.eq(a[:x], 0.0, 'stick inside deadzone zeroed')

# Keyboard wasd synth
args.inputs.controller_one = FakeController.new
args.inputs.keyboard = FakeKeyboard.new(held: [:d, :w])
backend.tick(args)
a = backend.analog(:one, :move)
T.assert(a[:x] > 0.99 && a[:y] > 0.99, 'wasd up-right -> (1,1)')

puts "\nMulti-cluster keyboard analog (wasd + arrows)"
mccfg = DragonInput::Config.new
mccfg.action_set :play do |s|
  s.analog :move, controller: :left_analog, keyboard: [:wasd, :arrows]
end
mcb = DragonInput::RubyBackend.new(mccfg, storage: DragonInput::Storage::Memory.new)
ma = FakeArgs.new
ma.inputs.keyboard = FakeKeyboard.new(held: [:up])
mcb.tick(ma)
T.assert(mcb.analog(:one, :move)[:y] > 0.99, 'arrow Up moves (arrows cluster)')
ma.inputs.keyboard = FakeKeyboard.new(held: [:d])
mcb.tick(ma)
T.assert(mcb.analog(:one, :move)[:x] > 0.99, 'D moves (wasd cluster)')
T.eq(DragonInput::Glyphs.new(mccfg).path(:one, mccfg.set(:play).action(:move), :keyboard),
     'sprites/dragon_input/glyphs/keyboard/arrows.png',
     'array binding: glyph comes from the first cluster (wasd -> arrows)')

puts "\nAction set switching"
backend.activate_set(:one, :menu)
args.inputs.keyboard = FakeKeyboard.new(down: [:enter])
backend.tick(args)
T.assert(backend.digital(:one, :confirm)[:down], 'confirm works after switching to menu set')
T.assert(!backend.digital(:one, :fire)[:active], 'fire inactive in menu set')
backend.activate_set(:one, :gameplay)

puts "\nCapabilities (the seam)"
caps = backend.capabilities
T.assert(caps.include?(:actions), 'ruby backend has :actions')
T.assert(caps.include?(:in_game_rebind), 'ruby backend has :in_game_rebind')
T.assert(!caps.include?(:gyro), 'ruby backend lacks :gyro')
T.assert(!caps.include?(:exact_glyphs), 'ruby backend lacks :exact_glyphs')

puts "\nDevice-aware glyph style (prompts follow last-used device)"
dev = DragonInput::RubyBackend.new(build_config, storage: DragonInput::Storage::Memory.new)
dargs = FakeArgs.new
T.eq(dev.glyph_style(:one), :keyboard, 'defaults to keyboard style')
dargs.inputs.controller_one = FakeController.new(down: [:r2], held: [:r2])
dev.tick(dargs)
T.eq(dev.glyph_style(:one), :xbox, 'switches to controller style on controller input')
dargs.inputs.controller_one = FakeController.new
dargs.inputs.keyboard = FakeKeyboard.new(down: [:space], held: [:space])
dev.tick(dargs)
T.eq(dev.glyph_style(:one), :keyboard, 'switches back to keyboard on keyboard input')
dargs.inputs.keyboard = FakeKeyboard.new # idle
dev.tick(dargs)
T.eq(dev.glyph_style(:one), :keyboard, 'idle frame keeps last device (sticky)')
# analog stick also counts as controller activity
dargs.inputs.controller_one = FakeController.new.tap { |c| c.left_analog_x_perc = 0.9 }
dev.tick(dargs)
T.eq(dev.glyph_style(:one), :xbox, 'moving the stick switches to controller')

puts "\nRebind override persistence"
store = DragonInput::Storage::Memory.new
b1 = DragonInput::RubyBackend.new(build_config, storage: store)
b1.set_override(:one, :fire, :controller, :x) # rebind fire to X button
# New backend instance loads the persisted override
b2 = DragonInput::RubyBackend.new(build_config, storage: store)
args2 = FakeArgs.new
args2.inputs.controller_one = FakeController.new(down: [:x], held: [:x])
b2.tick(args2)
T.assert(b2.digital(:one, :fire)[:down], 'persisted rebind: fire now fires on X')
# Original default r2 no longer bound
args2.inputs.controller_one = FakeController.new(held: [:r2])
b2.tick(args2)
T.assert(!b2.digital(:one, :fire)[:held], 'after rebind, r2 no longer fires')

puts "\nSteam backend dormant without shim"
T.assert(!DragonInput::SteamBackend.available?(build_config), 'steam unavailable without native shim')

puts "\nIGA (VDF) generation"
vdf = DragonInput::IGA.generate(build_config)
T.assert(vdf.include?('"In Game Actions"'), 'IGA has root block')
T.assert(vdf.include?('"gameplay"'), 'IGA has gameplay action set')
T.assert(vdf.include?('"Button"'), 'IGA has Button block for digitals')
T.assert(vdf.include?('"StickPadGyro"'), 'IGA has StickPadGyro for analogs')
T.assert(vdf.include?('joystick_move'), 'analog uses joystick_move input mode')
T.assert(vdf.include?('"#Action_Fire"'), 'fire action title token present')
T.assert(vdf.include?('"Fire"'), 'localization has humanized Fire')

# Signal failure by raising (mruby has no Kernel#exit and exits non-zero on an
# uncaught exception); normal completion is a passing exit 0.
raise 'dragon_input test suite failed' unless T.report
