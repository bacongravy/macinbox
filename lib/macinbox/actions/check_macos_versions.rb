module Macinbox

  module Actions

    class CheckMacosVersions

      def initialize(opts)
        @installer_app     = opts[:installer_path]  or raise ArgumentError.new(":installer_path not specified")

        @collector         = opts[:collector]       or raise ArgumentError.new(":collector not specified")
        @debug             = opts[:debug]

        raise Macinbox::Error.new("Installer app not found") unless File.exist? @installer_app
      end

      def run
        install_info_plist = "#{@installer_app}/Contents/SharedSupport/InstallInfo.plist"
        raise Macinbox::Error.new("InstallInfo.plist not found in installer app bundle") unless File.exist? install_info_plist

        installer_os_version = Task.backtick %W[ /usr/libexec/PlistBuddy -c #{'Print :System\ Image\ Info:version'} #{install_info_plist} ]
        installer_os_version_components = installer_os_version.split(".") rescue [0, 0, 0]
        installer_os_version_major = installer_os_version_components[0]
        installer_os_version_minor = installer_os_version_components[1]
        Logger.info "Installer macOS version detected: #{installer_os_version}" if @debug

        host_os_version = Task.backtick %W[ /usr/bin/sw_vers -productVersion ]
        host_os_version_components = host_os_version.split(".") rescue [0, 0, 0]
        host_os_version_major = host_os_version_components[0]
        host_os_version_minor = host_os_version_components[1]
        Logger.info "Host macOS version detected: #{host_os_version}" if @debug

        if installer_os_version_major != host_os_version_major || installer_os_version_minor != host_os_version_minor
          Logger.error "Warning: host OS version (#{host_os_version}) and installer OS version (#{installer_os_version}) do not match"
          # raise Macinbox::Error.new("host OS version (#{host_os_version}) and installer OS version (#{installer_os_version}) do not match")
        end

        installer_os_version
      end

    end

  end

end
