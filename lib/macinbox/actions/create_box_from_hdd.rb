require 'fileutils'
require 'rubygems/package'

require 'macinbox/copyfiles'
require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class CreateBoxFromHDD

      def initialize(opts)
        @input_hdd         = opts[:hdd_path]        or raise ArgumentError.new(":hdd_path not specified")
        @output_path       = opts[:box_path]        or raise ArgumentError.new(":box_path not specified")

        @box_name          = opts[:box_name]        or raise ArgumentError.new(":box_name not specified")
        @cpu_count         = opts[:cpu_count]       or raise ArgumentError.new(":cpu_count not specified")
        @memory_size       = opts[:memory_size]     or raise ArgumentError.new(":memory_size not specified")

        @gui               = opts[:gui]
        @fullscreen        = opts[:fullscreen]
        @hidpi             = opts[:hidpi]

        @collector         = opts[:collector]       or raise ArgumentError.new(":collector not specified")

        raise Macinbox::Error.new("HDD not found") unless File.exist? @input_hdd
      end

      def run
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_box_from_hdd ]
        @collector.add_temp_dir @temp_dir

        Logger.info "Assembling the box contents..." do

          @box_dir = "#{@temp_dir}/#{@box_name}.box"

          FileUtils.mkdir @box_dir

          File.write "#{@box_dir}/metadata.json", <<~EOF
            {"provider": "parallels"}
          EOF

          File.write "#{@box_dir}/Vagrantfile", <<~EOF
            Vagrant.configure(2) do |config|
              config.vm.box_check_update = false
              config.vm.network :forwarded_port, guest: 22, host: 2222, id: "ssh", disabled: true
              config.vm.synced_folder ".", "/vagrant", disabled: true
              config.vm.provider "parallels" do |prl|
                prl.customize ["set", :id, "--startup-view", "#{@gui ? (@fullscreen ? "fullscreen" : "window") : "headless"}"]
              end
            end
          EOF

          task_opts = $verbose ? {} : { :out => File::NULL }

          Task.run %W[ prlctl create macinbox -o macos --no-hdd --dst #{@box_dir} ] + [task_opts]

          @collector.on_cleanup do
            Task.run %W[ prlctl unregister macinbox ] + [task_opts]
          end

          Macinbox::copyfiles(from: @input_hdd, to: "#{@box_dir}/macinbox.pvm/macinbox.hdd", recursive: true)
          
          Task.run %W[ prl_disk_tool convert --merge --hdd #{@box_dir}/macinbox.pvm/macinbox.hdd ] + [task_opts]
          Task.run %W[ prlctl set macinbox --device-add hdd --image #{@box_dir}/macinbox.pvm/macinbox.hdd ] + [task_opts]
          Task.run %W[ prlctl set macinbox --high-resolution #{@hidpi ? "on" : "off"} ] + [task_opts]
          Task.run %W[ prlctl set macinbox --cpus #{@cpu_count} ] + [task_opts]
          Task.run %W[ prlctl set macinbox --memsize #{@memory_size} ] + [task_opts]

        end

        Logger.info "Moving the box to the destination..." do
          FileUtils.chown ENV["SUDO_USER"], nil, @box_dir
          FileUtils.mv @box_dir, @output_path
        end

      end

    end

  end

end
