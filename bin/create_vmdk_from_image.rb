#!/usr/bin/env ruby

require 'fileutils'
require 'shellwords'

class Main

  def run
    trap_signals
    check_for_root
    find_vmware_fusion_app
    read_parameters
    create_temp_dir
    mount_image
    convert_image
    move_vmdk
  end

  def trap_signals
    ["EXIT", "INT", "TERM"].each { |signal| Signal.trap(signal) { cleanup(signal) } }
  end

  def check_for_root
    if Process.uid != 0 || ENV["SUDO_USER"].nil?
    	bail "Script must be run as root with sudo."
    end
  end

  def find_vmware_fusion_app
    @vmware_fusion_app = ENV["VMWARE_FUSION_APP"] || "/Applications/VMware Fusion.app"
    bail "VMware Fusion not found." unless File.exist? @vmware_fusion_app
  end

  def read_parameters
    bail "Wrong number of arguments (found #{ARGV.size}, expected 2)." unless ARGV.size == 2

    @input_image = ARGV[0]
    bail "Input image not specified." if @input_image.empty?
    bail "Input image not found." unless File.exist? @input_image

    @output_path = ARGV[1]
    bail "No output path specified." if @output_path.empty?
  end

  def create_temp_dir
    @temp_dir = %x( /usr/bin/mktemp -d -t create_vmdk_from_image ).chomp
  end

  def mount_image
    Logger.info "Mounting the image..."

    @mountpoint = "#{@temp_dir}/image_mountpoint"

    FileUtils.mkdir @mountpoint

    @device = %x(
    	hdiutil attach #{@input_image.shellescape} -mountpoint #{@mountpoint.shellescape} -nobrowse -owners on |
    	grep _partition_scheme |
    	cut -f1 |
    	tr -d '[:space:]'
    ).chomp

    bail "Failed to mount the image." unless File.exist? @device
  end

  def run_command(cmd)
    system(*cmd) or bail "#{File.basename(cmd.slice(0))} failed with non-zero exit code: #{$?}"
  end

  def convert_image
    Logger.info "Converting the image to VMDK format..."

    rawdiskCreator = "#{@vmware_fusion_app}/Contents/Library/vmware-rawdiskCreator"
    vdiskmanager = "#{@vmware_fusion_app}/Contents/Library/vmware-vdiskmanager"

    Dir.chdir(@temp_dir) do
      run_command %W[ #{rawdiskCreator} create  #{@device} fullDevice rawdisk lsilogic ]
      run_command %W[ #{vdiskmanager} -t 0 -r rawdisk.vmdk macinbox.vmdk ]
    end
  end

  def move_vmdk
    Logger.info "Moving the VMDK to the destination..."

    FileUtils.chown ENV["SUDO_USER"], nil, "#{@temp_dir}/macinbox.vmdk"
    FileUtils.mv "#{@temp_dir}/macinbox.vmdk", @output_path
  end

  def cleanup(signal)
    ["EXIT", "INT", "TERM"].each { |signal| Signal.trap(signal, "SYSTEM_DEFAULT") }
    print %x( tput cnorm )
    if @temp_dir and File.exist? @temp_dir
      Logger.info "Cleaning up..."
      %x( hdiutil detach -quiet -force #{@mountpoint.shellescape} > /dev/null 2>&1 ) if @mountpoint
      %x( diskutil eject #{@device.shellescape} > /dev/null 2>&1 ) if @device
      FileUtils.rm_rf @temp_dir
    end
    Process.kill(signal, Process.pid) unless signal == "EXIT"
  end

  def bail(msg)
  	Logger.error msg
  	exit 1
  end

  def self.run!
    self.new.run
    exit 0
  end

end

class Logger
  @@text_color = {
    :black => STDIN.isatty ? %x(tput setaf 0) : "",
    :red => STDIN.isatty ? %x(tput setaf 1) : "",
    :green => STDIN.isatty ? %x(tput setaf 2) : "",
  }
  def self.info(msg)
    STDERR.puts @@text_color[:green] + "  + " + msg + @@text_color[:black]
  end
  def self.error(msg)
    STDERR.puts @@text_color[:red] + "  + " + msg + @@text_color[:black]
  end
end

Main.run!
