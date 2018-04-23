require 'fileutils'
require 'shellwords'

require 'macinbox/error'
require 'macinbox/logger'
require 'macinbox/task'

module Macinbox

  module Actions

    class CreateHDDFromImage

      def initialize(opts)
        @input_image       = opts[:image_path]     or raise ArgumentError.new(":image_path not specified")
        @output_path       = opts[:hdd_path]       or raise ArgumentError.new(":hdd_path not specified")
        @parallels_app     = opts[:parallels_path] or raise ArgumentError.new(":parallels_path not specified")

        @collector         = opts[:collector]      or raise ArgumentError.new(":collector not specified")
        @debug             = opts[:debug]

        raise Macinbox::Error.new("input image not found")       unless File.exist? @input_image
        raise Macinbox::Error.new("Parallels Desktop not found") unless File.exist? @parallels_app
      end

      def run
        @temp_dir = Task.backtick %W[ /usr/bin/mktemp -d -t create_hdd_from_image ]
        @collector.add_temp_dir @temp_dir

        Logger.info "Attaching the image..." do

          @collector.on_cleanup do
            %x( diskutil eject #{@device.shellescape} > /dev/null 2>&1 ) if @device
          end

          @device = %x(
            hdiutil attach #{@input_image.shellescape} -nomount |
            grep _partition_scheme |
            cut -f1 |
            tr -d [:space:]
          )

          raise Macinbox::Error.new("failed to attach the image") unless File.exist? @device
        end

        Logger.info "Converting the image to HDD format..." do

          disk_info = Task.backtick %W[ fdisk #{@device} ]

          geometry_re = /geometry: (\d+)\/(\d+)\/(\d+) \[(\d+) sectors\]/

          match = geometry_re.match(disk_info)

          raise Macinbox::Error.new("failed to determine disk geometry") if match.nil? || match.captures.length != 4

          device_sectors = match.captures[3]

          device_cylinders = match.captures[0]
          device_heads_per_track = match.captures[1]
          device_sectors_per_track = match.captures[2]

          bios_cylinders = 1024
          bios_heads_per_track = device_heads_per_track
          bios_sectors_per_track = device_sectors_per_track

          File.write "#{@temp_dir}/macinbox.vmdk", <<~EOF
            # Disk DescriptorFile
            version=1
            encoding="UTF-8"
            CID=fffffffe
            parentCID=ffffffff
            isNativeSnapshot="no"
            createType="monolithicFlat"

            # Extent description
            RW #{device_sectors} FLAT "#{@device}" 0

            # The Disk Data Base
            #DDB

            ddb.adapterType = "lsilogic"
            ddb.deletable = "true"
            ddb.geometry.biosCylinders = "#{bios_cylinders}"
            ddb.geometry.biosHeads = "#{bios_heads_per_track}"
            ddb.geometry.biosSectors = "#{bios_sectors_per_track}"
            ddb.geometry.cylinders = "#{device_cylinders}"
            ddb.geometry.heads = "#{device_heads_per_track}"
            ddb.geometry.sectors = "#{device_sectors_per_track}"
            ddb.longContentID = "9fa218b506cfe68615c39994fffffffe"
            ddb.uuid = "60 00 C2 99 91 76 dd 77-6e 0d 84 8b b0 24 6e 00"
            ddb.virtualHWVersion = "14"
          EOF

          prl_convert = "#{@parallels_app}/Contents/MacOS/prl_convert"
          task_opts = @debug ? {} : { :out => File::NULL }
          Task.run %W[ #{prl_convert} #{@temp_dir}/macinbox.vmdk --allow-no-os --dst=#{@temp_dir} ] + [task_opts]

        end

        Logger.info "Moving the HDD to the destination..." do
          FileUtils.chown_R ENV["SUDO_USER"], nil, "#{@temp_dir}/macinbox.hdd"
          FileUtils.mv "#{@temp_dir}/macinbox.hdd", @output_path
        end

        Task.run %W[ diskutil eject #{@device.shellescape} ]
        @device = nil

      end

    end

  end

end
