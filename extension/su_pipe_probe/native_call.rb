# encoding: UTF-8
require 'fiddle'

module SUPipeProbe
  # Explicit native out-parameter, independent of Fiddle's last-error cache.
  class NativeCall
    def initialize(function)
      @function = function
    end

    def call(*arguments)
      error = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
      error[0, 4] = [0].pack('V')
      result = @function.call(*(arguments + [error]))
      [result, error[0, 4].unpack('V')[0]]
    end
  end
end
