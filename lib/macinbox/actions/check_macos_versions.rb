require "macinbox/error"
require "macinbox/os_version"

module Macinbox

  module Actions

    class CheckMacosVersions

      def initialize(opts)
        @installer_app     = opts[:installer_path]  or raise ArgumentError.new(":installer_path not specified")

        @collector         = opts[:collector]       or raise ArgumentError.new(":collector not specified")

        raise Macinbox::Error.new("Installer app not found") unless File.exist? @installer_app
      end

      def run
        install_info_plist = "#{@installer_app}/Contents/SharedSupport/InstallInfo.plist"
        raise Macinbox::Error.new("InstallInfo.plist not found in installer app bundle") unless File.exist? install_info_plist

        installer_os_version = Macinbox::OSVersion.new(Task.backtick %W[ /usr/libexec/PlistBuddy -c #{'Print :System\ Image\ Info:version'} #{install_info_plist} ])
        Logger.info "Installer macOS version detected: #{installer_os_version}" if $verbose

        host_os_version = Macinbox::OSVersion.new(Task.backtick %W[ /usr/bin/sw_vers -productVersion ])
        Logger.info "Host macOS version detected: #{host_os_version}" if $verbose

        unless installer_os_version.is_sierra_or_later?
          raise Macinbox::Error.new("Installer macOS version is not supported: #{installer_os_version}")
        end

        if (host_os_version.is_catalina_or_later? && installer_os_version.is_mojave_or_earlier?) ||
           (host_os_version.is_mojave_or_earlier? && installer_os_version.is_catalina_or_later?)
          raise Macinbox::Error.new("macOS #{host_os_version} cannot install macOS #{installer_os_version}")
        end

        if installer_os_version.major != host_os_version.major || installer_os_version.minor != host_os_version.minor
          Logger.error "Warning: host OS version (#{host_os_version}) and installer OS version (#{installer_os_version}) do not match"
        end

        installer_os_version
      end

    end

  end

end
