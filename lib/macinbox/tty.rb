module Macinbox
  module TTY
    BLACK = %x(tput setaf 0)
    RED = %x(tput setaf 1)
    GREEN = %x(tput setaf 2)
    CLEAR_LINE = "\r" + %x( tput el )
    CURSOR_INVISIBLE = %x( tput civis )
    CURSOR_NORMAL = %x( tput cnorm )
  end
end
