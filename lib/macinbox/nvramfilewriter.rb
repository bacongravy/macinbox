require 'zlib'

module Macinbox
  class NVRAMFileWriter

    def self.write_binary_file(name, uuid, data, outputfile)
      # Writes an NVRAM binary file
      # following https://github.com/myspaghetti/macos-virtualbox/blob/master/macos-guest-virtualbox.sh
      #
      # The format is
      #
      #  - length of encoded name: 4 byte integer (little endian)
      #  - length of data: 4 byte integer (little endian)
      #  - encoded name: name in ASCII, interleaved with null bytes, terminated with two null bytes (Example: "foo" becomes "66 00 6f 00 6f 00 00 00")
      #  - encoded UUID, with the first three segments inverted (example: "7C436110-AB2A-4BBB-A880-FE41995C9F82" becomes "10 61 43 7c 2a ab bb 4b a8 80 fe 41 99 5c 9f 82")
      #  - attributes: 4 bytes, here always "07 00 00 00"
      #  - checksum: CRC32 of the data above: 4 byte integer (little endian)
      nameAscii = name.bytes.to_a
      nulbytes = Array.new(nameAscii.length, 0x00)
      nameEncoded = nameAscii.zip(nulbytes).flatten << 0x00 << 0x00

      nameLength = encode_int32_le nameEncoded.length
      dataLength = encode_int32_le data.length

      uuidSegments = uuid.split "-"
      3.times { |i| uuidSegments[i] = reverse_hex_string(uuidSegments[i]) }
      uuidEncoded =  uuidSegments.join.scan(/../).map(&:hex)

      attributes = [7, 0, 0, 0]

      nvramDataString = int_array_to_string [nameLength, dataLength, nameEncoded, uuidEncoded, attributes, data].flatten
      checksum = int_array_to_string encode_int32_le(Zlib::crc32(nvramDataString))
      nvramDataString = nvramDataString + checksum

      File.open(outputfile, 'wb') { |file| file.write(nvramDataString) }
    end

    def self.reverse_hex_string(str)
      str.chars.each_slice(2).to_a.reverse.flatten
    end

    def self.encode_int32_le(n)
      [n].pack('l<').bytes.to_a
    end

    def self.int_array_to_string(is)
      is.pack('c*')
    end
  end
end
