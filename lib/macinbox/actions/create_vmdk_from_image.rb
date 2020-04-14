require 'fileutils'
require 'shellwords'

require 'macinbox/copyfiles'
require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'
require 'macinbox/virtual_disk'
require 'macinbox/vmdk'

module Macinbox

  module Actions

    class CreateVMDKFromImage

      def initialize(opts)
        @input_image       = opts[:image_path]    or raise ArgumentError.new(":image_path not specified")
        @output_path       = opts[:vmdk_path]     or raise ArgumentError.new(":vmdk_path not specified")
        @vmware_fusion_app = opts[:vmware_path]   or raise ArgumentError.new(":vmware_path not specified")
        @use_qemu          = opts[:use_qemu]

        @macos_version     = opts[:macos_version] or raise ArgumentError.new(":macos_version not specified")

        @collector         = opts[:collector]     or raise ArgumentError.new(":collector not specified")

        raise Macinbox::Error.new("input image not found")   unless File.exist? @input_image
        raise Macinbox::Error.new("VMware Fusion not found") unless File.exist? @vmware_fusion_app

        if @use_qemu
          raise Macinbox::Error.new("qemu-img not found") unless File.exist? "/usr/local/bin/qemu-img"
        end
      end

      def run
        create_temp_dir
        copy_input_image
        attach_image
        set_spc_kextpolicy
        install_vmware_tools
        eject_image
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
          @disk = VirtualDisk.new(@image)
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
              Task.run %W[ /usr/bin/curl #{darwin_iso_url} -O ] + ($verbose ? [] : %W[ -s -S ])
              Task.run %W[ /usr/bin/tar -xf com.vmware.fusion.tools.darwin.zip.tar com.vmware.fusion.tools.darwin.zip ]
              Task.run %W[ /usr/bin/unzip ] + ($verbose ? [] : %W[ -qq ]) + %W[ com.vmware.fusion.tools.darwin.zip payload/darwin.iso ]
            end
            tools_image = "#{@temp_dir}/payload/darwin.iso"
          end
        end

        Logger.info "Installing the VMware Tools..." do
          tools_disk = VirtualDisk.new(tools_image)
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
          unless File.exist? image_spc_kextpolicy
            Task.run_with_input %W[ /usr/bin/sqlite3 #{image_spc_kextpolicy} ] do |pipe|
              pipe.write <<~EOF
                PRAGMA foreign_keys=OFF;
                BEGIN TRANSACTION;
                CREATE TABLE kext_load_history_v3 ( path TEXT PRIMARY KEY, team_id TEXT, bundle_id TEXT, boot_uuid TEXT, created_at TEXT, last_seen TEXT, flags INTEGER );
                CREATE TABLE kext_policy ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, developer_name TEXT, flags INTEGER, PRIMARY KEY (team_id, bundle_id) );
                CREATE TABLE kext_policy_mdm ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, payload_uuid TEXT, PRIMARY KEY (team_id, bundle_id) );
                CREATE TABLE settings ( name TEXT, value TEXT, PRIMARY KEY (name) );
                COMMIT;
              EOF
            end
          end
          Task.run_with_input %W[ /usr/bin/sqlite3 #{image_spc_kextpolicy} ] do |pipe|
            pipe.write <<~EOF
              PRAGMA foreign_keys=OFF;
              BEGIN TRANSACTION;
              INSERT OR REPLACE INTO kext_load_history_v3 VALUES('/Library/Extensions/VMwareGfx.kext','EG7KH642X6','com.vmware.kext.VMwareGfx','F5E8FB21-EE9B-47F0-9C9C-FD6C4E41AC99','2020-04-13 16:29:03','2020-04-13 16:30:58',55);
              INSERT OR REPLACE INTO kext_load_history_v3 VALUES('/Library/Application Support/VMware Tools/vmhgfs.kext','EG7KH642X6','com.vmware.kext.vmhgfs','F5E8FB21-EE9B-47F0-9C9C-FD6C4E41AC99','2020-04-13 16:29:04','2020-04-13 16:29:45',53);
              INSERT OR REPLACE INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.VMwareGfx',1,'VMware, Inc.',1);
              INSERT OR REPLACE INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmmemctl',1,'VMware, Inc.',1);
              INSERT OR REPLACE INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmhgfs',1,'VMware, Inc.',1);
              COMMIT;
            EOF
          end
        end
      end

      def eject_image
        @disk.eject
      end

      def convert_image
        Logger.info "Converting the image to VMDK format#{@use_qemu ? " using QEMU" : ""}..." do
          if @use_qemu
            @disk.convert(outfile: "#{@temp_dir}/macinbox.dmg")
            Task.run %W[ /usr/local/bin/qemu-img convert -f dmg -O vmdk #{@temp_dir}/macinbox.dmg #{@temp_dir}/macinbox.vmdk ]
          else
            @disk.attach
            task_opts = $verbose ? {} : { :out => File::NULL }
            vdiskmanager = "#{@vmware_fusion_app}/Contents/Library/vmware-vdiskmanager"
            Dir.chdir(@temp_dir) do
              VMDK.create_raw_vmdk(@disk.device, "rawdisk.vmdk")
              begin
                Task.run %W[ #{vdiskmanager} -t 0 -r rawdisk.vmdk macinbox.vmdk ] + [task_opts]
              rescue Macinbox::Error => e
                Logger.error "If the conversion failed due to an AppleXPC error please see https://kb.vmware.com/s/article/65163 for a possible workaround."
                raise e
              end
            end
            @disk.eject
          end
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
