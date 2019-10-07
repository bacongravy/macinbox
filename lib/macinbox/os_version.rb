module Macinbox

  class OSVersion

    def initialize(version)
      @version = version
      @components = @version.split(".") rescue [0, 0]
    end

    def to_s
      @version
    end

    def major
      @components[0].to_i rescue 0
    end

    def minor
      @components[1].to_i rescue 0
    end

    def darwin_major
      minor + 4
    end

    def is_sierra?
      major == 10 && minor == 12
    end

    def is_high_sierra?
      major == 10 && minor == 13
    end

    def is_mojave?
      major == 10 && minor == 14
    end

    def is_catalina?
      major == 10 && minor == 15
    end

    def is_sierra_or_later?
      major == 10 && minor >= 12
    end

    def is_mojave_or_earlier?
      major == 10 && minor <= 14
    end

    def is_catalina_or_later?
      major == 10 && minor >= 15
    end

  end
  
end
