# encoding: UTF-8
require 'minitest/autorun'
require_relative '../extension/su_pipe_probe/session'

class CommandSessionTest < Minitest::Test
  def setup
    @sent, @calls = [], []
    @model = {'model_id'=>'model-a'}
    @executor = lambda { |method, args| @calls << [method, args]; {'dry_run'=>args.fetch('dry_run', false)} }
    @session = SUPipeProbe::Session.new(lambda { |m| @sent << m }, lambda { @model }, nil, nil,
      lambda { |method, args| @executor.call(method, args) })
  end
  def request(method, fields = {})
    @session.receive({'v'=>1, 'type'=>'request', 'id'=>SecureRandom.uuid, 'method'=>method,
      'session_id'=>@session.session_id, 'model_id'=>@model['model_id'], 'lease'=>@session.lease,
      'owner_id'=>'owner-a', 'expires_at_ms'=>Time.now.to_f*1000+7000}.merge(fields))
    @sent.reverse.find { |m| m['type']=='result' }
  end
  def command(fields = {})
    request('move_entities', {'command_id'=>@session.snapshot['next_command_id'],
      'expected_context'=>[], 'entity_ids'=>['101'], 'delta_mm'=>[1000,0,0]}.merge(fields))
  end
  def test_native_activity_is_visible_only_during_execution_and_cleared_on_error
    @session.grant
    observed=[]
    @session.on_change=lambda { observed << @session.busy? }
    @executor=lambda do |method,args|
      assert @session.busy?
      assert_equal args['command_id'],@session.snapshot['active_command']['command_id']
      assert_equal method,@session.snapshot['active_command']['method']
      raise ArgumentError,'native failure'
    end
    result=command
    refute result['ok']
    refute @session.busy?
    assert_nil @session.snapshot['active_command']
    assert_includes observed,true
    assert_equal false,observed.last
  end

  def test_permission_and_expiry_reject_without_consuming_id
    original = @session.snapshot['next_command_id']
    assert_equal 'authority_or_model_mismatch', command['status']
    @session.grant
    assert_equal 'request_expired', command('expires_at_ms'=>1)['status']
    assert_equal original, @session.snapshot['next_command_id']
    assert_empty @calls
  end
  def test_replay_returns_result_without_reexecution_even_after_revoke
    @session.grant
    id = @session.snapshot['next_command_id']
    first = command('command_id'=>id)
    @session.revoke
    result = command('command_id'=>id)
    assert result['ok']
    assert result['replayed']
    assert_equal first['result'], result['result']
    assert_equal 1, @calls.length
  end
  def test_conflicting_payload_and_method_never_execute
    @session.grant
    id = @session.snapshot['next_command_id']
    command('command_id'=>id)
    assert_equal 'command_id_conflict', command('command_id'=>id,'delta_mm'=>[2,0,0])['status']
    assert_equal 'command_id_conflict', request('set_view', 'command_id'=>id, 'expected_context'=>[], 'preset'=>'top')['status']
    assert_equal 1, @calls.length
  end
  def test_evicted_command_never_executes_again
    @session.grant
    original = @session.snapshot['next_command_id']
    33.times { assert command['ok'] }
    assert_equal 'command_expired', command('command_id'=>original)['status']
    assert_equal 'command_expired', request('get_command_result', 'command_id'=>original)['status']
    assert_equal 33, @calls.length
  end
  def test_out_of_order_and_foreign_session_ids_are_rejected
    @session.grant
    assert_equal 'command_out_of_order', command('command_id'=>@session.session_id+':2')['status']
    assert_equal 'invalid_command_id', command('command_id'=>SecureRandom.uuid+':1')['status']
    assert_empty @calls
  end
  def test_result_query_needs_matching_original_model_but_no_permission
    @session.grant
    executed = command
    @session.revoke
    id = executed['command_id']
    assert_equal 'completed', request('get_command_result','command_id'=>id)['result']['state']
    assert_equal 'model_mismatch', request('get_command_result','command_id'=>id,'model_id'=>'wrong')['status']
    assert_equal 'command_not_found', request('get_command_result','command_id'=>@session.snapshot['next_command_id'])['status']
  end
  def test_model_change_and_reconnect_preserve_counter_and_history
    @session.grant
    first = command
    next_id = @session.snapshot['next_command_id']
    @session.reset
    assert_equal next_id, @session.snapshot['next_command_id']
    @model['model_id'] = 'model-b'
    @session.tick
    assert_equal next_id, @session.snapshot['next_command_id']
    assert_equal 'model_mismatch', command('model_id'=>'model-a')['status']
    assert request('get_command_result','command_id'=>first['command_id'],'model_id'=>'model-a')['ok']
    @session.grant
    assert command['ok']
    assert_equal 2, @calls.length
  end
  def test_failed_and_unknown_results_are_cached_and_not_reexecuted
    @session.grant
    @executor = lambda { |*_args| @calls << :failed; raise SUPipeProbe::CommandError.new('outcome_unknown','Rollback failed') }
    id = @session.snapshot['next_command_id']
    assert_equal 'outcome_unknown', command('command_id'=>id)['status']
    assert_equal 'unknown', request('get_command_result','command_id'=>id)['result']['state']
    assert_equal 'outcome_unknown', command('command_id'=>id)['status']
    assert_equal 1, @calls.length
  end
  def test_dry_run_consumes_its_id_and_needs_new_id_for_execution
    @session.grant
    id = @session.snapshot['next_command_id']
    assert_equal 'preview', command('command_id'=>id,'dry_run'=>true)['result']['state']
    assert_equal 'command_id_conflict', command('command_id'=>id)['status']
    refute_equal id, @session.snapshot['next_command_id']
    assert command['ok']
  end
  def test_unknown_cleanup_details_survive_result_lookup_without_reexecution
    details={'changed_fields'=>['bounds'],'differences'=>{'bounds'=>{'before'=>nil,'after'=>[[0,0,0],[1,2,3]]}}}
    @session.grant
    @executor=lambda { |*_args| @calls<<:failed;raise SUPipeProbe::CommandError.new('outcome_unknown','Cleanup mismatch',details) }
    first=command
    assert_equal 'unknown',first['result']['state']
    assert_equal details,first['result']['details']
    @session.revoke
    assert_equal first['result'],request('get_command_result','command_id'=>first['command_id'])['result']
    assert_equal 1,@calls.length
  end
  def test_oversized_error_details_do_not_break_cached_failure
    @session.grant
    @executor=lambda { |*_args| raise SUPipeProbe::CommandError.new('outcome_unknown','Cleanup mismatch',{'large'=>'x'*5000}) }
    result=command['result']
    assert_equal 'unknown',result['state']
    refute result.key?('details')
  end
  def test_other_owner_is_rejected_and_only_matching_disconnect_revokes
    @session.grant
    command
    assert_equal 'controller_busy', command('owner_id'=>'owner-b')['status']
    request('release_owner','owner_id'=>'owner-b')
    assert_equal 'mcp', @session.authority
    request('release_owner')
    assert_equal 'user', @session.authority
  end
  def test_running_demo_blocks_commands_without_burning_id
    @session.grant
    request('demo')
    original = @session.snapshot['next_command_id']
    assert_equal 'busy', command['status']
    assert_equal original, @session.snapshot['next_command_id']
    assert_empty @calls
  end
  def test_creation_and_duplication_require_permission_and_replay_without_new_objects
    {'create_box'=>{'name'=>'A동', 'origin_mm'=>[0,0,0], 'size_mm'=>[1000,2000,3000]},
     'duplicate_entities'=>{'entity_ids'=>['101'], 'delta_mm'=>[1000,0,0]}}.each do |method, fields|
      @session.revoke
      args = fields.merge('expected_context'=>[], 'command_id'=>@session.snapshot['next_command_id'])
      before = @calls.length
      assert_equal 'authority_or_model_mismatch', request(method,args)['status']
      assert_equal before, @calls.length
      @session.grant
      preview = request(method,args.merge('dry_run'=>true))
      assert_equal 'preview', preview['result']['state']
      assert_equal 'command_id_conflict', request(method,args)['status']
      args['command_id'] = @session.snapshot['next_command_id']
      first = request(method,args)
      assert_equal 'completed', first['result']['state']
      replay = request(method,args)
      assert replay['replayed']
      assert_equal first['result'], replay['result']
      assert_equal before + 2, @calls.length
    end
  end

  def test_batch_report_failure_is_visible_and_cached_without_an_automatic_rerun
    @executor = lambda { |method,args| @calls << method; {'passed'=>false,'cleanup_verified'=>true,'checks'=>[{'name'=>'circle','status'=>'failed','message'=>'Area mismatch'}]} }
    @session.grant
    fields={'command_id'=>@session.snapshot['next_command_id'],'expected_context'=>[],'confirm_test_model'=>true}
    result=request('run_self_test',fields)
    assert_equal 'completed',result['result']['state']
    refute result['result']['data']['passed']
    assert_includes @session.last_result,'실패'
    assert_includes @session.last_error,'Area mismatch'
    assert request('run_self_test',fields)['replayed']
    assert_equal 1,@calls.length
  end


end
