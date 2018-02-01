module Macinbox
  class Logger
    BLACK = %x(tput setaf 0)
    RED = %x(tput setaf 1)
    GREEN = %x(tput setaf 2)
    PREFIXES = ["• ", "  + ", "    - "]
    @@depth = 0
    def self.prefix
      PREFIXES[@@depth]
    end
    def self.info(msg)
      STDERR.puts GREEN + prefix + msg + BLACK
      if block_given?
        @@depth += 1
        begin
          yield
        ensure
          @@depth -= 1
        end
      end
    end
    def self.error(msg)
      STDERR.puts RED + prefix + msg + BLACK
    end
    def self.bail(msg)
    	Logger.error msg
    	exit 1
    end
  end
end
