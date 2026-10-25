# encoding: UTF-8
require 'fiddle'
require_relative 'native_call'
require_relative 'version'

module SUPipeProbe
  module Win32
    raise 'Windows x64 Ruby is required' unless RUBY_PLATFORM =~ /mswin|mingw/ && Fiddle::SIZEOF_VOIDP == 8
    KERNEL = Fiddle.dlopen('kernel32.dll')
    PTR = Fiddle::TYPE_VOIDP
    INT = Fiddle::TYPE_INT

    # Load by absolute UTF-16 path, including Korean Windows user names.
    LOAD_LIBRARY = Fiddle::Function.new(KERNEL['LoadLibraryW'], [PTR], PTR)
    GET_PROC = Fiddle::Function.new(KERNEL['GetProcAddress'], [PTR, PTR], PTR)
    DLL_PATH = File.join(__dir__, 'native', 'pipe_win32_x64.dll')
    path = DLL_PATH.encode('UTF-16LE').b + "\0\0".b
    DLL_HANDLE = LOAD_LIBRARY.call(path)
    raise "Cannot load #{DLL_PATH}; reinstall the complete #{VERSION} RBZ" if DLL_HANDLE.to_i == 0

    def self.export(name, arguments, result)
      address = GET_PROC.call(DLL_HANDLE, name + "\0")
      raise "Missing native export: #{name}" if address.to_i == 0
      Fiddle::Function.new(address, arguments, result)
    end

    ABI_VERSION = export('sp_AbiVersion', [], INT).call
    raise 'Unsupported pipe helper ABI' unless ABI_VERSION == 1

    # DWORD is 32 bits even in the Windows x64 ABI. Last argument is DWORD*.
    {
      :CreateFileW => [[PTR, INT, INT, PTR, INT, INT, PTR], PTR],
      :CreateEventW => [[PTR, INT, INT, PTR], PTR],
      :ReadFile => [[PTR, PTR, INT, PTR, PTR], INT],
      :WriteFile => [[PTR, PTR, INT, PTR, PTR], INT],
      :GetOverlappedResult => [[PTR, PTR, PTR, INT], INT],
      :CancelIoEx => [[PTR, PTR], INT],
      :CloseHandle => [[PTR], INT]
    }.each do |name, signature|
      function = NativeCall.new(export('sp_' + name.to_s, signature[0] + [PTR], signature[1]))
      define_singleton_method(name) do |*args|
        result, error = function.call(*args)
        Thread.current[:su_pipe_probe_win32_error] = error
        result
      end
    end

    def self.error
      Thread.current[:su_pipe_probe_win32_error]
    end

    def self.memory(bytes)
      pointer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
      pointer[0, bytes] = "\0" * bytes
      pointer
    end
  end
end
