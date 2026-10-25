# encoding: UTF-8
require 'securerandom'
require 'json'
require 'digest'
require 'time'
require_relative 'command_executor'

module SUPipeProbe
  # Protocol and authority state machine; independent of SketchUp and Win32.
  class Session
    attr_reader :session_id, :authority, :lease, :job, :last_error, :last_result

    def initialize(sender, metadata, clock = nil, reader = nil, executor = nil)
      @sender, @metadata = sender, metadata
      @reader = reader
      @executor = executor
      @command_sequence = 0
      @commands = {}
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
        'next_command_id' => next_command_id,
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
      return execute_command(id, method, message) if CommandExecutor::METHODS.include?(method)
      case method
      when 'ping'
        reply(id, true, 'pong', 'text' => message['text'].to_s)
      when 'get_state'
        reply(id, true, 'state', 'state' => snapshot.reject { |key, _| key == 'lease' })
      when 'get_model_summary', 'get_selection_info', 'find_entities', 'get_children'
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
        statuses = {'get_model_summary'=>'model_summary', 'get_selection_info'=>'selection_info',
          'find_entities'=>'entities_found', 'get_children'=>'children'}
        reply(id, true, statuses.fetch(method),
          'model_id' => @model_id, 'data' => data)
      when 'get_job'
        job_id = message['job_id']
        state = @job && @job[:id] == job_id ? job_state('running') : @history[job_id]
        reply(id, !state.nil?, state ? 'job' : 'job_not_found', 'job' => state)
      when 'get_command_result'
        sequence = command_sequence(message['command_id'])
        return reply(id, false, 'invalid_command_id') unless sequence
        record = @commands[message['command_id']]
        return reply(id, false, sequence <= @command_sequence ? 'command_expired' : 'command_not_found') unless record
        return reply(id, false, 'model_mismatch') unless record['result']['model_id'] == message['model_id']
        reply(id, true, 'command_result', 'result' => record['result'])
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
        return reply(id, false, 'controller_busy') if @controller_owner && @controller_owner != message['owner_id']
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

    def next_command_id
      @command_sequence < 1_000_000_000 ? "#{@session_id}:#{@command_sequence + 1}" : nil
    end

    def command_sequence(value)
      return nil unless value.is_a?(String) && value.start_with?(@session_id + ':')
      number = value[(@session_id.length + 1)..-1]
      return nil unless number.match(/\A[1-9][0-9]{0,9}\z/)
      sequence = number.to_i
      sequence <= 1_000_000_000 ? sequence : nil
    end

    def canonical(value)
      case value
      when Hash then value.keys.sort.each_with_object({}) { |key, result| result[key] = canonical(value[key]) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def execute_command(id, method, message)
      return reply(id, false, 'model_mismatch', 'model_id' => @model_id) unless message['model_id'] == @model_id
      command_id = message['command_id']
      sequence = command_sequence(command_id)
      return reply(id, false, 'invalid_command_id') unless sequence
      ignored = %w[v type session_id id method lease expires_at_ms owner_id]
      payload = message.reject { |key, _| ignored.include?(key) }.merge('command' => method)
      begin
        signature = Digest::SHA256.hexdigest(JSON.generate(canonical(payload)))
      rescue StandardError
        return reply(id, false, 'invalid_arguments')
      end
      record = @commands[command_id]
      if record
        return reply(id, false, 'command_id_conflict') unless record['signature'] == signature
        result = record['result']
        return reply(id, result['state'] != 'failed' && result['state'] != 'unknown',
          result['error'] || 'command_replayed', 'replayed' => true, 'result' => result)
      end
      return reply(id, false, 'command_expired') if sequence <= @command_sequence
      return reply(id, false, 'command_out_of_order', 'next_command_id' => next_command_id) unless sequence == @command_sequence + 1
      unless @authority == 'mcp' && message['lease'] == @lease
        return reply(id, false, 'authority_or_model_mismatch')
      end
      return reply(id, false, 'controller_busy') if @controller_owner && @controller_owner != message['owner_id']
      return reply(id, false, 'busy') if @job
      return reply(id, false, 'request_expired') unless message['expires_at_ms'].is_a?(Numeric) && Time.now.to_f * 1000 <= message['expires_at_ms']
      return reply(id, false, 'command_unavailable') unless @executor
      # Counter is never reset on model changes, grant/revoke, or bridge reconnect.
      # It rejects evicted IDs without retaining an unbounded tombstone set.
      @command_sequence = sequence
      @controller_owner = message['owner_id']
      result = {'command_id' => command_id, 'model_id' => @model_id,
        'command' => method, 'expected_context' => message['expected_context'], 'finished_at' => Time.now.utc.iso8601(3)}
      begin
        data = @executor.call(method, message)
        unless data.is_a?(Hash) && JSON.generate(data).bytesize <= CommandExecutor::RESULT_LIMIT
          raise CommandError.new('outcome_unknown', 'Command result cannot be represented; inspect the model')
        end
        result['state'] = message['dry_run'] ? 'preview' : 'completed'
        result['data'] = data
      rescue StandardError => error
        code = error.is_a?(CommandError) ? error.code : 'api_error'
        result.merge!('state' => code == 'outcome_unknown' ? 'unknown' : 'failed',
          'error' => code, 'message' => error.message.to_s[0, 256])
      end
      result['finished_at'] = Time.now.utc.iso8601(3)
      result = JSON.parse(JSON.generate(result))
      @commands[command_id] = {'signature' => signature, 'result' => result}
      @commands.shift while @commands.length > 32
      labels = {'set_selection'=>'선택 변경', 'set_view'=>'보기 변경', 'zoom'=>'화면 확대',
        'update_entity_properties'=>'객체 속성 변경', 'move_entities'=>'객체 이동'}
      states = {'preview'=>'미리보기 완료', 'completed'=>'완료', 'failed'=>'실패', 'unknown'=>'결과 확인 필요'}
      @last_result = labels[method] + ': ' + states[result['state']]
      @last_error = result['message'] || ''
      reply(id, !result.key?('error'), result['error'] || 'command_' + result['state'],
        'command_id' => command_id, 'model_id' => @model_id,
        'next_command_id' => next_command_id, 'result' => result)
    end

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
