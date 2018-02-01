require 'fileutils'
require 'shellwords'

require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class CreateVMDKFromImage

      def initialize(opts)
        @input_image = opts[:image_path]        or bail "Installer app not specified."
        @output_path = opts[:vmdk_path]         or bail "Output path not specified."
        @vmware_fusion_app = opts[:vmware_path] or bail "VMWare Fusion app not specified."

        @collector = opts[:collector]
        @debug = opts[:debug] || false

        Logger.bail "Input image not found."   unless File.exist? @input_image
        Logger.bail "VMware Fusion not found." unless File.exist? @vmware_fusion_app
      end

      def run
        create_temp_dir
        mount_image
        convert_image
        move_vmdk
      end

      def create_temp_dir
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_vmdk_from_image ]
      end

      def mount_image
        Logger.info "Mounting the image..."

        @collector.on_cleanup do
          %x( hdiutil detach -quiet -force #{@mountpoint.shellescape} > /dev/null 2>&1 ) if @mountpoint
          %x( diskutil eject #{@device.shellescape} > /dev/null 2>&1 ) if @device
        end

        @mountpoint = "#{@temp_dir}/image_mountpoint"

        FileUtils.mkdir @mountpoint

        @device = Task.backtick %W[
        	hdiutil attach #{@input_image} -mountpoint #{@mountpoint} -nobrowse -owners on |
        	grep _partition_scheme |
        	cut -f1 |
        	tr -d [:space:]
        ]

        Logger.bail "Failed to mount the image." unless File.exist? @device
      end

      def convert_image
        Logger.info "Converting the image to VMDK format..."
        rawdiskCreator = "#{@vmware_fusion_app}/Contents/Library/vmware-rawdiskCreator"
        vdiskmanager = "#{@vmware_fusion_app}/Contents/Library/vmware-vdiskmanager"
        Dir.chdir(@temp_dir) do
          Task.run %W[ #{rawdiskCreator} create  #{@device} fullDevice rawdisk lsilogic ]
          Task.run %W[ #{vdiskmanager} -t 0 -r rawdisk.vmdk macinbox.vmdk ]
        end
      end

      def move_vmdk
        Logger.info "Moving the VMDK to the destination..."
        FileUtils.chown ENV["SUDO_USER"], nil, "#{@temp_dir}/macinbox.vmdk"
        FileUtils.mv "#{@temp_dir}/macinbox.vmdk", @output_path
      end

    end

  end

end
