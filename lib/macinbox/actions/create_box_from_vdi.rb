require 'fileutils'
require 'rubygems/package'

require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class CreateBoxFromVDI

      def initialize(opts)
        @input_vdi         = opts[:vdi_path]        or raise ArgumentError.new(":vdi_path not specified")
        @output_path       = opts[:box_path]        or raise ArgumentError.new(":box_path not specified")

        @box_name          = opts[:box_name]        or raise ArgumentError.new(":box_name not specified")
        @cpu_count         = opts[:cpu_count]       or raise ArgumentError.new(":cpu_count not specified")
        @memory_size       = opts[:memory_size]     or raise ArgumentError.new(":memory_size not specified")

        @gui               = opts[:gui]
        @fullscreen        = opts[:fullscreen]
        @hidpi             = opts[:hidpi]

        @collector         = opts[:collector]       or raise ArgumentError.new(":collector not specified")

        raise Macinbox::Error.new("VDI not found") unless File.exist? @input_vdi
      end

      def run
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_box_from_vdi ]
        @collector.add_temp_dir @temp_dir

        Logger.info "Assembling the box contents..." do

          @box_dir = "#{@temp_dir}/#{@box_name}.box"

          FileUtils.mkdir @box_dir

          File.write "#{@box_dir}/metadata.json", <<~EOF
            {"provider": "virtualbox"}
          EOF

          File.write "#{@box_dir}/Vagrantfile", <<~EOF
            Vagrant.configure(2) do |config|
              config.vm.box_check_update = false
              config.vm.synced_folder ".", "/vagrant", disabled: true
              config.vm.provider "virtualbox" do |v|
                v.gui = #{@gui}
              end
            end
          EOF

          task_opts = $verbose ? {} : { :out => File::NULL }

          Task.run %W[ VBoxManage createvm --register --name macinbox --ostype MacOS1013_64 ] + [task_opts]

          @collector.on_cleanup do
            Task.run %W[ VBoxManage unregistervm macinbox --delete ] + [task_opts]
          end

          Task.run %W[ VBoxManage modifyvm macinbox --usbxhci on --memory #{@memory_size} --vram 128 --cpus #{@cpu_count} --firmware efi --chipset ich9 --mouse usbtablet --keyboard usb ] + [task_opts]
          Task.run %W[ VBoxManage setextradata macinbox CustomVideoMode1 1280x800x32 ] + [task_opts]
          Task.run %W[ VBoxManage setextradata macinbox VBoxInternal2/EfiGraphicsResolution 1280x800 ] + [task_opts]
          Task.run %W[ VBoxManage setextradata macinbox GUI/ScaleFactor 2.0 ] + [task_opts] if @hidpi
          Task.run %W[ VBoxManage storagectl macinbox --name #{"SATA Controller"} --add sata --controller IntelAHCI --hostiocache on ] + [task_opts]
          Task.run %W[ VBoxManage storageattach macinbox --storagectl #{"SATA Controller"} --port 0 --device 0 --type hdd --nonrotational on --medium #{@input_vdi} ] + [task_opts]
          Task.run %W[ VBoxManage modifyvm macinbox --boot1 disk ] + [task_opts]
          Task.run %W[ VBoxManage export macinbox -o #{@box_dir}/box.ovf ] + [task_opts]

        end

        Logger.info "Moving the box to the destination..." do
          FileUtils.chown_R ENV["SUDO_USER"], nil, @box_dir
          FileUtils.mv @box_dir, @output_path
        end

      end

    end

  end

end
