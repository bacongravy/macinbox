require 'macinbox/tty'

module Macinbox
  class Logger
    PREFIXES = ["• ", "  + ", "    - "]
    @@depth = 0
    def self.prefix
      PREFIXES[@@depth]
    end
    def self.reset_depth
      @@depth = 0
    end
    def self.info(msg)
      STDERR.puts TTY::Color::GREEN + prefix + msg + TTY::Color::RESET
      if block_given?
        @@depth += 1
        yield
        @@depth -= 1
      end
    end
    def self.error(msg)
      STDERR.puts TTY::Color::RED + prefix + msg + TTY::Color::RESET
    end
  end
end
