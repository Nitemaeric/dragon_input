# Import glyphs from the Kenney "Input Prompts" pack (CC0, https://kenney.nl/assets/input-prompts)
# into dragon_input's naming scheme.
#
# The Ruby backend resolves glyphs at:
#   sprites/dragon_input/glyphs/<style>/<button>.png
# This build-time tool copies just the ~20 glyphs per style we reference out of
# an extracted Kenney pack (which ships ~1500 files) and renames them to match.
# Anything not found is reported and simply falls back to a drawn keycap at
# runtime — so a partial import is fine.
#
# Usage:
#   ruby tools/import_kenney_glyphs.rb <pack> [dest-sprites-dir]
#
#   <pack>              path to the extracted Kenney "Input Prompts" folder
#   [dest-sprites-dir]  a project's `sprites` dir to populate; glyphs land under
#                       <dest>/dragon_input/glyphs/. Defaults to this repo's
#                       bundled sprites. Point it at a consumer's mygame/sprites,
#                       e.g. `ruby tools/import_kenney_glyphs.rb <pack> demo/mygame/sprites`.
#
# Kenney bumps their filenames between versions, so matching is fuzzy: we look
# for an exact basename first, then a substring, preferring the plain "Default"
# 64px variant over decorated ones.

require 'fileutils'

DEFAULT_SPRITES_DIR = File.expand_path('../sprites', __dir__)

def dest_root(sprites_dir)
  File.join(File.expand_path(sprites_dir), 'dragon_input', 'glyphs')
end

# our button -> ordered list of candidate Kenney basenames (without extension)
CONTROLLER_MAP = {
  xbox: {
    a:  %w[xbox_button_a], b: %w[xbox_button_b], x: %w[xbox_button_x], y: %w[xbox_button_y],
    l1: %w[xbox_lb xbox_button_lb], r1: %w[xbox_rb xbox_button_rb],
    l2: %w[xbox_lt xbox_button_lt], r2: %w[xbox_rt xbox_button_rt],
    l3: %w[xbox_stick_l_press xbox_ls xbox_stick_l],
    r3: %w[xbox_stick_r_press xbox_rs xbox_stick_r],
    start: %w[xbox_button_menu], select: %w[xbox_button_view],
    up: %w[xbox_dpad_up], down: %w[xbox_dpad_down],
    left: %w[xbox_dpad_left], right: %w[xbox_dpad_right],
    left_analog: %w[xbox_stick_l xbox_ls], right_analog: %w[xbox_stick_r xbox_rs]
  },
  playstation: {
    # Face buttons by physical position (matches DragonRuby's a/b/x/y layout):
    # a=bottom=cross, b=right=circle, x=left=square, y=top=triangle.
    a: %w[playstation_button_cross playstation_button_color_cross],
    b: %w[playstation_button_circle playstation_button_color_circle],
    x: %w[playstation_button_square playstation_button_color_square],
    y: %w[playstation_button_triangle playstation_button_color_triangle],
    l1: %w[playstation_trigger_l1], r1: %w[playstation_trigger_r1],
    l2: %w[playstation_trigger_l2], r2: %w[playstation_trigger_r2],
    l3: %w[playstation_button_l3 playstation_stick_l_press],
    r3: %w[playstation_button_r3 playstation_stick_r_press],
    # options/create/share are prefixed with the console generation in the pack.
    start: %w[playstation5_button_options playstation4_button_options],
    select: %w[playstation5_button_create playstation4_button_share],
    up: %w[playstation_dpad_up], down: %w[playstation_dpad_down],
    left: %w[playstation_dpad_left], right: %w[playstation_dpad_right],
    left_analog: %w[playstation_stick_l], right_analog: %w[playstation_stick_r]
  },
  switch: {
    # NOTE: DragonRuby reports face buttons by Xbox-style position. Nintendo's
    # physical A/B are swapped vs Xbox, so we map by position: our :a (bottom)
    # -> Switch B, our :b (right) -> Switch A. x/y likewise.
    a: %w[switch_button_b], b: %w[switch_button_a],
    x: %w[switch_button_y], y: %w[switch_button_x],
    l1: %w[switch_button_l], r1: %w[switch_button_r],
    l2: %w[switch_button_zl], r2: %w[switch_button_zr],
    l3: %w[switch_stick_l_press switch_stick_l],
    r3: %w[switch_stick_r_press switch_stick_r],
    start: %w[switch_button_plus], select: %w[switch_button_minus],
    up: %w[switch_dpad_up], down: %w[switch_dpad_down],
    left: %w[switch_dpad_left], right: %w[switch_dpad_right],
    left_analog: %w[switch_stick_l], right_analog: %w[switch_stick_r]
  }
}.freeze

# our keyboard filename -> candidate Kenney basenames. Letters/digits are
# generated below; this covers the named keys our example config uses.
KEYBOARD_NAMED = {
  'space' => %w[keyboard_space],
  'enter' => %w[keyboard_enter keyboard_return],
  'escape' => %w[keyboard_escape],
  'tab' => %w[keyboard_tab],
  'shift' => %w[keyboard_shift],
  'ctrl' => %w[keyboard_ctrl], 'control' => %w[keyboard_ctrl],
  'alt' => %w[keyboard_alt],
  'up' => %w[keyboard_arrow_up], 'down' => %w[keyboard_arrow_down],
  'left' => %w[keyboard_arrow_left], 'right' => %w[keyboard_arrow_right],
  # cluster glyph for an :arrows analog binding (Kenney ships no WASD cluster,
  # so a :wasd binding falls back to a drawn "WASD" keycap).
  'arrows' => %w[keyboard_arrows]
}.freeze

def keyboard_map
  map = KEYBOARD_NAMED.dup
  ('a'..'z').each { |c| map[c] = ["keyboard_#{c}"] }
  (0..9).each { |n| map[n.to_s] = ["keyboard_#{n}"] }
  (1..12).each { |n| map["f#{n}"] = ["keyboard_f#{n}"] }
  map
end

# Whole-device icons, imported to <root>/device/<style>.png. Used for the
# "current device" indicator; the library resolves them via device_glyph.
DEVICE_MAP = {
  xbox:        %w[controller_xboxseries controller_xboxone],
  playstation: %w[controller_playstation5 controller_playstation4],
  switch:      %w[controller_switch controller_switch_pro],
  keyboard:    %w[keyboard]
}.freeze

# Build an index of the extracted pack: basename(without ext) -> [full paths].
def index_pack(root)
  index = Hash.new { |h, k| h[k] = [] }
  Dir.glob(File.join(root, '**', '*.png')).each do |path|
    base = File.basename(path, '.png').downcase
    index[base] << path
  end
  index
end

# Pick the best source path for an ordered list of candidate basenames.
def find_source(index, candidates)
  # 1) exact basename match, preferring a "Default" folder and shorter paths.
  candidates.each do |cand|
    hits = index[cand.downcase]
    return best(hits) unless hits.empty?
  end
  # 2) substring match as a fallback (tolerates minor Kenney renames).
  candidates.each do |cand|
    hits = index.select { |base, _| base.include?(cand.downcase) }.values.flatten
    return best(hits) unless hits.empty?
  end
  nil
end

def best(paths)
  paths.min_by { |p| [p.downcase.include?('default') ? 0 : 1, p.length] }
end

def import(pack_root, sprites_dir = DEFAULT_SPRITES_DIR)
  unless File.directory?(pack_root)
    warn "Not a directory: #{pack_root}"
    exit 1
  end

  index = index_pack(pack_root)
  if index.empty?
    warn "No .png files found under #{pack_root} — is this the extracted Kenney pack?"
    exit 1
  end

  root = dest_root(sprites_dir)
  copied = 0
  missing = []

  CONTROLLER_MAP.each do |style, buttons|
    dest_dir = File.join(root, style.to_s)
    FileUtils.mkdir_p(dest_dir)
    buttons.each do |button, candidates|
      src = find_source(index, candidates)
      if src
        FileUtils.cp(src, File.join(dest_dir, "#{button}.png"))
        copied += 1
      else
        missing << "#{style}/#{button}"
      end
    end
  end

  kb_dir = File.join(root, 'keyboard')
  FileUtils.mkdir_p(kb_dir)
  keyboard_map.each do |name, candidates|
    src = find_source(index, candidates)
    if src
      FileUtils.cp(src, File.join(kb_dir, "#{name}.png"))
      copied += 1
    else
      missing << "keyboard/#{name}"
    end
  end

  device_dir = File.join(root, 'device')
  FileUtils.mkdir_p(device_dir)
  DEVICE_MAP.each do |style, candidates|
    src = find_source(index, candidates)
    if src
      FileUtils.cp(src, File.join(device_dir, "#{style}.png"))
      copied += 1
    else
      missing << "device/#{style}"
    end
  end

  puts "Imported #{copied} glyphs into #{root}"
  unless missing.empty?
    puts "\n#{missing.size} not found (these fall back to a drawn keycap at runtime):"
    missing.each { |m| puts "  - #{m}" }
    puts "\nIf many are missing, your Kenney pack may use different filenames —"
    puts "adjust the candidate lists in tools/import_kenney_glyphs.rb."
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.empty?
    warn 'Usage: ruby tools/import_kenney_glyphs.rb <pack> [dest-sprites-dir]'
    exit 1
  end
  import(File.expand_path(ARGV[0]), ARGV[1] || DEFAULT_SPRITES_DIR)
end
