require 'fileutils'

require 'macinbox/copyfiles'
require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class InstallBox

      def initialize(opts)
        @input_box   = opts[:box_path]   or raise ArgumentError.new(":box_path not specified")
        @box_name    = opts[:box_name]   or raise ArgumentError.new(":box_name not specified")
        @box_format  = opts[:box_format] or raise ArgumentError.new(":box_format not specified")
        @boxes_dir   = opts[:boxes_dir]  or raise ArgumentError.new(":boxes_dir not specified")

        @box_version = opts[:macos_version].to_s rescue nil

        raise Macinbox::Error.new("box not found: #{@input_box}") unless File.exist? @input_box
        raise Macinbox::Error.new("boxes directory not found: #{@boxes_dir}") unless File.exist? @boxes_dir
      end

      def target_box_dir
        "#{@boxes_dir}/#{@box_name}/#{@box_version}/#{@box_format}"
      end

      def run
        Logger.info "Copying box to #{@boxes_dir}..." do
          if !@box_version || File.exist?(target_box_dir)
            @box_version = Dir["#{@boxes_dir}/#{@box_name}/*/*"].map { |o| o.split('/')[-2].to_i }.sort.last.next rescue 0
          end
          raise Macinbox::Error.new("box already exists") if File.exist? target_box_dir
          Task.run %W[ /bin/mkdir -p #{target_box_dir} ]
          Macinbox::copyfiles(from: Dir["#{@input_box}/*"], to: target_box_dir, recursive: true)
          Task.run %W[ /usr/sbin/chown -R #{ENV["SUDO_USER"]} #{@boxes_dir}/#{@box_name} ]
          Logger.info "Installed box: #{@box_name} (#{@box_format}, #{@box_version})"
        end
      end

    end
  end
end
