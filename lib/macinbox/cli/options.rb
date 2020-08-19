require 'optparse'

require 'macinbox/version'

module Macinbox

  class CLI

    DEFAULT_OPTION_VALUES = {
      :box_format      => "vmware_desktop",
      :box_name        => "macinbox",
      :disk_size       => 64,
      :fstype          => "APFS",
      :memory_size     => 2048,
      :cpu_count       => 2,
      :short_name      => "vagrant",
      :installer_path  => "/Applications/Install macOS Catalina.app",
      :vmware_path     => "/Applications/VMware Fusion.app",
      :parallels_path  => "/Applications/Parallels Desktop.app",
      :vmware_tools    => true,
      :auto_login      => true,
      :skip_mini_buddy => true,
      :hidpi           => true,
      :fullscreen      => true,
      :gui             => true,
      :sip_enabled     => true,
      :use_qemu        => false,
      :verbose         => false,
      :debug           => false,
    }

    def parse_options(argv)

      @options = DEFAULT_OPTION_VALUES

      @option_parser = OptionParser.new do |o|

        o.separator ''
        o.on(      '--box-format FORMAT',  'Format of the box (default: vmware_desktop)')  { |v| @options[:box_format] = v }
        o.separator ''
        o.on('-n', '--name NAME',          'Name of the box         (default: macinbox)') { |v| @options[:box_name] = v }
        o.on('-d', '--disk SIZE',          'Size (GB) of the disk   (default: 64)')       { |v| @options[:disk_size] = v }
        o.on('-t', '--fstype TYPE',        'Type of FS on the disk  (default: APFS)')     { |v| @options[:fstype] = v }
        o.on('-m', '--memory SIZE',        'Size (MB) of the memory (default: 2048)')     { |v| @options[:memory_size] = v }
        o.on('-c', '--cpu COUNT',          'Number of virtual cores (default: 2)')        { |v| @options[:cpu_count] = v }
        o.on('-s', '--short NAME',         'Short name of the user  (default: vagrant)')  { |v| @options[:short_name] = v }
        o.on('-f', '--full NAME',          'Full name of the user   (default: Vagrant)')  { |v| @options[:full_name] = v }
        o.on('-p', '--password PASSWORD',  'Password of the user    (default: vagrant)')  { |v| @options[:password] = v }
        o.separator ''
        o.on(      '--installer PATH',     'Path to the macOS installer app')             { |v| @options[:installer_path] = File.absolute_path(v) }
        o.on(      '--installer-dmg PATH', 'Path to a macOS installer app disk image')    { |v| @options[:installer_dmg] = File.absolute_path(v) }
        o.on(      '--vmware PATH',        'Path to the VMware Fusion app')               { |v| @options[:vmware_path] = File.absolute_path(v) }
        o.on(      '--parallels PATH',     'Path to the Parallels Desktop app')           { |v| @options[:parallels_path] = File.absolute_path(v) }
        o.on(      '--user-script PATH',   'Path to user script')                         { |v| @options[:user_script] = File.absolute_path(v) }
        o.separator ''
        o.on(      '--no-auto-login',      'Disable auto login')                          { |v| @options[:auto_login] = v }
        o.on(      '--no-skip-mini-buddy', 'Show the mini buddy on first login')          { |v| @options[:skip_mini_buddy] = v }
        o.on(      '--no-hidpi',           'Disable HiDPI resolutions')                   { |v| @options[:hidpi] = v }
        o.on(      '--no-fullscreen',      'Display the virtual machine GUI in a window') { |v| @options[:fullsceen] = v }
        o.on(      '--no-gui',             'Disable the GUI')                             { |v| @options[:gui] = v }
        o.separator ''
        o.on(      '--no-sip',             'Disable System Integrity Protection (virtualbox only)') { |v| @options[:sip_enabled] = v }
        o.separator ''
        o.on(      '--use-qemu',           'Use qemu-img (vmware_desktop only)')          { |v| @options[:use_qemu] = v }
        o.separator ''
        o.on(      '--verbose',            'Enable verbose mode')                         { |v| $verbose = v }
        o.on(      '--debug',              'Enable debug mode')                           { |v| $debug = $verbose = v }
        o.separator ''
        o.on('-v', '--version')                                                           { puts "macinbox #{Macinbox::VERSION}"; exit }
        o.on('-h', '--help')                                                              { puts o; exit }

        o.parse(argv)

      end

      @options[:full_name] ||= @options[:short_name].capitalize
      @options[:password]  ||= @options[:short_name]

    end
  end
end
