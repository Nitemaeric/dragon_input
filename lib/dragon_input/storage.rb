module DragonInput
  # Tiny persistence seam so the Ruby backend can save/load rebinds without
  # hard-coupling to `$gtk`. In DragonRuby this reads/writes through the engine's
  # sandboxed file API; in tests (or plain MRI) an in-memory stub can be injected.
  module Storage
    # DragonRuby-backed storage. Uses $gtk.read_file / write_file which resolve
    # to the platform's per-game save directory.
    class Gtk
      def read(path)
        return nil unless $gtk

        $gtk.read_file(path)
      end

      def write(path, contents)
        return false unless $gtk

        $gtk.write_file(path, contents)
        true
      end
    end

    # In-memory storage for tests / headless use.
    class Memory
      def initialize
        @files = {}
      end

      def read(path)
        @files[path]
      end

      def write(path, contents)
        @files[path] = contents
        true
      end
    end

    # Pick a sensible default: real GTK storage when running inside DragonRuby,
    # otherwise an in-memory stub so the library never explodes off-engine.
    def self.default
      $gtk ? Gtk.new : Memory.new
    end
  end
end
