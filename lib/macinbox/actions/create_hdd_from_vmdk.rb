require 'fileutils'
require 'shellwords'

require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class CreateHDDFromVMDK

      def initialize(opts)
        @input_image       = opts[:vmdk_path]     or raise ArgumentError.new(":vmdk_path not specified")
        @output_path       = opts[:hdd_path]       or raise ArgumentError.new(":hdd_path not specified")
        @app_path          = opts[:parallels_path] or raise ArgumentError.new(":parallels_path not specified")

        @collector         = opts[:collector]   or raise ArgumentError.new(":collector not specified")
        @debug             = opts[:debug]

        raise Macinbox::Error.new("input image not found")   unless File.exist? @input_image
        raise Macinbox::Error.new("Parallels not found") unless File.exist? @app_path
      end

      def run
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_hdd_from_vmdk ]
        @collector.add_temp_dir @temp_dir

        Logger.info "Converting the VMDK to HDD format..." do
          prl_convert = "#{@app_path}/Contents/MacOS/prl_convert"
          prl_disk_tool = "#{@app_path}/Contents/MacOS/prl_disk_tool"
          task_opts = @debug ? {} : { :out => File::NULL }
          Task.run %W[ #{prl_convert} #{@input_image} --allow-no-os --dst=#{@temp_dir} ] + [task_opts]
        end

        Logger.info "Moving the HDD to the destination..." do
          hdd_name = "#{File.basename(@input_image, ".*")}.hdd"
          FileUtils.chown_R ENV["SUDO_USER"], nil, "#{@temp_dir}/#{hdd_name}"
          FileUtils.mv "#{@temp_dir}/#{hdd_name}", @output_path
        end

      end

    end

  end

end
