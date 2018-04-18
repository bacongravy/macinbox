require 'fileutils'
require 'rubygems/package'

require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class CreateBoxFromVMDK

      def initialize(opts)
        @input_vmdk        = opts[:vmdk_path]       or raise ArgumentError.new(":vmdk_path not specified")
        @output_path       = opts[:box_path]        or raise ArgumentError.new(":box_path not specified")

        @box_name          = opts[:box_name]        or raise ArgumentError.new(":box_name not specified")
        @cpu_count         = opts[:cpu_count]       or raise ArgumentError.new(":cpu_count not specified")
        @memory_size       = opts[:memory_size]     or raise ArgumentError.new(":memory_size not specified")

        @gui               = opts[:gui]
        @fullscreen        = opts[:fullscreen]
        @hidpi             = opts[:hidpi]

        @collector         = opts[:collector]       or raise ArgumentError.new(":collector not specified")
        @debug             = opts[:debug]

        raise Macinbox::Error.new("VMDK not found") unless File.exist? @input_vmdk
      end

      def run
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_box_from_vmdk ]
        @collector.add_temp_dir @temp_dir

        Logger.info "Assembling the box contents..." do

          @box_dir = "#{@temp_dir}/#{@box_name}.box"

          FileUtils.mkdir @box_dir

          File.open "#{@box_dir}/macinbox.vmx", 'w' do |file|

            file.write <<~EOF
              .encoding = "UTF-8"
              config.version = "8"
              virtualHW.version = "14"
              numvcpus = "#{@cpu_count}"
              memsize = "#{@memory_size}"
              sata0.present = "TRUE"
              sata0:0.fileName = "macinbox.vmdk"
              sata0:0.present = "TRUE"
              sata0:1.autodetect = "TRUE"
              sata0:1.deviceType = "cdrom-raw"
              sata0:1.fileName = "auto detect"
              sata0:1.startConnected = "FALSE"
              sata0:1.present = "TRUE"
              ethernet0.connectionType = "nat"
              ethernet0.addressType = "generated"
              ethernet0.virtualDev = "e1000e"
              ethernet0.linkStatePropagation.enable = "TRUE"
              ethernet0.present = "TRUE"
              usb.present = "TRUE"
              usb_xhci.present = "TRUE"
              ehci.present = "TRUE"
              ehci:0.parent = "-1"
              ehci:0.port = "0"
              ehci:0.deviceType = "video"
              ehci:0.present = "TRUE"
              pciBridge0.present = "TRUE"
              pciBridge4.present = "TRUE"
              pciBridge4.virtualDev = "pcieRootPort"
              pciBridge4.functions = "8"
              pciBridge5.present = "TRUE"
              pciBridge5.virtualDev = "pcieRootPort"
              pciBridge5.functions = "8"
              pciBridge6.present = "TRUE"
              pciBridge6.virtualDev = "pcieRootPort"
              pciBridge6.functions = "8"
              pciBridge7.present = "TRUE"
              pciBridge7.virtualDev = "pcieRootPort"
              pciBridge7.functions = "8"
              vmci0.present = "TRUE"
              smc.present = "TRUE"
              hpet0.present = "TRUE"
              ich7m.present = "TRUE"
              usb.vbluetooth.startConnected = "TRUE"
              board-id.reflectHost = "TRUE"
              firmware = "efi"
              displayName = "#{@box_name}"
              guestOS = "darwin17-64"
              nvram = "macinbox.nvram"
              virtualHW.productCompatibility = "hosted"
              keyboardAndMouseProfile = "macProfile"
              powerType.powerOff = "soft"
              powerType.powerOn = "soft"
              powerType.suspend = "soft"
              powerType.reset = "soft"
              tools.syncTime = "TRUE"
              sound.autoDetect = "TRUE"
              sound.virtualDev = "hdaudio"
              sound.fileName = "-1"
              sound.present = "TRUE"
              extendedConfigFile = "macinbox.vmxf"
              floppy0.present = "FALSE"
              mks.enable3d = "FALSE"
              gui.fitGuestUsingNativeDisplayResolution = "#{@hidpi ? "TRUE" : "FALSE"}"
              gui.viewModeAtPowerOn = "#{@fullscreen ? "fullscreen" : "windowed"}"
            EOF

          end

          File.write "#{@box_dir}/metadata.json", <<~EOF
            {"provider": "vmware_fusion"}
          EOF

          File.write "#{@box_dir}/Vagrantfile", <<~EOF
            ENV["VAGRANT_DEFAULT_PROVIDER"] = "vmware_fusion"
            Vagrant.configure(2) do |config|
              config.vm.box_check_update = false
              config.vm.network :forwarded_port, guest: 22, host: 2222, id: "ssh", disabled: true
              config.vm.synced_folder ".", "/vagrant", disabled: true
              config.vm.provider "vmware_fusion" do |v|
                v.vmx["ethernet0.virtualDev"] = "e1000e"
                v.gui = #{@gui}
              end
            end
          EOF

          FileUtils.cp @input_vmdk, "#{@box_dir}/macinbox.vmdk"

        end

        Logger.info "Moving the box to the destination..." do
          FileUtils.chown ENV["SUDO_USER"], nil, @box_dir
          FileUtils.mv @box_dir, @output_path
        end

      end

    end

  end

end
