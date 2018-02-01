require 'macinbox/cli/options'

require 'pathname'
require 'fileutils'

require "macinbox/actions"
require "macinbox/collector"
require 'macinbox/logger'

module Macinbox

  class CLI

    def self.start(argv)
      cli = self.new
      cli.start(argv)
      cli
    end

    def start(argv)

      parse_options(argv)
      check_for_sudo_root

      if not File.exists? @options[:installer_path]
        Logger.bail "Installer app not found: #{installer_path}"
      end

      if not File.exists? @options[:vmware_path]
        Logger.bail "VMware Fusion app not found: #{installer_path}"
      end

      root_temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t macinbox_root ]
      user_temp_dir = Task.backtick %W[ sudo -u #{ENV["SUDO_USER"]} /usr/bin/mktemp -d -t macinbox_user ]

      collector = Collector.new

      collector.on_cleanup do
        if @options[:debug]
          Logger.error "WARNING: Temporary files were not removed. Run this command to remove them:"
          Logger.error "sudo rm -rf #{Shellwords.escape(root_temp_dir)} #{Shellwords.escape(user_temp_dir)}"
        else
          FileUtils.remove_dir(root_temp_dir)
          FileUtils.remove_dir(user_temp_dir)
        end
        STDERR.print %x( tput cnorm )
      end

      ["TERM", "INT", "EXIT"].each do |signal|
        trap signal do
          trap signal, "SYSTEM_DEFAULT" unless signal == "EXIT"
          Process.waitall
          Logger.info "Cleaning up..."
          collector.cleanup!
          Process.kill(signal, Process.pid) unless signal == "EXIT"
        end
      end

      collector.on_cleanup do
        if @temp_dir and File.exist? @temp_dir
          FileUtils.rm_rf @temp_dir
        end
      end

      @options[:image_path] = "macinbox.dmg"
      @options[:vmdk_path] = "macinbox.vmdk"
      @options[:box_path] = "macinbox.box"
      @options[:collector] = collector

      Dir.chdir(root_temp_dir) do

        Logger.info "Creating image from installer..." do
          Actions::CreateImageFromInstaller.new(@options).run
        end

        Logger.info "Creating VMDK from image..." do
          Actions::CreateVMDKFromImage.new(@options).run
        end

        Logger.info "Creating box from VMDK..." do
          Actions::CreateBoxFromVMDK.new(@options).run
        end

      end

      Dir.chdir(user_temp_dir) do
        Logger.info "Adding box to Vagrant..."
        FileUtils.mv "#{root_temp_dir}/macinbox.box", "#{@options[:box_name]}.box"
        FileUtils.chown ENV["SUDO_USER"], nil, "#{@options[:box_name]}.box"
        Task.run_as_sudo_user %W[ vagrant box add #{@options[:box_name]}.box --name #{@options[:box_name]} ] + [ @options[:debug] ? {} : { :out => File::NULL } ]
      end
    end

    def check_for_sudo_root
      if Process.uid != 0 or ENV["SUDO_USER"].nil?
        STDERR.puts "Error: Script must be run as root with sudo."
        STDERR.puts
        STDERR.puts @option_parser
        exit 1
      end
    end

  end
end
