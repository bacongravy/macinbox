require 'fileutils'

require 'macinbox/error'
require 'macinbox/logger'

module Macinbox

  module Actions

    class InstallBox

      def initialize(opts)
        @input_box  = opts[:box_path]   or raise ArgumentError.new(":box_path not specified")
        @box_name   = opts[:box_name]   or raise ArgumentError.new(":box_name not specified")
        @box_format = opts[:box_format] or raise ArgumentError.new(":box_format not specified")
        @boxes_dir  = opts[:boxes_dir]  or raise ArgumentError.new(":boxes_dir not specified")
        @debug      = opts[:debug]
        raise Macinbox::Error.new("box not found: #{@input_box}") unless File.exist? @input_box
        raise Macinbox::Error.new("boxes directory not found: #{@boxes_dir}") unless File.exist? @boxes_dir
      end

      def run
        Logger.info "Copying box to #{@boxes_dir}..." do
          box_name = @box_name
          box_version = Dir["#{@boxes_dir}/#{box_name}/*/*"].map { |o| o.split('/')[-2].to_i }.sort.last.next rescue 0
          box_provider = @box_format
          target_box_dir = "#{@boxes_dir}/#{box_name}/#{box_version}/#{box_provider}"
          raise Macinbox::Error.new("box already exists") if File.exist? target_box_dir
          FileUtils.mkdir_p target_box_dir
          FileUtils.cp_r Dir["#{@input_box}/*"], target_box_dir
          FileUtils.chown_R ENV["SUDO_USER"], nil, "#{@boxes_dir}/#{box_name}"
          Logger.info "Installed box: #{box_name} (#{box_provider}, #{box_version})"
        end
      end

    end
  end
end
