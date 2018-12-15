module Macinbox
  module TTY
    module Color
      RED = STDERR.isatty ? %x(/usr/bin/tput setaf 1) : ""
      GREEN = STDERR.isatty ? %x(/usr/bin/tput setaf 2) : ""
      RESET = STDERR.isatty ? %x(/usr/bin/tput sgr0) : ""
    end
    module Line
      CLEAR = STDERR.isatty ? "\r" + %x( /usr/bin/tput el ) : ""
    end
    module Cursor
      INVISIBLE = %x( /usr/bin/tput civis )
      NORMAL = %x( /usr/bin/tput cnorm )
    end
  end
end
