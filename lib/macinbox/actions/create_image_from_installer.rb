require 'fileutils'
require 'shellwords'
require 'io/console'

require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'
require 'macinbox/virtual_disk'

module Macinbox

  module Actions

    class CreateImageFromInstaller

      def initialize(opts)
        @installer_app     = opts[:installer_path]  or raise ArgumentError.new(":installer_path not specified")
        @output_path       = opts[:image_path]      or raise ArgumentError.new(":image_path not specified")
        @vmware_fusion_app = opts[:vmware_path]
        @parallels_app     = opts[:parallels_path]
        @user_script       = opts[:user_script]

        @disk_size         = opts[:disk_size]       or raise ArgumentError.new(":disk_size not specified")
        @fstype            = opts[:fstype]          or raise ArgumentError.new(":fstype not specified")
        @short_name        = opts[:short_name]      or raise ArgumentError.new(":short_name not specified")
        @full_name         = opts[:full_name]       or raise ArgumentError.new(":full_name not specified")
        @password          = opts[:password]        or raise ArgumentError.new(":password not specified")

        @box_format        = opts[:box_format]
        @auto_login        = opts[:auto_login]
        @skip_mini_buddy   = opts[:skip_mini_buddy]
        @hidpi             = opts[:hidpi]

        @collector         = opts[:collector]       or raise ArgumentError.new(":collector not specified")

        raise Macinbox::Error.new("Installer app not found") unless File.exist? @installer_app

        raise ArgumentError.new(":vmware_path not specified") if @box_format == "vmware_desktop" && !opts[:vmware_path]
        raise ArgumentError.new(":parallels_path not specified") if @box_format == "parallels" && !opts[:parallels_path]
      end

      def run
        create_temp_dir
        if installer_is_on_root_filesystem
          create_wrapper_image
        end
        create_scratch_image
        install_macos
        create_rc_vagrant
        automate_user_account_creation
        automate_vagrant_group_creation
        automate_vagrant_ssh_key_installation
        enable_passwordless_sudo
        enable_sshd
        enable_hidpi
        run_user_script
        save_image
      end

      def create_temp_dir
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_image_from_installer ]
        @collector.add_temp_dir @temp_dir
      end

      def installer_is_on_root_filesystem
        root_device = Task.backtick %W[ /usr/bin/stat -f %d / ]
        installer_device = Task.backtick %W[ /usr/bin/stat -f %d #{@installer_app} ]
        root_device == installer_device
      end

      def create_wrapper_image
        Logger.info "Creating and attaching wrapper disk image..." do
          @wrapper_image = "#{@temp_dir}/wrapper.dmg"
          @wrapper_disk = VirtualDisk.new(@wrapper_image)
          @collector.on_cleanup { @wrapper_disk.detach! }
          @wrapper_disk.create_from_folder(@installer_app)
          @wrapper_disk.attach
          @wrapper_disk.mount
          @installer_app = "#{@wrapper_disk.mountpoint}/#{File.basename @installer_app}"
        end
      end

      def create_scratch_image
        Logger.info "Creating and attaching a new blank disk image..." do
          @scratch_image = "#{@temp_dir}/scratch.sparseimage"
          @scratch_disk = VirtualDisk.new(@scratch_image)
          @collector.on_cleanup { @scratch_disk.detach! }
          @scratch_mountpoint = "#{@temp_dir}/scratch_mountpoint"
          FileUtils.mkdir @scratch_mountpoint
          @scratch_disk.create(@disk_size, @fstype)
          @scratch_disk.attach
          @scratch_disk.mount(at: @scratch_mountpoint, owners: true)
        end
      end

      def install_macos
        Logger.info "Installing macOS..." do
          activity = Logger.prefix + "installer"
          install_info_plist = "#{@installer_app}/Contents/SharedSupport/InstallInfo.plist"
          Task.run %W[ /usr/bin/touch #{@scratch_mountpoint}/.macinbox ]
          cmd = %W[ /usr/sbin/installer -verboseR -dumplog -pkg #{install_info_plist} -target #{@scratch_mountpoint} ]
          opts = $verbose ? {} : { :err => [:child, :out] }
          Task.run_with_progress activity, cmd, opts do |line|
            /^installer:%(.*)$/.match(line)[1].to_f rescue nil
          end
          @wrapper_disk.detach! if @wrapper_disk
        end
      end

      def create_rc_vagrant
        first_boot_launch_daemon = "#{@scratch_mountpoint}/Library/LaunchDaemons/rc.vagrant.plist"
        File.write first_boot_launch_daemon, <<~EOF
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>Label</key>
            <string>rc.vagrant</string>
            <key>ProgramArguments</key>
            <array>
              <string>/etc/rc.vagrant</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
          </dict>
          </plist>
        EOF
        FileUtils.chmod 0755, first_boot_launch_daemon
        @scratch_rc_vagrant = "#{@scratch_mountpoint}/private/etc/rc.vagrant"
        File.write @scratch_rc_vagrant, <<~EOF
          #!/bin/sh
          rm -r /Library/LaunchDaemons/rc.vagrant.plist
          rm -f /etc/rc.vagrant
        EOF
        FileUtils.chmod 0755, @scratch_rc_vagrant
      end

      def automate_user_account_creation
        Logger.info "Configuring the primary user account..." do
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
                  <#{@auto_login ? true : false}/>
                  <key>fullName</key>
                  <string>#{@full_name}</string>
                  <key>shortName</key>
                  <string>#{@short_name}</string>
                  <key>password</key>
                  <string>#{@password}</string>
                  <key>skipMiniBuddy</key>
                  <#{@skip_mini_buddy ? true : false}/>
                </dict>
              </array>
            </dict>
            </plist>
          EOF
        end
      end

      def automate_vagrant_group_creation
        if @short_name == "vagrant"
          Logger.info "Configuring the 'vagrant' group..." do
            contents = <<~EOF
              until dscl . -read /Users/vagrant UniqueID; do
                sleep 1
              done
              dscl . -create /Groups/vagrant
              dscl . -create /Groups/vagrant gid 501
              dscl . -create /Groups/vagrant GroupMembers `dscl . -read /Users/vagrant GeneratedUID | cut -d ' ' -f 2`
              dscl . -create /Groups/vagrant GroupMembership vagrant
            EOF
            File.write @scratch_rc_vagrant, contents, mode: 'a'
          end
        end
      end

      def automate_vagrant_ssh_key_installation
        if @short_name == "vagrant"
          Logger.info "Installing the default insecure vagrant ssh key..." do
            contents = <<~EOF
              while [ ! -e /Users/vagrant ]; do
                sleep 1
              done
              while [ `stat -f %u /Users/vagrant` == 0 ]; do
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
            File.write @scratch_rc_vagrant, contents, mode: 'a'
          end
        end
      end

      def enable_passwordless_sudo
        Logger.info "Enabling password-less sudo..." do
          scratch_sudoers_d_user_rule_file = "#{@scratch_mountpoint}/private/etc/sudoers.d/#{@short_name}"
          File.write scratch_sudoers_d_user_rule_file, <<~EOF
            #{@short_name} ALL=(ALL) NOPASSWD: ALL
          EOF
          FileUtils.chmod 0440, scratch_sudoers_d_user_rule_file
        end
      end

      def enable_sshd
        Logger.info "Enabling sshd..." do
          scratch_launchd_disabled_plist = "#{@scratch_mountpoint}/private/var/db/com.apple.xpc.launchd/disabled.plist"
          opts = $verbose ? {} : { :out => File::NULL }
          Task.run %W[ /usr/libexec/PlistBuddy -c #{'Add :com.openssh.sshd bool False'} #{scratch_launchd_disabled_plist} ] + [opts]
        end
      end

      def enable_hidpi
        if @hidpi
          Logger.info "Enabling HiDPI resolutions..." do
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
      end

      def run_user_script
        if @user_script
          Logger.info "Running user script..." do
            Task.run %W[ #{@user_script} #{@scratch_mountpoint} ]
          end
        end
      end

      def save_image
        Logger.info "Saving the image..." do
          @scratch_disk.eject
          FileUtils.chown ENV["SUDO_USER"], nil, @scratch_image
          FileUtils.mv @scratch_image, @output_path
        end
      end

    end

  end

end
