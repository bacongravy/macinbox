require 'macinbox/cli/options'

require 'pathname'
require 'fileutils'

require "macinbox/actions"
require "macinbox/collector"
require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/tty'

module Macinbox

  class CLI

    def self.run!(argv)
      begin
        self.new.start(argv)
      rescue Macinbox::Error => e
        Logger.error "Error: " + e.to_s
        exit 1
      end
      exit 0
    end

    def start(argv)

      parse_options(argv)

      check_for_sudo_root

      if not File.exists? @options[:installer_path]
        raise Macinbox::Error.new("Installer app not found: #{@options[:installer_path]}")
      end

      if not File.exists? @options[:vmware_path]
        raise Macinbox::Error.new("VMware Fusion app not found: #{@options[:vmware_path]}")
      end

      root_temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t macinbox_root_temp ]
      user_temp_dir = Task.backtick %W[ sudo -u #{ENV["SUDO_USER"]} /usr/bin/mktemp -d -t macinbox_user_temp ]

      collector = Collector.new

      collector.add_temp_dir root_temp_dir
      collector.add_temp_dir user_temp_dir

      collector.on_cleanup do
        if @options[:debug]
          temp_dir_args = collector.temp_dirs.reverse.map { |o| o.shellescape }.join(" \\\n")
          Logger.error "WARNING: Temporary files were not removed. Run this command to remove them:"
          Logger.error "sudo rm -rf #{temp_dir_args}"
        else
          collector.remove_temp_dirs
        end
        STDERR.print TTY::CURSOR_NORMAL
      end

      ["TERM", "INT", "EXIT"].each do |signal|
        trap signal do
          trap signal, "SYSTEM_DEFAULT" unless signal == "EXIT"
          Process.waitall
          Logger.reset_depth
          if @success
            Logger.info "Cleaning up..."
          else
            STDERR.puts
            Logger.error "Cleaning up..."
          end
          collector.cleanup!
          Process.kill(signal, Process.pid) unless signal == "EXIT"
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

        Logger.info "Installing box..." do
          Actions::InstallBox.new(@options).run
        end

      end

      @success = true

    end

    def check_for_sudo_root
      if Process.uid != 0 or ENV["SUDO_USER"].nil?
        raise Macinbox::Error.new("script must be run as root with sudo")
      end
    end

  end
end
