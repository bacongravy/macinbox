require 'macinbox/task'

module Macinbox

  def self.copyfiles(from:, to:, recursive: false)
    flags = recursive ? ['-R'] : []
    src = [*from]
    dest = [to]
    begin
      Task.run %W[ /bin/cp -c ] + flags + src + dest + [{ :err => File::NULL }]
    rescue
      Task.run %W[ /bin/cp ] + flags + src + dest
    end
  end

end
