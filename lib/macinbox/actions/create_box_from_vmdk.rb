require 'fileutils'
require 'rubygems/package'

require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class CreateBoxFromVMDK

      def initialize(opts)
        @input_vmdk        = opts[:vmdk_path]       or bail "Input VMDK not specified."
        @output_path       = opts[:box_path]        or bail "Output path not specified."
        @vmware_fusion_app = opts[:vmware_path]     or bail "VMWare Fusion app not specified."

        @box_name          = opts[:box_name]        or bail "Box name not specified."
        @cpu_count         = opts[:cpu_count]       or bail "CPU count not specified."
        @memory_size       = opts[:memory_size]     or bail "Memory size not specified."
        @gui               = opts[:gui]             or bail "GUI not specified."
        @fullscreen        = opts[:fullscreen]      or bail "Fullscreen not specified."
        @hidpi             = opts[:hidpi]           or bail "HiDPI not specified."

        @collector         = opts[:collector]       or bail "Collector not specified."
        @debug             = opts[:debug] || false

        Logger.bail "Input VMDK not found."    unless File.exist? @input_vmdk
        Logger.bail "VMware Fusion not found." unless File.exist? @vmware_fusion_app
      end

      def run
        create_temp_dir
        create_box
        package_box
        move_box
      end

      def create_temp_dir
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_box_from_vmdk ]
        @collector.on_cleanup do
          if @temp_dir and File.exist? @temp_dir
            FileUtils.rm_rf @temp_dir
          end
        end
      end

      def create_box
        Logger.info "Creating the box..."

        File.open "#{@temp_dir}/#{@box_name}.vmx", 'w' do |file|

          file.write <<~EOF
            .encoding = "UTF-8"
            config.version = "8"
            virtualHW.version = "14"
            numvcpus = "#{@cpu_count}"
            memsize = "#{@memory_size}"
            sata0.present = "TRUE"
            sata0:0.fileName = "#{@box_name}.vmdk"
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
            nvram = "#{@box_name}.nvram"
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
            extendedConfigFile = "#{@box_name}.vmxf"
            floppy0.present = "FALSE"
            mks.enable3d = "FALSE"
          EOF

          if @fullscreen == "true"
          	file.write <<~EOF
              gui.viewModeAtPowerOn = "fullscreen"
            EOF
          end

          if @hidpi == "true"
          	file.write <<~EOF
              gui.fitGuestUsingNativeDisplayResolution = "TRUE"
            EOF
          end

        end

        File.write "#{@temp_dir}/metadata.json", <<~EOF
          {"provider": "vmware_fusion"}
        EOF

        File.write "#{@temp_dir}/Vagrantfile", <<~EOF
          ENV["VAGRANT_DEFAULT_PROVIDER"] = "vmware_fusion"
          Vagrant.configure(2) do |config|
            config.vm.network :forwarded_port, guest: 22, host: 2222, id: "ssh", disabled: true
            config.vm.synced_folder ".", "/vagrant", disabled: true
            config.vm.provider "vmware_fusion" do |v|
              v.gui = #{@gui}
            end
          end
        EOF

      end

      def package_box
        Logger.info "Packaging the box..." do

          filenames_and_sources = {
            "#{@box_name}.vmx" => "#{@temp_dir}/#{@box_name}.vmx",
            "metadata.json" => "#{@temp_dir}/metadata.json",
            "Vagrantfile" => "#{@temp_dir}/Vagrantfile",
            File.basename(@input_vmdk) => @input_vmdk
          }

          File.open("#{@temp_dir}/#{@box_name}.box", "wb") do |file|
            Zlib::GzipWriter.wrap(file) do |gzip|
              Gem::Package::TarWriter.new(gzip) do |tar|
                filenames_and_sources.each_pair do |filename, source|
                  tar.add_file_simple(filename, 0644, File.size(source)) do |io|
                    activity = Logger.prefix + File.basename(source)
                    Task.write_file_to_io_with_progress activity, source, io
                  end
                end
              end
            end
          end
        end
      end

      def move_box
        Logger.info "Moving the box to the destination..."
        FileUtils.chown ENV["SUDO_USER"], nil, "#{@temp_dir}/#{@box_name}.box"
        FileUtils.mv "#{@temp_dir}/#{@box_name}.box", @output_path
      end

    end

  end

end
