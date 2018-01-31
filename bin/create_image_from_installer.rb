#!/usr/bin/env ruby

require 'fileutils'
require 'shellwords'
require 'io/console'

class Main

  def run
    trap_signals
    check_for_root
    find_vmware_fusion_app
    read_parameters
    create_temp_dir
    check_macos_versions
    create_scratch_image
    install_macos
    install_vmware_tools
    set_spc_kextpolicy
    automate_user_account_creation
    automate_vagrant_ssh_key_installation
    enable_passwordless_sudo
    enable_sshd
    enable_hidpi
    save_image
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

    @installer_app = ARGV[0]
    bail "Installer app not specified." if @installer_app.empty?
    bail "Installer app not found." unless File.exist? @installer_app

    @output_path = ARGV[1]
    bail "No output path specified." if @output_path.empty?

    @disk_size       = ENV["MACINBOX_DISK_SIZE"]       || "64"
    @short_name      = ENV["MACINBOX_SHORT_NAME"]      || "vagrant"
    @full_name       = ENV["MACINBOX_FULL_NAME"]       || @short_name
    @password        = ENV["MACINBOX_PASSWORD"]        || @short_name
    @auto_login      = ENV["MACINBOX_AUTO_LOGIN"]      || "true"
    @skip_mini_buddy = ENV["MACINBOX_SKIP_MINI_BUDDY"] || "true"
    @hidpi           = ENV["MACINBOX_HIDPI"]           || "true"

    @debug = !ENV["MACINBOX_DEBUG"].nil?
  end

  def create_temp_dir
    @temp_dir = %x( /usr/bin/mktemp -d -t create_image_from_installer ).chomp
  end

  def check_macos_versions
    Logger.info "Checking macOS versions..."

    @install_info_plist = "#{@installer_app}/Contents/SharedSupport/InstallInfo.plist"
  	bail "InstallInfo.plist not found in installer app bundle." unless File.exist? @install_info_plist

    installer_os_version = IO.popen(%W[ /usr/libexec/PlistBuddy -c #{'Print :System\ Image\ Info:version'} #{@install_info_plist} ]).read.chomp
    installer_os_version_components = installer_os_version.split(".") rescue [0, 0, 0]
    installer_os_version_major = installer_os_version_components[0]
    installer_os_version_minor = installer_os_version_components[1]
    installer_os_version_patch = installer_os_version_components[2]
    Logger.info "Installer macOS version detected: #{installer_os_version}" if @debug

    host_os_version = %x( sw_vers -productVersion ).chomp
    host_os_version_components = host_os_version.split(".") rescue [0, 0, 0]
    host_os_version_major = host_os_version_components[0]
    host_os_version_minor = host_os_version_components[1]
    host_os_version_patch = host_os_version_components[2]
    Logger.info "Host macOS version detected: #{host_os_version}" if @debug

    if installer_os_version_major != host_os_version_major || installer_os_version_minor != host_os_version_minor
    	bail "Host OS version (#{host_os_version}) and installer OS version (#{installer_os_version}) do not match."
    end
  end

  def run_command(cmd)
    system(*cmd) or bail "#{cmd.slice(0)} failed with non-zero exit code: #{$?}"
  end

  def create_scratch_image
    Logger.info "Creating and attaching a new blank disk image..."
    @scratch_mountpoint = "#{@temp_dir}/scratch_mountpoint"
    @scratch_image = "#{@temp_dir}/scratch.sparseimage"
    FileUtils.mkdir @scratch_mountpoint
    quiet_flag = @debug ? [] : %W[ -quiet ]
    run_command %W[ hdiutil create -size #{@disk_size}g -type SPARSE -fs HFS+J -volname #{"Macintosh HD"} -uid 0 -gid 80 -mode 1775 #{@scratch_image} ] + quiet_flag
    run_command %W[ hdiutil attach #{@scratch_image} -mountpoint #{@scratch_mountpoint} -nobrowse -owners on ] + quiet_flag
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

  def install_macos
    Logger.info "Installing macOS..."
    activity = "    - installer"
    header = "\r" + %x( tput el )
    black, green = [%x(tput setaf 0), %x(tput setaf 2)]
    STDERR.print %x( tput civis ) + "\r" + %x( tput el ) + green + progress_bar(activity, 0) + black
    opts = @debug ? {} : { :err => [:child, :out] }
    IO.popen %W[ installer -verboseR -dumplog -pkg #{@install_info_plist} -target #{@scratch_mountpoint} ], opts do |pipe|
      pipe.each_line do |line|
        percent = /^installer:%(.*)$/.match(line)[1].to_f rescue nil
        STDERR.print header + green + progress_bar(activity, percent) + black if percent
      end
    end
    STDERR.puts %x( tput cnorm )
  end

  def install_vmware_tools
    Logger.info "Installing the VMware Tools..."

    @tools_mountpoint = "#{@temp_dir}/tools_mountpoint"
    FileUtils.mkdir @tools_mountpoint

    tools_image = "#{@vmware_fusion_app}/Contents/Library/isoimages/darwin.iso"
    tools_package = "#{@tools_mountpoint}/Install VMware Tools.app/Contents/Resources/VMware Tools.pkg"
    tools_package_dir = "#{@temp_dir}/tools_package"

    quiet_flag = @debug ? [] : %W[ -quiet ]

    run_command %W[ hdiutil attach #{tools_image} -mountpoint #{@tools_mountpoint} -nobrowse ] + quiet_flag
    run_command %W[ pkgutil --expand #{tools_package} #{tools_package_dir} ]
    run_command %W[ ditto -x -z #{tools_package_dir}/files.pkg/Payload #{@scratch_mountpoint} ]

    scratch_vmhgfs_filesystem_resources = "#{@scratch_mountpoint}/Library/Filesystems/vmhgfs.fs/Contents/Resources"

    FileUtils.mkdir_p scratch_vmhgfs_filesystem_resources
    FileUtils.ln_s "/Library/Application Support/VMware Tools/mount_vmhgfs", "#{scratch_vmhgfs_filesystem_resources}/"
  end

  def set_spc_kextpolicy
    Logger.info "Setting the KextPolicy to allow loading the VMware kernel extensions..."
    scratch_spc_kextpolicy = "#{@scratch_mountpoint}/private/var/db/SystemPolicyConfiguration/KextPolicy"
    IO.popen(["sqlite3", scratch_spc_kextpolicy], 'w') do |pipe|
      pipe.write <<~EOF
      	PRAGMA foreign_keys=OFF;
      	BEGIN TRANSACTION;
      	CREATE TABLE kext_load_history_v3 ( path TEXT PRIMARY KEY, team_id TEXT, bundle_id TEXT, boot_uuid TEXT, created_at TEXT, last_seen TEXT, flags INTEGER );
      	CREATE TABLE kext_policy ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, developer_name TEXT, flags INTEGER, PRIMARY KEY (team_id, bundle_id) );
      	INSERT INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.VMwareGfx',1,'VMware, Inc.',1);
      	INSERT INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmmemctl',1,'VMware, Inc.',1);
      	INSERT INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmhgfs',1,'VMware, Inc.',1);
      	CREATE TABLE kext_policy_mdm ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, payload_uuid TEXT, PRIMARY KEY (team_id, bundle_id) );
      	CREATE TABLE settings ( name TEXT, value TEXT, PRIMARY KEY (name) );
      	COMMIT;
      EOF
    end
  end

  def automate_user_account_creation
    Logger.info "Configuring the primary user account..."
    scratch_installer_configuration_file = "#{@scratch_mountpoint}/private/var/db/.InstallerConfiguration"
    File.write scratch_installer_configuration_file, <<~EOF
    	<?xml version="1.0" encoding="UTF-8"?>
    	<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    	<plist version="1.0">
    	<dict>
    		<key>Users</key>
    		<array>
    			<dict>
    				<key>admin</key>
    				<true/>
    				<key>autologin</key>
    				<#{@auto_login}/>
    				<key>fullName</key>
    				<string>#{@full_name}</string>
    				<key>shortName</key>
    				<string>#{@short_name}</string>
    				<key>password</key>
    				<string>#{@password}</string>
    				<key>skipMiniBuddy</key>
    				<#{@skip_mini_buddy}/>
    			</dict>
    		</array>
    	</dict>
    	</plist>
    EOF
  end

  def automate_vagrant_ssh_key_installation
    if @short_name == "vagrant"
    	Logger.info "Installing the default insecure vagrant ssh key..."
      scratch_rc_installer_cleanup = "#{@scratch_mountpoint}/private/etc/rc.installer_cleanup"
      scratch_rc_vagrant = "#{@scratch_mountpoint}/private/etc/rc.vagrant"
      File.write scratch_rc_installer_cleanup, <<~EOF
    		#!/bin/sh
    		rm /etc/rc.installer_cleanup
    		/etc/rc.vagrant &
    		exit 0
    	EOF
    	FileUtils.chmod 0755, scratch_rc_installer_cleanup
    	File.write scratch_rc_vagrant, <<~EOF
    		#!/bin/sh
    		rm /etc/rc.vagrant
    		while [ ! -e /Users/vagrant ]; do
    			sleep 1
    		done
    		if [ ! -e /Users/vagrant/.ssh ]; then
    			mkdir /Users/vagrant/.ssh
    			chmod 0700 /Users/vagrant/.ssh
    			chown `stat -f %u /Users/vagrant` /Users/vagrant/.ssh
    		fi
    		echo "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key" >> /Users/vagrant/.ssh/authorized_keys
    		chmod 0600 /Users/vagrant/.ssh/authorized_keys
    		chown `stat -f %u /Users/vagrant` /Users/vagrant/.ssh/authorized_keys
    	EOF
    	FileUtils.chmod 0755, scratch_rc_vagrant
    end
  end

  def enable_passwordless_sudo
    Logger.info "Enabling password-less sudo..."
    scratch_sudoers_d_user_rule_file = "#{@scratch_mountpoint}/private/etc/sudoers.d/#{@short_name}"
    File.write scratch_sudoers_d_user_rule_file, <<~EOF
    	#{@short_name} ALL=(ALL) NOPASSWD: ALL
    EOF
    FileUtils.chmod 0440, scratch_sudoers_d_user_rule_file
  end

  def enable_sshd
    Logger.info "Enabling sshd..."
    scratch_launchd_disabled_plist = "#{@scratch_mountpoint}/private/var/db/com.apple.xpc.launchd/disabled.plist"
    opts = @debug ? {} : { :out => File::NULL }
    run_command %W[ /usr/libexec/PlistBuddy -c #{'Add :com.openssh.sshd bool False'} #{scratch_launchd_disabled_plist} ] + [opts]
  end


  def enable_hidpi
    if @hidpi == "true"
    	Logger.info "Enabling HiDPI resolutions..."
      scratch_windowserver_preferences = "#{@scratch_mountpoint}/Library/Preferences/com.apple.windowserver.plist"
    	File.write scratch_windowserver_preferences, <<~EOF
    		<?xml version="1.0" encoding="UTF-8"?>
    		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    		<plist version="1.0">
    		<dict>
    			<key>DisplayResolutionEnabled</key>
    			<true/>
    		</dict>
    		</plist>
    	EOF
    end
  end

  def save_image
    Logger.info "Saving the image..."
    run_command %W[ hdiutil detach -quiet #{@scratch_mountpoint} ]
    FileUtils.mv @scratch_image, "#{@temp_dir}/macinbox.dmg"
    FileUtils.chown ENV["SUDO_USER"], nil, "#{@temp_dir}/macinbox.dmg"
    FileUtils.mv "#{@temp_dir}/macinbox.dmg", @output_path
  end

  def cleanup(signal)
    ["EXIT", "INT", "TERM"].each { |signal| Signal.trap(signal, "SYSTEM_DEFAULT") }
    STDERR.print %x( tput cnorm )
    if @temp_dir and File.exist? @temp_dir
      Logger.info "Cleaning up..."
      %x( hdiutil detach -quiet -force #{@scratch_mountpoint.shellescape} > /dev/null 2>&1 ) if @scratch_mountpoint
      %x( hdiutil detach -quiet -force #{@tools_mountpoint.shellescape} > /dev/null 2>&1 ) if @tools_mountpoint
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
