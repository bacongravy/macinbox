module Macinbox
  module TTY
    module Color
      RED = STDERR.isatty ? %x(tput setaf 1) : ""
      GREEN = STDERR.isatty ? %x(tput setaf 2) : ""
      RESET = STDERR.isatty ? %x(tput sgr0) : ""
    end
    module Line
      CLEAR = STDERR.isatty ? "\r" + %x( tput el ) : ""
    end
    module Cursor
      INVISIBLE = %x( tput civis )
      NORMAL = %x( tput cnorm )
    end
  end
end
