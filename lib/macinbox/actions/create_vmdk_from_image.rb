require 'fileutils'
require 'shellwords'

require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class CreateVMDKFromImage

      def initialize(opts)
        @input_image       = opts[:image_path]  or raise ArgumentError.new(":image_path not specified")
        @output_path       = opts[:vmdk_path]   or raise ArgumentError.new(":vmdk_path not specified")
        @vmware_fusion_app = opts[:vmware_path] or raise ArgumentError.new(":vmware_path not specified")

        @collector         = opts[:collector]   or raise ArgumentError.new(":collector not specified")
        @debug             = opts[:debug]

        raise Macinbox::Error.new("input image not found")   unless File.exist? @input_image
        raise Macinbox::Error.new("VMware Fusion not found") unless File.exist? @vmware_fusion_app
      end

      def run
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_vmdk_from_image ]
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

        Logger.info "Converting the image to VMDK format..." do
          task_opts = @debug ? {} : { :out => File::NULL }
          rawdiskCreator = "#{@vmware_fusion_app}/Contents/Library/vmware-rawdiskCreator"
          vdiskmanager = "#{@vmware_fusion_app}/Contents/Library/vmware-vdiskmanager"
          Dir.chdir(@temp_dir) do
            Task.run %W[ #{rawdiskCreator} create #{@device} fullDevice rawdisk lsilogic ] + [task_opts]
            Task.run %W[ #{vdiskmanager} -t 0 -r rawdisk.vmdk macinbox.vmdk ] + [task_opts]
          end
          Task.run %W[ /usr/sbin/diskutil eject #{@device.shellescape} ] + [task_opts]
          @device = nil
        end

        Logger.info "Moving the VMDK to the destination..." do
          FileUtils.chown ENV["SUDO_USER"], nil, "#{@temp_dir}/macinbox.vmdk"
          FileUtils.mv "#{@temp_dir}/macinbox.vmdk", @output_path
        end

      end

    end

  end

end
