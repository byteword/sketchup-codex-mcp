# encoding: UTF-8
require 'minitest/autorun'
require_relative '../extension/su_pipe_probe/session'

class SessionTest < Minitest::Test
  def setup
    @sent = []
    @time = 0.0
    @model = {'model_id' => 'model-a', 'pid' => 123}
    @session = SUPipeProbe::Session.new(lambda { |m| @sent << m }, lambda { @model }, lambda { @time })
  end

  def request(method, fields = {})
    message = {'v' => 1, 'type' => 'request', 'session_id' => @session.session_id,
      'id' => SecureRandom.uuid, 'method' => method, 'lease' => @session.lease, 'model_id' => @model['model_id']}
    @session.receive(message.merge(fields))
    @sent.reverse.find { |m| m['type'] == 'result' }
  end

  def test_user_mode_rejects_jobs_but_allows_ping
    assert_equal 'authority_or_model_mismatch', request('demo')['status']
    assert_nil @session.job
    assert_equal '한글🙂', request('ping', 'text' => '한글🙂')['text']
  end

  def test_progress_and_completion
    @session.grant
    assert_equal 'accepted', request('demo')['status']
    @time = 10
    @session.tick
    assert_equal 50, @session.job[:progress]
    @time = 20
    @session.tick
    assert_nil @session.job
    assert @sent.any? { |m| m['event'] == 'completed' }
  end

  def test_revoke_cancels_and_invalidates_lease
    @session.grant
    old_lease = @session.lease
    request('demo')
    @session.revoke
    assert_nil @session.job
    assert_nil @session.lease
    assert_equal 'user', @session.authority
    assert @sent.any? { |m| m['event'] == 'canceled' }
    @session.grant
    refute_equal old_lease, @session.lease
    assert_equal false, request('demo', 'lease' => old_lease)['ok']
  end

  def test_model_change_checked_before_request
    @session.grant
    lease = @session.lease
    @model = {'model_id' => 'model-b', 'pid' => 123}
    result = request('demo', 'lease' => lease, 'model_id' => 'model-a')
    assert_equal false, result['ok']
    assert_equal 'user', @session.authority
    assert_nil @session.job
  end

  def test_other_session_cannot_start_or_cancel_work
    @session.grant
    request('demo')
    id = @session.job[:id]
    request('cancel', 'session_id' => 'other-session')
    assert_equal id, @session.job[:id]
  end

  def test_duplicate_and_busy_do_not_replace_job
    @session.grant
    request('demo', 'id' => 'original')
    assert_equal 'duplicate_id', request('demo', 'id' => 'original')['status']
    assert_equal 'busy', request('demo')['status']
    assert_equal 'original', @session.job[:id]
  end

  def test_reconnect_reset_revokes_control
    @session.grant
    request('demo')
    @session.reset
    assert_nil @session.job
    assert_nil @session.lease
    assert_equal 'user', @session.authority
  end

  def test_explicit_cancel_and_intentional_error
    @session.grant
    request('demo')
    request('cancel')
    assert_nil @session.job
    assert_equal false, request('test_error')['ok']
    refute_empty @session.last_error
  end

  def test_fresh_state_does_not_expose_lease
    @session.grant
    result = request('get_state')
    assert_equal 'mcp', result['state']['authority']
    refute result['state'].key?('lease')
  end

  def test_finished_job_can_be_queried_and_history_is_bounded
    @session.grant
    ids = []
    33.times do
      ids << request('demo')['job_id']
      @time += 20
      @session.tick
    end
    assert_equal 'job_not_found', request('get_job', 'job_id' => ids.first)['status']
    result = request('get_job', 'job_id' => ids.last)['job']
    assert_equal 'completed', result['status']
    assert_equal 100, result['progress']
  end

  def test_cancel_old_job_cannot_cancel_new_job
    @session.grant
    old = request('demo')['job_id']
    request('cancel', 'job_id' => old)
    fresh = request('demo')['job_id']
    assert_equal 'not_running', request('cancel', 'job_id' => old)['status']
    assert_equal fresh, @session.job[:id]
    assert_equal 'canceled', request('get_job', 'job_id' => old)['job']['status']
  end

  def test_disconnect_only_releases_matching_owner
    @session.grant
    request('demo', 'owner_id' => 'client-a')
    request('release_owner', 'owner_id' => 'client-b')
    refute_nil @session.job
    assert_equal 'mcp', @session.authority
    request('release_owner', 'owner_id' => 'client-a')
    assert_nil @session.job
    assert_equal 'user', @session.authority
  end

  def test_expired_start_never_runs
    @session.grant
    assert_equal 'request_expired', request('demo', 'expires_at_ms' => 1)['status']
    assert_nil @session.job
  end

  def test_bridge_presence_and_reset
    @session.receive('type' => 'bridge_state', 'session_id' => @session.session_id,
      'mcp_clients' => [{'name' => 'ChatGPT'}])
    assert_equal 'ChatGPT', @session.snapshot['mcp_clients'].first['name']
    @session.reset
    assert_empty @session.snapshot['mcp_clients']
  end

  def test_reads_work_in_user_mode_and_model_mismatch_never_invokes_reader
    calls = []
    reader = lambda { |method, args| calls << [method, args]; {'title' => '대지'} }
    @session = SUPipeProbe::Session.new(lambda { |m| @sent << m }, lambda { @model }, lambda { @time }, reader)
    result = request('get_model_summary')
    assert result['ok']
    assert_equal 'model-a', result['model_id']
    assert_equal '대지', result['data']['title']
    assert_equal 'user', @session.authority
    assert_nil @session.job
    @model['model_id'] = 'model-b'
    assert_equal 'model_mismatch', request('get_selection_info', 'model_id' => 'model-a')['status']
    assert_equal 1, calls.length
  end

  def test_query_error_and_large_response_do_not_disconnect_or_revoke
    reader = lambda do |method, args|
      raise 'API read error' if method == 'get_model_summary'
      {'text' => '가' * 30_000}
    end
    @session = SUPipeProbe::Session.new(lambda { |m| @sent << m }, lambda { @model }, lambda { @time }, reader)
    @session.grant
    request('demo')
    assert_equal 'query_failed', request('get_model_summary')['status']
    assert_equal 'response_too_large', request('get_selection_info')['status']
    assert_equal 'mcp', @session.authority
    refute_nil @session.job
    assert_equal 'pong', request('ping')['status']
  end

  def test_expired_read_is_not_executed
    reader = lambda { |*_args| flunk 'Expired read was executed' }
    @session = SUPipeProbe::Session.new(lambda { |m| @sent << m }, lambda { @model }, nil, reader)
    assert_equal 'request_expired', request('get_model_summary', 'expires_at_ms' => 1)['status']
  end
end
