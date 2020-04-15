require 'fileutils'
require 'macinbox/logger'

module Macinbox
  class Collector
    def initialize(preserve_temp_dirs: false)
      @temp_dirs = []
      @blocks = []
      @preserve_temp_dirs = preserve_temp_dirs
    end
    def add_temp_dir(temp_dir)
      @temp_dirs << temp_dir
    end
    def remove_temp_dirs
      if @preserve_temp_dirs
        temp_dir_args = @temp_dirs.reverse.map { |o| o.shellescape }.join(" \\\n")
        Logger.error "WARNING: Temporary files were not removed. Run this command to remove them:"
        Logger.error "sudo rm -rf #{temp_dir_args}"
      else
        @temp_dirs.reverse_each do |temp_dir|
          FileUtils.remove_dir(temp_dir)
        end
      end
    end
    def on_cleanup(&block)
      @blocks << block
    end
    def cleanup!
      @blocks.reverse.each do |block|
        block.call
      end
      remove_temp_dirs
      @blocks = []
      @temp_dirs = []
    end
  end
end
