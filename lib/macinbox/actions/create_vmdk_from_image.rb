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

      def self.startPrivilegedHelper(helper_name)
        targetBinDir = "/Library/PrivilegedHelperTools"
        targetPlistDir = "/Library/LaunchDaemons"
        sourceBin = "#{@vmware_fusion_app}/Contents/Library/LaunchServices/#{helper_name}"
        sourcePlist = "#{@vmware_fusion_app}/Contents/Library/LaunchServices/#{helper_name}.plist"
        targetBin = "#{targetBinDir}/#{helper_name}"
        targetPlist = "#{targetPlistDir}/#{helper_name}.plist"
        Task.run %W[ cp -f -- #{sourceBin} #{targetBinDir} ]
        Task.run %W[ chmod 544 #{targetBin} ]
        Task.run %W[ cp -f -- #{sourcePlist} #{targetPlistDir} ]
        Task.run %W[ chmod 644 #{targetPlist} ]
        Task.run %W[ launchctl load #{targetPlist} ]
      end

      def self.stopPrivilegedHelper(helperName)
        targetBin = "/Library/PrivilegedHelperTools/#{helper_name}"
        targetPlist = "/Library/LaunchDaemons/#{helper_name}.plist"
        Task.run %W[ launchctl stop #{targetBin} || true ]
        Task.run %W[ launchctl unload #{targetPlist} || true ]
        Task.run %W[ rm #{targetBin} || true ]
        Task.run %W[ rm #{targetPlist} || true ]
      end

      def run
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_vmdk_from_image ]
        @collector.add_temp_dir @temp_dir

        Logger.info "Attaching the image..." do

          @collector.on_cleanup do
            %x( diskutil eject #{@device.shellescape} > /dev/null 2>&1 ) if @device
          end

          @device = %x(
            hdiutil attach #{@input_image.shellescape} -nomount |
            grep _partition_scheme |
            cut -f1 |
            tr -d [:space:]
          )

          raise Macinbox::Error.new("failed to attach the image") unless File.exist? @device
        end

        Logger.info "Converting the image to VMDK format..." do
          rawdiskCreator = "#{@vmware_fusion_app}/Contents/Library/vmware-rawdiskCreator"
          vdiskmanager = "#{@vmware_fusion_app}/Contents/Library/vmware-vdiskmanager"
          CreateVMDKFromImage.startPrivilegedHelper("com.vmware.DiskHelper")
          CreateVMDKFromImage.startPrivilegedHelper("com.vmware.MountHelper")
          Dir.chdir(@temp_dir) do
            Task.run %W[ #{rawdiskCreator} create #{@device} fullDevice rawdisk lsilogic ]
            Task.run %W[ #{vdiskmanager} -t 0 -r rawdisk.vmdk macinbox.vmdk ]
          end
          CreateVMDKFromImage.stopPrivilegedHelper("com.vmware.DiskHelper")
          CreateVMDKFromImage.stopPrivilegedHelper("com.vmware.MountHelper")
          Task.run %W[ diskutil eject #{@device.shellescape} ]
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
