# Fake DragonRuby input objects so the library can be exercised under
# DragonRuby's mruby-patched (see script/test.sh) without the engine. Only the
# surface the Ruby backend reads is modeled.

# A group like key_down / key_held / key_up: responds truthily to any button
# name it was told is active.
class FakeKeys
  def initialize(active = [])
    @active = active.map(&:to_sym)
  end

  def respond_to_missing?(_name, _include_private = false)
    true
  end

  def method_missing(name, *)
    @active.include?(name)
  end
end

class FakeController
  attr_accessor :left_analog_x_perc, :left_analog_y_perc,
                :right_analog_x_perc, :right_analog_y_perc,
                :connected, :name

  def initialize(down: [], held: [], up: [])
    @down = FakeKeys.new(down)
    @held = FakeKeys.new(held)
    @up = FakeKeys.new(up)
    @left_analog_x_perc = 0.0
    @left_analog_y_perc = 0.0
    @right_analog_x_perc = 0.0
    @right_analog_y_perc = 0.0
    @connected = true
    @name = nil
  end

  def key_down; @down; end
  def key_held; @held; end
  def key_up; @up; end
end

class FakeKeyboard
  def initialize(down: [], held: [], up: [])
    @down = FakeKeys.new(down)
    @held = FakeKeys.new(held)
    @up = FakeKeys.new(up)
  end

  def key_down; @down; end
  def key_held; @held; end
  def key_up; @up; end
end

class FakeMouse
  attr_accessor :click, :button_left, :button_right, :up

  def initialize(click: false, button_left: false, button_right: false, up: false)
    @click = click
    @button_left = button_left
    @button_right = button_right
    @up = up
  end
end

class FakeInputs
  attr_accessor :controller_one, :controller_two, :controller_three,
                :controller_four, :keyboard, :mouse

  def initialize
    @controller_one = FakeController.new
    @controller_two = FakeController.new
    @controller_three = FakeController.new
    @controller_four = FakeController.new
    @keyboard = FakeKeyboard.new
    @mouse = FakeMouse.new
  end
end

class FakeArgs
  attr_accessor :inputs

  def initialize
    @inputs = FakeInputs.new
  end
end

# ---- Tiny assertion harness ------------------------------------------------

module T
  @failures = []
  @count = 0

  class << self
    attr_reader :failures, :count

    def assert(cond, msg)
      @count += 1
      @failures << msg unless cond
      puts(cond ? "  ok  #{msg}" : "  FAIL #{msg}")
    end

    def eq(actual, expected, msg)
      assert(actual == expected, "#{msg} (expected #{expected.inspect}, got #{actual.inspect})")
    end

    def report
      puts "\n#{@count - @failures.size}/#{@count} passed"
      unless @failures.empty?
        puts 'FAILURES:'
        @failures.each { |f| puts "  - #{f}" }
      end
      @failures.empty?
    end
  end
end
