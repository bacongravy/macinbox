module Macinbox
  class Collector
    def initialize
      @blocks = []
    end
    def on_cleanup(&block)
      @blocks << block
    end
    def cleanup!
      @blocks.reverse.each do |block|
        block.call
      end
      @blocks = []
    end
  end
end
