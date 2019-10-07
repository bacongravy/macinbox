require 'macinbox/cli/options'

require 'pathname'
require 'fileutils'

require "macinbox/actions"
require "macinbox/collector"
require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/tty'
require 'macinbox/virtual_disk'

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

      collector = Collector.new(preserve_temp_dirs: $debug)

      collector.on_cleanup do
        STDERR.print TTY::Color::RESET
        STDERR.print TTY::Cursor::NORMAL
      end

      if @options[:installer_dmg]
        if !File.exists?(@options[:installer_dmg])
          raise Macinbox::Error.new("Installer disk image not found: #{@options[:installer_dmg]}")
        end
        Logger.info "Attaching installer disk image..."
        installer_disk = VirtualDisk.new(@options[:installer_dmg])
        collector.on_cleanup { installer_disk.detach! }
        installer_disk.attach
        installer_disk.mount
        @options[:installer_path] = Dir[installer_disk.mountpoint+'/*.app'].first
      end

      if not File.exists? @options[:installer_path]
        raise Macinbox::Error.new("Installer app not found: #{@options[:installer_path]}")
      end

      if not ["vmware_fusion", "vmware_desktop", "parallels", "virtualbox"].include? @options[:box_format]
        raise Macinbox::Error.new("Box format not supported: #{@options[:box_format]}")
      end

      if /^vmware_(fusion|desktop)$/ === @options[:box_format]
        unless File.exists?(@options[:vmware_path])
          raise Macinbox::Error.new("VMware Fusion app not found: #{@options[:vmware_path]}")
        end
        vmware_version = Task.backtick %W[ defaults read #{@options[:vmware_path]}/Contents/Info.plist CFBundleShortVersionString ]
        @options[:vmware_major_version] = vmware_version.split(".")[0].to_i rescue 10
      end

      if /^parallels$/ === @options[:box_format] && !File.exists?(@options[:parallels_path])
        raise Macinbox::Error.new("Parallels Desktop app not found: #{@options[:parallels_path]}")
      end

      if /^virtualbox$/ === @options[:box_format] && !File.exists?('/usr/local/bin/VBoxManage')
        raise Macinbox::Error.new("VBoxManage not found: /usr/local/bin/VBoxManage")
      end

      if @options[:use_qemu] && !File.exists?('/usr/local/bin/qemu-img')
        raise Macinbox::Error.new("QEMU not found: /usr/local/bin/qemu-img")
      end

      if /^vmware_(fusion|desktop)$/ === @options[:box_format] && !@options[:use_qemu] && @options[:vmware_major_version] >= 11
        fusion_is_not_running = false
        begin
          Task.run %W[ pgrep -q #{"^VMware Fusion$"} ]
        rescue
          fusion_is_not_running = true
        end
        if fusion_is_not_running || !File.exist?("/Library/PrivilegedHelperTools/com.vmware.DiskHelper")
          raise Macinbox::Error.new("VMware Fusion is not running and the workaround was not detected. See https://kb.vmware.com/s/article/65163 for more information, or try the --use-qemu option.")
        end
      end

      vagrant_home = ENV["VAGRANT_HOME"]

      if vagrant_home.nil? or vagrant_home.empty?
        vagrant_home = File.expand_path "~/.vagrant.d"
      end

      if !File.exist? vagrant_home
        raise Macinbox::Error.new("VAGRANT_HOME not found: #{vagrant_home}")
      end

      vagrant_boxes_dir = "#{vagrant_home}/boxes"

      if !File.exist? vagrant_boxes_dir
        Dir.mkdir vagrant_boxes_dir
      end

      root_temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t macinbox_root_temp ]
      user_temp_dir = Task.backtick %W[ /usr/bin/sudo -u #{ENV["SUDO_USER"]} /usr/bin/mktemp -d -t macinbox_user_temp ]

      collector.add_temp_dir root_temp_dir
      collector.add_temp_dir user_temp_dir

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

      @options[:image_path] = "macinbox.sparseimage"
      @options[:vmdk_path] = "macinbox.vmdk"
      @options[:hdd_path] = "macinbox.hdd"
      @options[:vdi_path] = "macinbox.vdi"
      @options[:box_path] = "macinbox.box"
      @options[:boxes_dir] = vagrant_boxes_dir
      @options[:collector] = collector

      Dir.chdir(root_temp_dir) do

        Logger.info "Checking macOS versions..." do
          @options[:macos_version] = Actions::CheckMacosVersions.new(@options).run
        end

        Logger.info "Creating image from installer..." do
          Actions::CreateImageFromInstaller.new(@options).run
        end

        case @options[:box_format]

        when /^vmware_(fusion|desktop)$/

          Logger.info "Creating VMDK from image..." do
            Actions::CreateVMDKFromImage.new(@options).run
          end

          Logger.info "Creating box from VMDK..." do
            Actions::CreateBoxFromVMDK.new(@options).run
          end

        when /^parallels$/

          Logger.info "Creating HDD from image..." do
            Actions::CreateHDDFromImage.new(@options).run
          end

          Logger.info "Creating box from HDD..." do
            Actions::CreateBoxFromHDD.new(@options).run
          end

        when /^virtualbox$/

          Logger.info "Creating VDI from image..." do
            Actions::CreateVDIFromImage.new(@options).run
          end

          Logger.info "Creating box from VDI..." do
            Actions::CreateBoxFromVDI.new(@options).run
          end

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
