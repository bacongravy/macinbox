require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  class VirtualDisk

    def initialize(image)
      @image = image
      @quiet_flag = $verbose ? [] : %W[ -quiet ]
      @task_opts = $verbose ? [] : [{ :out => File::NULL }]
    end

    def device
      @disk_device
    end

    def set_devices(devices)
      @disk_device = devices[/([^ \n]*)([ \t])+\w*_partition_scheme/, 1]
      @efi_device = devices[/([^ \n]*)([ \t])+EFI/, 1]
      @volume_device = devices[/([^ \n]*)([ \t])+(Apple_HFS|41504653-0000-11AA-AA11-0030654)/, 1]
      raise Macinbox::Error.new("failed to attach the image") unless File.exist? @disk_device
    end

    def unset_devices
      @disk_device = nil
      @efi_device = nil
      @volume_device = nil
    end

    def mountpoint
      disk_info = Task.backtick %W[ /usr/sbin/diskutil info #{@volume_device} ]
      disk_info[/Mount Point:\s+(.*)/, 1]
    end

    def create_from_folder(srcfolder)
      Task.run %W[ /usr/bin/hdiutil create -srcfolder #{srcfolder} #{@image} ] + @quiet_flag
    end

    def create(disk_size, fstype)
      Task.run %W[ /usr/bin/hdiutil create -size #{disk_size}g -type SPARSE -fs #{fstype} -volname #{"Macintosh HD"} -uid 0 -gid 80 -mode 1775 #{@image} ] + @quiet_flag
    end

    def convert(format: 'UDZO', outfile:)
      Task.run %W[ /usr/bin/hdiutil convert -format #{format} -o #{outfile} #{@image} ] + @quiet_flag
    end

    def attach
      set_devices(Task.backtick %W[ /usr/bin/hdiutil attach #{@image} -nomount ])
    end

    def mount(at: nil, owners: false)
      mount_option = at ? %W[ -mountpoint #{at} ] : []
      owners_option = owners ? %W[ -owners on ] : []
      Task.run %W[ /usr/bin/hdiutil attach #{@volume_device} -nobrowse ] + mount_option + owners_option + @quiet_flag
    end

    def mount_efi(at:)
      Task.run %W[ /usr/sbin/diskutil mount -mountPoint #{at} #{@efi_device} ] + @task_opts
    end

    def unmount_efi
      Task.run %W[ /usr/sbin/diskutil unmount #{@efi_device} ] + @task_opts
    end

    def eject
      max_attempts = 5
      for attempt in 1..max_attempts
        begin
          quiet = $verbose ? [] : %W[ quiet ]
          Task.run %W[ /usr/sbin/diskutil ] + quiet + %W[ eject #{@disk_device} ] + @task_opts
          unset_devices
          break
        rescue Macinbox::Error => error
          raise if attempt == max_attempts
          Logger.info "Eject failed: #{error.message}. Sleeping and retrying..." if $verbose
          sleep 15
        end
      end
    end

    def detach!
      return unless @disk_device
      %x( /usr/bin/hdiutil detach -quiet -force #{@disk_device.shellescape} > /dev/null 2>&1 )
      unset_devices
    end

  end

end
