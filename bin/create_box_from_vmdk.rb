#!/usr/bin/env ruby

require 'fileutils'
require 'shellwords'
require 'rubygems/package'

class Main

  def run
    trap_signals
    check_for_root
    find_vmware_fusion_app
    read_parameters
    create_temp_dir
    create_box
    package_box
    move_box
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

    @input_vmdk = ARGV[0]
    bail "Input VMDK not specified." if @input_vmdk.empty?
    bail "Input VMDK not found." unless File.exist? @input_vmdk

    @output_path = ARGV[1]
    bail "No output path specified." if @output_path.empty?

    @box_name    = ENV["MACINBOX_BOX_NAME"]    || "macinbox"
    @cpu_count   = ENV["MACINBOX_CPU_COUNT"]   || "2"
    @memory_size = ENV["MACINBOX_MEMORY_SIZE"] || "2048"
    @gui         = ENV["MACINBOX_GUI"]         || "true"
    @fullscreen  = ENV["MACINBOX_FULLSCREEN"]  || "true"
    @hidpi       = ENV["MACINBOX_HIDPI"]       || "true"
  end

  def create_temp_dir
    @temp_dir = %x( /usr/bin/mktemp -d -t create_box_from_vmdk ).chomp
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

  def progress_bar(activity, percent_done)
    @spinner ||= Enumerator.new { |e| loop { e.yield '|'; e.yield '/'; e.yield '-'; e.yield '\\' } }
    columns = STDOUT.winsize[1] - 8
    header = activity + ": " + percent_done.round(0).to_s + "% done "
    bar = ""
    if percent_done.round(0).to_i < 100
      bar_available_size = columns - header.size - 2
      bar_size = (percent_done * bar_available_size / 100.0).to_i
      bar_remainder = bar_available_size - bar_size
      bar_full = "#" * bar_size
      bar_empty = @spinner.next + " " * (bar_remainder-1) rescue ""
      bar = "[" + bar_full + bar_empty + "]"
    end
    header + bar
  end

  def write_file_to_io_with_progress(source, destination)
    eof = false
    bytes_written = 0
    total_size = File.size(source)
    last_percent_done = -1
    activity = "    - " + File.basename(source)
    header = "\r" + %x( tput el )
    black, green = [%x(tput setaf 0), %x(tput setaf 2)]
    STDERR.print %x( tput civis ) + header
    File.open(source) do |file|
      until eof
        begin
          bytes_written += destination.write(file.readpartial(1024*1024))
          percent_done = ((bytes_written.to_f / total_size.to_f) * 100).round(1)
          last_percent_done = percent_done
          STDERR.print header + green + progress_bar(activity, percent_done) + black
        rescue EOFError
          eof = true
        end
      end
    end
    STDERR.puts %x( tput cnorm )
  end

  def package_box
    Logger.info "Packaging the box..."

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
              write_file_to_io_with_progress(source, io)
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

  def cleanup(signal)
    ["EXIT", "INT", "TERM"].each { |signal| Signal.trap(signal, "SYSTEM_DEFAULT") }
    STDERR.print %x( tput cnorm )
    if @temp_dir and File.exist? @temp_dir
      Logger.info "Cleaning up..."
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
