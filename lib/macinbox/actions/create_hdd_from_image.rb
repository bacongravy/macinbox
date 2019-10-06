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

    class CreateHDDFromImage

      def initialize(opts)
        @input_image       = opts[:image_path]     or raise ArgumentError.new(":image_path not specified")
        @output_path       = opts[:hdd_path]       or raise ArgumentError.new(":hdd_path not specified")
        @parallels_app     = opts[:parallels_path] or raise ArgumentError.new(":parallels_path not specified")

        @collector         = opts[:collector]      or raise ArgumentError.new(":collector not specified")

        raise Macinbox::Error.new("input image not found")       unless File.exist? @input_image
        raise Macinbox::Error.new("Parallels Desktop not found") unless File.exist? @parallels_app
      end

      def run
        create_temp_dir
        copy_input_image
        attach_image
        install_parallels_tools
        eject_and_reattach_image
        convert_image
        save_image
      end

      def create_temp_dir
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_hdd_from_image ]
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

      def install_parallels_tools

        Logger.info "Installing the Parallels Tools..." do

          tools_image = "#{@parallels_app}/Contents/Resources/Tools/prl-tools-mac.iso"

          tools_disk = VirtualDisk.new(tools_image)

          @collector.on_cleanup { tools_disk.detach! }

          tools_mountpoint = "#{@temp_dir}/tools_mountpoint"
          FileUtils.mkdir tools_mountpoint

          tools_disk.attach
          tools_disk.mount(at: tools_mountpoint)

          tools_packages_dir = "#{tools_mountpoint}/Install.app/Contents/Resources/Install.mpkg/Contents/Packages"

          tools_packages = [
            "Parallels Tools Audio 10.9.pkg",
            "Parallels Tools Coherence.pkg",
            "Parallels Tools CopyPaste.pkg",
            "Parallels Tools DragDrop.pkg",
            "Parallels Tools HostTime.pkg",
            "Parallels Tools InstallationAgent.pkg",
            "Parallels Tools Network 10.9.pkg",
            "Parallels Tools SharedFolders.pkg",
            "Parallels Tools TimeSync.pkg",
            "Parallels Tools ToolGate 10.9.pkg",
            "Parallels Tools Utilities.pkg",
            "Parallels Tools Video 10.9.pkg"
          ]

          tools_expanded_packages_dir = "#{@temp_dir}/tools_packages"
          FileUtils.mkdir tools_expanded_packages_dir

          tools_packages.each do |package|
            if File.exist? "#{tools_packages_dir}/#{package}"
              Task.run %W[ /usr/sbin/pkgutil --expand #{tools_packages_dir}/#{package} #{tools_expanded_packages_dir}/#{package} ]
              Task.run %W[ /usr/bin/ditto -x -z #{tools_expanded_packages_dir}/#{package}/Payload #{@image_mountpoint} ]
            end
          end

          prl_nettool_source = "/Library/Parallels Guest Tools/prl_nettool"
          prl_nettool_target = "#{@image_mountpoint}/usr/local/bin/prl_nettool"

          FileUtils.mkdir_p File.dirname(prl_nettool_target)
          FileUtils.ln_s prl_nettool_source, prl_nettool_target

          prl_fsd_plist = "#{@image_mountpoint}/Library/LaunchDaemons/com.parallels.vm.prl_fsd.plist"
          Task.run %W[ /usr/bin/sed -i #{''} s/PARALLELS_ADDITIONAL_ARGS/--share/ #{prl_fsd_plist} ]

          contents = "/Library/Parallels\ Guest\ Tools/dynres --enable-retina\n"
          File.write "#{@image_mountpoint}/private/etc/rc.vagrant", contents, mode: 'a'

          tools_disk.eject
        end

        def eject_and_reattach_image
          Logger.info "Reattaching the image..." do
            @disk.eject
            @disk.attach
          end
        end

        def convert_image
          Logger.info "Converting the image to HDD format..." do
            VMDK.create_raw_vmdk(@disk.device, "#{@temp_dir}/macinbox.vmdk")
            prl_convert = "#{@parallels_app}/Contents/MacOS/prl_convert"
            task_opts = $verbose ? {} : { :out => File::NULL }
            Task.run %W[ #{prl_convert} #{@temp_dir}/macinbox.vmdk --allow-no-os --dst=#{@temp_dir} ] + [task_opts]
            @disk.eject
          end
        end

        def save_image
          Logger.info "Moving the HDD to the destination..." do
            FileUtils.chown_R ENV["SUDO_USER"], nil, "#{@temp_dir}/macinbox.hdd"
            FileUtils.mv "#{@temp_dir}/macinbox.hdd", @output_path
          end
        end

      end

    end

  end

end
