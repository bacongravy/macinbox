require 'fileutils'

module Macinbox
  class Collector
    def initialize
      @temp_dirs = []
      @blocks = []
    end
    def add_temp_dir(temp_dir)
      @temp_dirs << temp_dir
    end
    def temp_dirs
      @temp_dirs
    end
    def remove_temp_dirs
      @temp_dirs.reverse.each do |temp_dir|
        FileUtils.remove_dir(temp_dir)
      end
    end
    def on_cleanup(&block)
      @blocks << block
    end
    def cleanup!
      @blocks.reverse.each do |block|
        block.call
      end
      @blocks = []
      @temp_dirs = []
    end
  end
end
