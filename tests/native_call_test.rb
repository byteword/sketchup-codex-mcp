# encoding: UTF-8
require 'minitest/autorun'
require_relative '../extension/su_pipe_probe/native_call'

class NativeCallTest < Minitest::Test
  def test_explicit_error_survives_a_zero_fiddle_cache
    callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_VOIDP]) do |address|
      Fiddle::Pointer.new(address)[0, 4] = [997].pack('V')
      Fiddle.last_error = 0
      0
    end
    native = Fiddle::Function.new(callback, [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    call = SUPipeProbe::NativeCall.new(native)
    result, error = call.call
    assert_equal 0, result
    assert_equal 997, error
  end

  def test_each_call_has_its_own_error_output
    next_error = 996
    callback = lambda do |output|
      output[0, 4] = [next_error].pack('V')
      next_error = 109
      0
    end
    call = SUPipeProbe::NativeCall.new(callback)
    first = call.call
    second = call.call
    assert_equal [0, 996], first
    assert_equal [0, 109], second
  end
end
