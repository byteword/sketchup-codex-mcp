# encoding: UTF-8
require 'securerandom'
require 'json'

module SUPipeProbe
  # Protocol and authority state machine; independent of SketchUp and Win32.
  class Session
    attr_reader :session_id, :authority, :lease, :job, :last_error, :last_result

    def initialize(sender, metadata, clock = nil, reader = nil)
      @sender, @metadata = sender, metadata
      @reader = reader
      @clock = clock || lambda { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @session_id = SecureRandom.uuid
      @authority = 'user'
      @last_error = ''
      @last_result = ''
      @seen = []
      @history = {}
      @mcp_clients = []
      @model_id = @metadata.call['model_id']
    end

    def envelope(type, fields = {})
      {'v' => 1, 'type' => type, 'session_id' => @session_id}.merge(fields)
    end

    def snapshot
      @metadata.call.merge('authority' => @authority, 'lease' => @lease,
        'mcp_clients' => @mcp_clients,
        'job_id' => @job && @job[:id], 'progress' => @job ? @job[:progress] : 0,
        'last_error' => @last_error, 'last_result' => @last_result)
    end

    def publish(type = 'state')
      @sender.call(envelope(type, snapshot))
    end

    def reset
      remember_job('canceled', 'Bridge disconnected') if @job
      @authority = 'user'
      @lease = nil
      @job = nil
      @controller_owner = nil
      @mcp_clients = []
      @last_result = 'Disconnected / control returned to user'
    end

    def grant
      return if @authority == 'mcp'
      @authority = 'mcp'
      @lease = SecureRandom.uuid
      publish
    end

    def revoke(reason = 'User reclaimed control')
      cancel(reason)
      @authority = 'user'
      @lease = nil
      @controller_owner = nil
      publish
    end

    def cancel(reason)
      if @job
        remember_job('canceled', reason)
        @sender.call(envelope('event', 'event' => 'canceled', 'job_id' => @job[:id], 'reason' => reason))
        @job = nil
      end
      @last_result = reason
    end

    def report_error(message)
      @last_error = message.to_s
    end

    def local_ping
      @ping_id = SecureRandom.uuid
      @sender.call(envelope('request', 'id' => @ping_id, 'method' => 'ping', 'text' => 'SketchUp → GUI: 한글 왕복'))
    end

    def tick
      model_id = @metadata.call['model_id']
      if model_id != @model_id
        @model_id = model_id
        revoke('Model changed; control returned to user')
      end
      return unless @job
      elapsed = @clock.call - @job[:started]
      @job[:progress] = [100, (elapsed * 5).to_i].min # 20 second cooperative demo
      if @job[:progress] == 100
        remember_job('completed', 'Demo completed')
        @sender.call(envelope('event', 'event' => 'completed', 'job_id' => @job[:id]))
        @last_result = 'Demo completed (no geometry changes)'
        @job = nil
        publish
      end
    end

    def receive(message)
      return unless message['session_id'] == @session_id
      if message['type'] == 'bridge_state'
        @mcp_clients = message['mcp_clients'].is_a?(Array) ? message['mcp_clients'] : []
        return
      end
      if message['type'] == 'result' && message['id'] == @ping_id
        @last_result = 'GUI replied: ' + message['text'].to_s
        @ping_id = nil
        return
      end
      return unless message['type'] == 'request'
      id = message['id']
      return unless id.is_a?(String) && id.bytesize.between?(1, 128)
      return reply(id, false, 'duplicate_id') if @seen.include?(id)
      @seen << id
      @seen.shift if @seen.length > 256
      # Check model identity BEFORE authorizing any command, not after dispatch.
      tick
      method = message['method']
      case method
      when 'ping'
        reply(id, true, 'pong', 'text' => message['text'].to_s)
      when 'get_state'
        reply(id, true, 'state', 'state' => snapshot.reject { |key, _| key == 'lease' })
      when 'get_model_summary', 'get_selection_info'
        return reply(id, false, 'model_mismatch', 'model_id' => @model_id) unless message['model_id'] == @model_id
        if message['expires_at_ms'] && Time.now.to_f * 1000 > message['expires_at_ms'].to_f
          return reply(id, false, 'request_expired')
        end
        return reply(id, false, 'query_unavailable') unless @reader
        begin
          data = @reader.call(method, message)
          # Keep room for the protocol envelope below the 64 KiB pipe limit.
          return reply(id, false, 'response_too_large') if JSON.generate(data).bytesize > 60_000
        rescue StandardError => error
          # Query errors must not reset the pipe or revoke an unrelated job.
          return reply(id, false, 'query_failed', 'message' => error.message.to_s[0, 256])
        end
        reply(id, true, method == 'get_model_summary' ? 'model_summary' : 'selection_info',
          'model_id' => @model_id, 'data' => data)
      when 'get_job'
        job_id = message['job_id']
        state = @job && @job[:id] == job_id ? job_state('running') : @history[job_id]
        reply(id, !state.nil?, state ? 'job' : 'job_not_found', 'job' => state)
      when 'release_owner'
        revoke('MCP client disconnected; user control restored') if @controller_owner == message['owner_id'] && @controller_owner
        reply(id, true, 'owner_released')
      when 'cancel'
        # A delayed cancellation must never stop a newer job.
        if message.key?('job_id') && (!@job || @job[:id] != message['job_id'])
          return reply(id, true, 'not_running', 'job_id' => message['job_id'])
        end
        cancel('Canceled by bridge')
        reply(id, true, 'canceled')
        publish
      when 'demo', 'test_error'
        if message['expires_at_ms'] && Time.now.to_f * 1000 > message['expires_at_ms'].to_f
          return reply(id, false, 'request_expired')
        end
        unless @authority == 'mcp' && message['lease'] == @lease && message['model_id'] == @model_id
          return reply(id, false, 'authority_or_model_mismatch')
        end
        return reply(id, false, 'busy') if @job
        if method == 'test_error'
          @last_error = 'Intentional test error; model was not changed'
          return reply(id, false, 'intentional_test_error')
        end
        @last_error = ''
        @controller_owner = message['owner_id']
        @job = {:id => id, :started => @clock.call, :progress => 0, :model_id => @model_id}
        reply(id, true, 'accepted', 'job_id' => id)
        publish
      else
        reply(id, false, 'unknown_method')
      end
    end

    private

    def job_state(status, reason = '')
      {'job_id' => @job[:id], 'model_id' => @job[:model_id], 'status' => status,
       'progress' => @job[:progress], 'reason' => reason}
    end

    def remember_job(status, reason)
      @history[@job[:id]] = job_state(status, reason)
      @history.shift while @history.length > 32
    end

    def reply(id, ok, status, extra = {})
      @sender.call(envelope('result', {'id' => id, 'ok' => ok, 'status' => status}.merge(extra)))
    end
  end
end
