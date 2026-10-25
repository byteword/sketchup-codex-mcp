# encoding: UTF-8
# Ruby 2.5 / Windows x64. No SketchUp API calls in this transport.
require 'fiddle'
require 'json'
require_relative 'win32' unless defined?(SUPipeProbe::Win32)

module SUPipeProbe
  class PipeError < StandardError; end

  # A separate OVERLAPPED + event + native buffer is kept alive for every I/O.
  # Cancellation is asynchronous: close() requests it; poll() reaps it later.
  class NativeOperation
    attr_reader :buffer, :overlapped, :count, :length, :started

    def initialize(handle, direction, payload = nil)
      @handle = handle
      @length = payload ? payload.bytesize : 8192
      @buffer = Win32.memory(@length)
      @buffer[0, @length] = payload if payload
      @overlapped = Win32.memory(32) # x64: ULONG_PTR x2, union 8, HANDLE 8
      @count = Win32.memory(4)
      @event = Win32.CreateEventW(0, 1, 0, 0)
      raise PipeError, "CreateEventW: #{Win32.error}" if @event.to_i == 0
      @overlapped[24, 8] = [@event.to_i].pack('Q<')
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @pending = false
      function = direction == :read ? :ReadFile : :WriteFile
      ok = Win32.send(function, handle, @buffer, @length, @count, @overlapped)
      error = Win32.error
      if ok == 0 && error != 997 # ERROR_IO_PENDING
        dispose
        raise PipeError, "#{function}: #{error}"
      end
      @pending = true
    end

    # nil means still pending; never wait on the SketchUp main thread.
    def result
      ok = Win32.GetOverlappedResult(@handle, @overlapped, @count, 0)
      error = Win32.error
      return nil if ok == 0 && error == 996 # ERROR_IO_INCOMPLETE
      @pending = false
      raise PipeError, "GetOverlappedResult: #{error}" if ok == 0
      @count[0, 4].unpack('V')[0]
    end

    def pending?
      @pending
    end

    def dispose
      raise PipeError, 'Attempted to free pending native I/O' if @pending
      Win32.CloseHandle(@event) if @event && @event.to_i != 0
      @event = nil
    end
  end

  class PipeClient
    NAME = (ENV['SUPIPE_TEST'] == '1' ? '\\\\.\\pipe\\SketchUpCodexMcp.Test.Probe.v1' : '\\\\.\\pipe\\SketchUpCodexMcp.Probe.v1').freeze
    MAX_FRAME = 65_536
    MAX_QUEUE = 64

    attr_reader :state

    def initialize
      @state = :closed
      @queue = []
      @input = ''.b
    end

    def connect
      raise PipeError, 'Previous connection is still closing' unless @state == :closed
      path = (NAME.encode('UTF-16LE').b + "\0\0".b)
      # OVERLAPPED + SECURITY_SQOS_PRESENT / SECURITY_IDENTIFICATION.
      @handle = Win32.CreateFileW(path, -1_073_741_824, 0, 0, 3, 0x40110000, 0)
      # Desired access is GENERIC_READ | GENERIC_WRITE = 0xC0000000.
      if (@handle.to_i & 0xffffffffffffffff) == 0xffffffffffffffff
        error = Win32.error
        @handle = nil
        raise PipeError, "CreateFileW: #{error} (2=server absent; 5=access denied; 231=busy)"
      end
      @queue.clear
      @input.clear
      @state = :connected
    end

    def send_message(message)
      raise PipeError, 'Pipe is not connected' unless @state == :connected
      data = JSON.generate(message).encode('UTF-8').b
      raise PipeError, 'Frame too large' if data.bytesize > MAX_FRAME
      raise PipeError, 'Output queue full' if @queue.length >= MAX_QUEUE
      @queue << data + "\n".b
    end

    def poll
      return reap if @state == :closing
      return [] unless @state == :connected
      messages = []
      if @write
        size = @write.result
        if size
          expected = @write.length
          @write.dispose
          @write = nil
          raise PipeError, 'Incomplete pipe write' if size != expected
        elsif Process.clock_gettime(Process::CLOCK_MONOTONIC) - @write.started > 5
          raise PipeError, 'Pipe write timed out'
        end
      end
      @write = NativeOperation.new(@handle, :write, @queue.shift) if !@write && !@queue.empty?
      @read ||= NativeOperation.new(@handle, :read)
      size = @read.result
      if size
        @input << @read.buffer[0, size]
        @read.dispose
        @read = nil
        raise PipeError, 'Server disconnected' if size == 0
      end
      # Bounded dispatch per UI tick. Framing handles split/coalesced UTF-8 data.
      16.times do
        index = @input.index("\n".b)
        break unless index
        raise PipeError, 'Incoming frame too large' if index > MAX_FRAME
        line = @input.slice!(0, index + 1).force_encoding('UTF-8')
        raise PipeError, 'Invalid UTF-8' unless line.valid_encoding?
        message = JSON.parse(line)
        raise PipeError, 'Invalid protocol envelope' unless message.is_a?(Hash) && message['v'] == 1
        messages << message
      end
      # This also bounds malicious delimiter-free input.
      raise PipeError, 'Input buffer full' if @input.bytesize > MAX_FRAME * 2
      messages
    end

    def close
      return if @state == :closed || @state == :closing
      @state = :closing
      @queue.clear
      Win32.CancelIoEx(@handle, 0)
      reap
    end

    private

    def reap
      [:@read, :@write].each do |name|
        operation = instance_variable_get(name)
        next unless operation
        begin
          operation.result
        rescue PipeError
          # Canceled/broken I/O is terminal. Keep memory until it is terminal.
        end
        next if operation.pending?
        operation.dispose
        instance_variable_set(name, nil)
      end
      unless @read || @write
        Win32.CloseHandle(@handle) if @handle
        @handle = nil
        @input.clear
        @state = :closed
      end
      []
    end
  end
end
