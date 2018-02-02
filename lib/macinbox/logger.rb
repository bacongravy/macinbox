require 'macinbox/tty'

module Macinbox
  class Logger
    include TTY
    PREFIXES = ["• ", "  + ", "    - "]
    @@depth = 0
    def self.prefix
      PREFIXES[@@depth]
    end
    def self.reset_depth
      @@depth = 0
    end
    def self.info(msg)
      STDERR.puts GREEN + prefix + msg + BLACK
      if block_given?
        @@depth += 1
        yield
        @@depth -= 1
      end
    end
    def self.error(msg)
      STDERR.puts RED + prefix + msg + BLACK
    end
  end
end
