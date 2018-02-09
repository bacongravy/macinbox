require 'fileutils'

require 'macinbox/error'
require 'macinbox/logger'

module Macinbox

  module Actions

    class InstallBox

      def initialize(opts)
        @input_box = opts[:box_path] or raise ArgumentError.new(":box_path not specified")
        @box_name  = opts[:box_name] or raise ArgumentError.new(":box_name not specified")
        @debug     = opts[:debug]
        raise Macinbox::Error.new("box not found") unless File.exist? @input_box
      end

      def run
        Logger.info "Copying box to ~/.vagrant.d/boxes..." do
          vagrant_boxes_dir = File.expand_path "~/.vagrant.d/boxes"
          raise Macinbox::Error.new("~/.vagrant.d/boxes not found") unless File.exist? vagrant_boxes_dir
          box_name = @box_name
          box_version = Dir["#{vagrant_boxes_dir}/#{box_name}/*/*"].map { |o| o.split('/')[-2].to_i }.sort.last.next rescue 0
          box_provider = "vmware_fusion"
          target_box_dir = "#{vagrant_boxes_dir}/#{box_name}/#{box_version}/#{box_provider}"
          raise Macinbox::Error.new("box already exists") if File.exist? target_box_dir
          FileUtils.mkdir_p target_box_dir
          FileUtils.cp Dir["#{@input_box}/*"], target_box_dir
          FileUtils.chown_R ENV["SUDO_USER"], nil, "#{vagrant_boxes_dir}/#{box_name}"
          Logger.info "Installed box: #{box_name} (#{box_provider}, #{box_version})"
        end
      end

    end
  end
end
