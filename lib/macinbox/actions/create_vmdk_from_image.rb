require 'fileutils'
require 'shellwords'

require 'macinbox/copyfiles'
require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'
require 'macinbox/virtual_disk'

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
        create_temp_dir
        copy_input_image
        attach_image
        install_vmware_tools
        set_spc_kextpolicy
        eject_and_reattach_image
        convert_image
        save_image
      end

      def create_temp_dir
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_vmdk_from_image ]
        @collector.add_temp_dir @temp_dir
      end

      def copy_input_image
        Logger.info "Copying the image..." do
          @image = "#{@temp_dir}/macinbox.sparseimage"
          Macinbox::copyfiles(from: @input_image, to: @image)
        end
      end

      def attach_image
        Logger.info "Attaching the image..." do
          @disk = VirtualDisk.new(@image, @debug)
          @collector.on_cleanup { @disk.detach! }
          @image_mountpoint = "#{@temp_dir}/image_mountpoint"
          FileUtils.mkdir @image_mountpoint
          @disk.attach
          @disk.mount(at: @image_mountpoint, owners: true)
        end
      end

      def install_vmware_tools
        tools_image = "#{@vmware_fusion_app}/Contents/Library/isoimages/darwin.iso"

        unless File.exist? tools_image
          Logger.info "Downloading the VMware Tools..." do
            bundle_version = Task.backtick %W[ defaults read #{"/Applications/VMware Fusion.app/Contents/Info.plist"} CFBundleVersion ]
            bundle_short_version = Task.backtick %W[ defaults read #{"/Applications/VMware Fusion.app/Contents/Info.plist"} CFBundleShortVersionString ]
            darwin_iso_url = "http://softwareupdate.vmware.com/cds/vmw-desktop/fusion/#{bundle_short_version}/#{bundle_version}/packages/com.vmware.fusion.tools.darwin.zip.tar"
            Dir.chdir(@temp_dir) do
              Task.run %W[ /usr/bin/curl #{darwin_iso_url} -O ] + (@debug ? [] : %W[ -s -S ])
              Task.run %W[ /usr/bin/tar -xf com.vmware.fusion.tools.darwin.zip.tar com.vmware.fusion.tools.darwin.zip ]
              Task.run %W[ /usr/bin/unzip ] + (@debug ? [] : %W[ -qq ]) + %W[ com.vmware.fusion.tools.darwin.zip payload/darwin.iso ]
            end
            tools_image = "#{@temp_dir}/payload/darwin.iso"
          end
        end

        Logger.info "Installing the VMware Tools..." do
          tools_disk = VirtualDisk.new(tools_image, @debug)
          @collector.on_cleanup { tools_disk.detach! }
          tools_mountpoint = "#{@temp_dir}/tools_mountpoint"
          FileUtils.mkdir tools_mountpoint
          tools_disk.attach
          tools_disk.mount(at: tools_mountpoint)
          tools_package = "#{tools_mountpoint}/Install VMware Tools.app/Contents/Resources/VMware Tools.pkg"
          tools_package_dir = "#{@temp_dir}/tools_package"
          Task.run %W[ /usr/sbin/pkgutil --expand #{tools_package} #{tools_package_dir} ]
          Task.run %W[ /usr/bin/ditto -x -z #{tools_package_dir}/files.pkg/Payload #{@image_mountpoint} ]
          image_vmhgfs_filesystem_resources = "#{@image_mountpoint}/Library/Filesystems/vmhgfs.fs/Contents/Resources"
          FileUtils.mkdir_p image_vmhgfs_filesystem_resources
          FileUtils.ln_s "/Library/Application Support/VMware Tools/mount_vmhgfs", "#{image_vmhgfs_filesystem_resources}/"
          tools_disk.eject
        end
      end

      def set_spc_kextpolicy
        Logger.info "Setting the KextPolicy to allow loading the VMware kernel extensions..." do
          image_spc_kextpolicy = "#{@image_mountpoint}/private/var/db/SystemPolicyConfiguration/KextPolicy"
          Task.run_with_input %W[ /usr/bin/sqlite3 #{image_spc_kextpolicy} ] do |pipe|
            pipe.write <<~EOF
              PRAGMA foreign_keys=OFF;
              BEGIN TRANSACTION;
              CREATE TABLE kext_load_history_v3 ( path TEXT PRIMARY KEY, team_id TEXT, bundle_id TEXT, boot_uuid TEXT, created_at TEXT, last_seen TEXT, flags INTEGER );
              CREATE TABLE kext_policy ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, developer_name TEXT, flags INTEGER, PRIMARY KEY (team_id, bundle_id) );
              INSERT INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.VMwareGfx',1,'VMware, Inc.',1);
              INSERT INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmmemctl',1,'VMware, Inc.',1);
              INSERT INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmhgfs',1,'VMware, Inc.',1);
              CREATE TABLE kext_policy_mdm ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, payload_uuid TEXT, PRIMARY KEY (team_id, bundle_id) );
              CREATE TABLE settings ( name TEXT, value TEXT, PRIMARY KEY (name) );
              COMMIT;
            EOF
          end
        end
      end

      def eject_and_reattach_image
        Logger.info "Reattaching the image..." do
          @disk.eject
          @disk.attach
        end
      end

      def convert_image
        Logger.info "Converting the image to VMDK format..." do
          task_opts = @debug ? {} : { :out => File::NULL }
          rawdiskCreator = "#{@vmware_fusion_app}/Contents/Library/vmware-rawdiskCreator"
          vdiskmanager = "#{@vmware_fusion_app}/Contents/Library/vmware-vdiskmanager"
          Dir.chdir(@temp_dir) do
            Task.run %W[ #{rawdiskCreator} create #{@disk.device} fullDevice rawdisk lsilogic ] + [task_opts]
            Task.run %W[ #{vdiskmanager} -t 0 -r rawdisk.vmdk macinbox.vmdk ] + [task_opts]
          end
          @disk.eject
        end
      end

      def save_image
        Logger.info "Moving the VMDK to the destination..." do
          FileUtils.chown ENV["SUDO_USER"], nil, "#{@temp_dir}/macinbox.vmdk"
          FileUtils.mv "#{@temp_dir}/macinbox.vmdk", @output_path
        end
      end

    end

  end

end
