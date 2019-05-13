require 'fileutils'
require 'shellwords'

require 'macinbox/copyfiles'
require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'
require 'macinbox/virtual_disk'

module Macinbox

  module Actions

    class CreateVDIFromImage

      def initialize(opts)
        @input_image       = opts[:image_path]  or raise ArgumentError.new(":image_path not specified")
        @output_path       = opts[:vdi_path]    or raise ArgumentError.new(":vdi_path not specified")

        @collector         = opts[:collector]   or raise ArgumentError.new(":collector not specified")

        raise Macinbox::Error.new("input image not found")   unless File.exist? @input_image
      end

      def run
        create_temp_dir
        copy_input_image
        attach_image
        setup_efi_partition
        convert_image
        save_image
      end

      def create_temp_dir
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_vdi_from_image ]
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
          @disk.attach
        end
      end

      def setup_efi_partition
        Logger.info "Setting up EFI partition..." do
          efi_mountpoint = "#{@temp_dir}/efi_mountpoint"
          FileUtils.mkdir efi_mountpoint
          @disk.mount_efi(at: efi_mountpoint)
          Task.run %W[ /bin/mkdir -p #{efi_mountpoint}/EFI/drivers ]
          Task.run %W[ /bin/cp /usr/standalone/i386/apfs.efi #{efi_mountpoint}/EFI/drivers/ ]
          File.write "#{efi_mountpoint}/startup.nsh", <<~'EOF'
            @echo -off
            echo "Loading APFS driver..."
            load "fs0:\EFI\drivers\apfs.efi"
            echo "Refreshing media mappings..."
            map -r
            echo "Searching for bootloader..."
            for %d in fs1 fs2 fs3 fs4 fs5 fs6
              if exist "%d:\System\Library\CoreServices\boot.efi" then
                echo "Found %d:\System\Library\CoreServices\boot.efi, launching..."
                "%d:\System\Library\CoreServices\boot.efi"
              endif
            endfor
            echo "Failed."
          EOF
          @disk.unmount_efi
        end
      end

      def convert_image
        Logger.info "Converting the image to VDI format..." do
          task_opts = $verbose ? {} : { :out => File::NULL }
          Task.run %W[ VBoxManage convertfromraw #{@disk.device} #{@temp_dir}/macinbox.vdi --format VDI ] + [task_opts]
        end
      end

      def save_image
        Logger.info "Moving the VDI to the destination..." do
          @disk.eject
          FileUtils.chown ENV["SUDO_USER"], nil, "#{@temp_dir}/macinbox.vdi"
          FileUtils.mv "#{@temp_dir}/macinbox.vdi", @output_path
        end
      end

    end

  end

end
