require 'fileutils'
require 'shellwords'

require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class CreateVDIFromImage

      def initialize(opts)
        @input_image       = opts[:image_path]  or raise ArgumentError.new(":image_path not specified")
        @output_path       = opts[:vdi_path]    or raise ArgumentError.new(":vdi_path not specified")

        @collector         = opts[:collector]   or raise ArgumentError.new(":collector not specified")
        @debug             = opts[:debug]

        raise Macinbox::Error.new("input image not found")   unless File.exist? @input_image
      end

      def run
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_vdi_from_image ]
        @collector.add_temp_dir @temp_dir

        Logger.info "Attaching the image..." do

          @collector.on_cleanup do
            %x( /usr/sbin/diskutil eject #{@device.shellescape} > /dev/null 2>&1 ) if @device
          end

          @device = %x(
            /usr/bin/hdiutil attach #{@input_image.shellescape} -nomount |
            /usr/bin/grep _partition_scheme |
            /usr/bin/cut -f1 |
            /usr/bin/tr -d [:space:]
          )

          raise Macinbox::Error.new("failed to attach the image") unless File.exist? @device
        end

        Logger.info "Converting the image to VDI format..." do
          task_opts = @debug ? {} : { :out => File::NULL }
          Task.run %W[ VBoxManage convertfromraw #{@device} #{@temp_dir}/macinbox.vdi --format VDI ] + [task_opts]
          Task.run %W[ /usr/sbin/diskutil eject #{@device} ] + [task_opts]
          @device = nil
        end

        Logger.info "Moving the VDI to the destination..." do
          FileUtils.chown ENV["SUDO_USER"], nil, "#{@temp_dir}/macinbox.vdi"
          FileUtils.mv "#{@temp_dir}/macinbox.vdi", @output_path
        end

      end

    end

  end

end
