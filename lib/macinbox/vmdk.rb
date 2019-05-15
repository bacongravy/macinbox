require 'macinbox/error'
require 'macinbox/task'

module Macinbox

  class VMDK

    def self.create_raw_vmdk(device, output)

      disk_info = Task.backtick %W[ /usr/sbin/fdisk #{device} ]

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

      File.write output, <<~EOF
        # Disk DescriptorFile
        version=1
        encoding="UTF-8"
        CID=fffffffe
        parentCID=ffffffff
        isNativeSnapshot="no"
        createType="monolithicFlat"

        # Extent description
        RW #{device_sectors} FLAT "#{device}" 0

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

    end

  end

end
