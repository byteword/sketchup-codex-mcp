# encoding: UTF-8
# Deterministic simulated Win32 completion states; not a Windows integration test.
require 'minitest/autorun'
require 'fiddle'

module SUPipeProbe
  module Win32
    class << self
      attr_accessor :start_error, :completion_error, :error, :closed, :operations
      def reset
        @start_error = 997
        @completion_error = 996
        @closed = []
        @operations = []
      end
      def memory(size)
        p = Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE)
        p[0, size] = "\0" * size
        p
      end
      def CreateEventW(*args); 81; end
      def CreateFileW(*args); 90; end
      def ReadFile(handle, buffer, length, count, overlapped)
        @error = @start_error
        @operations << overlapped
        @error == 0 ? 1 : 0
      end
      alias_method :WriteFile, :ReadFile
      def GetOverlappedResult(handle, operation, count, wait)
        raise 'Blocking wait is forbidden' unless wait == 0
        @error = @completion_error
        count[0, 4] = [3].pack('V')
        @error == 0 ? 1 : 0
      end
      def CloseHandle(handle); @closed << handle; 1; end
      def CancelIoEx(*args); 1; end
    end
  end
end
require_relative '../extension/su_pipe_probe/win_pipe'

class TransportTest < Minitest::Test
  def setup
    SUPipeProbe::Win32.reset
  end

  def test_pending_read_is_not_a_disconnect
    operation = SUPipeProbe::NativeOperation.new(90, :read)
    assert operation.pending?
    assert_nil operation.result
    assert operation.pending?
    assert_empty SUPipeProbe::Win32.closed
    assert_raises(SUPipeProbe::PipeError) { operation.dispose }
    SUPipeProbe::Win32.completion_error = 0
    assert_equal 3, operation.result
    refute operation.pending?
    operation.dispose
    assert_equal [81], SUPipeProbe::Win32.closed
  end

  def test_pending_write_then_completion
    operation = SUPipeProbe::NativeOperation.new(90, :write, 'abc')
    assert_nil operation.result
    SUPipeProbe::Win32.completion_error = 0
    assert_equal 3, operation.result
    operation.dispose
  end

  def test_real_read_failure_is_not_silently_treated_as_pending
    SUPipeProbe::Win32.start_error = 109
    error = assert_raises(SUPipeProbe::PipeError) { SUPipeProbe::NativeOperation.new(90, :read) }
    assert_match(/ReadFile: 109/, error.message)
    assert_equal [81], SUPipeProbe::Win32.closed
  end

  def test_cancel_keeps_buffers_and_handle_until_terminal_completion
    client = SUPipeProbe::PipeClient.new
    client.connect
    assert_equal [], client.poll
    client.close
    assert_equal :closing, client.state
    assert_empty SUPipeProbe::Win32.closed
    client.poll
    assert_equal :closing, client.state
    SUPipeProbe::Win32.completion_error = 995 # ERROR_OPERATION_ABORTED
    client.poll
    assert_equal :closed, client.state
    assert_equal [81, 90], SUPipeProbe::Win32.closed
  end

  def test_completed_broken_pipe_can_be_disposed
    operation = SUPipeProbe::NativeOperation.new(90, :read)
    SUPipeProbe::Win32.completion_error = 109
    assert_raises(SUPipeProbe::PipeError) { operation.result }
    refute operation.pending?
    operation.dispose
    assert_equal [81], SUPipeProbe::Win32.closed
  end
end
