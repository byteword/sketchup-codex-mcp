# encoding: UTF-8
# Real Win32/Fiddle ↔ C# pipe test, runnable without SketchUp on Windows x64.
require 'minitest/autorun'
require 'securerandom'
require_relative '../extension/su_pipe_probe/win_pipe'

class WindowsPipeTest < Minitest::Test
  def setup
    @clients = []
    @ids = {}
  end

  def teardown
    @clients.each(&:close)
    deadline = monotonic + 5
    until @clients.all? { |c| c.state == :closed }
      raise 'Cancellation did not complete' if monotonic > deadline
      @clients.each(&:poll)
      sleep 0.01
    end
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def wait_for(client)
    deadline = monotonic + 5
    loop do
      client.poll.each { |m| return m if yield(m) }
      raise 'Timed out waiting for response' if monotonic > deadline
      sleep 0.01
    end
  end

  def connect
    client = SUPipeProbe::PipeClient.new
    @clients << client
    deadline = monotonic + 5
    begin
      client.connect
    rescue SUPipeProbe::PipeError
      raise if monotonic > deadline
      sleep 0.05
      retry
    end
    @ids[client] = SecureRandom.uuid
    client.send_message('v' => 1, 'type' => 'hello', 'session_id' => @ids[client], 'pid' => Process.pid)
    wait_for(client) { |m| m['type'] == 'welcome' }
    client
  end

  def ping(client, text)
    id = SecureRandom.uuid
    client.send_message('v' => 1, 'type' => 'request', 'session_id' => @ids[client],
      'id' => id, 'method' => 'ping', 'text' => text)
    response = wait_for(client) { |m| m['id'] == id }
    assert_equal @ids[client], response['session_id']
    assert_equal text, response['text']
  end

  def test_two_simultaneous_clients_unicode_and_reconnect
    a, b = connect, connect
    ping(a, 'A: 한글 日本語 🙂')
    ping(b, 'B: 다른 인스턴스')
    # Larger than native 8192-byte read buffers; exercises UTF-8 split frames.
    ping(a, '가🙂' * 3000)
    a.close
    deadline = monotonic + 5
    while a.state != :closed
      raise 'Close timed out' if monotonic > deadline
      a.poll
      sleep 0.01
    end
    ping(b, 'B remains connected')
    c = connect
    ping(c, 'Reconnected')
  end

  def test_pending_read_cancellation_does_not_block
    client = connect
    client.poll
    started = monotonic
    client.close
    assert_operator monotonic - started, :<, 0.5
  end

  def test_pending_read_and_completion_errors_are_captured_inside_native_call
    client = connect
    # Drain the one bridge_state message sent with welcome.
    deadline = monotonic + 1
    while monotonic < deadline
      client.poll
      sleep 0.01
    end
    assert_equal 996, SUPipeProbe::Win32.error
    assert_equal :connected, client.state
    10.times do
      assert_empty client.poll
      assert_equal 996, SUPipeProbe::Win32.error
    end
    ping(client, 'Still connected after idle pending reads')
  end
end
