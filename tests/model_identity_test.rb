# encoding: UTF-8
require 'minitest/autorun'
module Sketchup
  class AppObserver; end
end
require_relative '../extension/su_pipe_probe/model_identity'
require_relative '../extension/su_pipe_probe/session'

class ModelIdentityTest < Minitest::Test
  Model = Struct.new(:title, :path, :revision)

  def setup
    @active = Model.new('', '', 0)
    @sent, @reads, @writes = [], [], []
    @session = nil
    @identity = SUPipeProbe::ModelIdentity.new { @session.tick if @session }
    @metadata = lambda { {'model_id'=>@identity.id_for(@active), 'title'=>@active.title, 'path'=>@active.path} }
    @session = SUPipeProbe::Session.new(lambda { |m| @sent << m }, @metadata, lambda { 0.0 },
      lambda { |method, _args| @reads << method; {'items'=>[]} },
      lambda { |method, _args| @writes << method; {'dry_run'=>false} })
  end

  def model_id
    @session.snapshot['model_id']
  end

  def request(method, fields = {})
    @session.receive({'type'=>'request', 'id'=>SecureRandom.uuid, 'method'=>method,
      'session_id'=>@session.session_id, 'model_id'=>model_id, 'lease'=>@session.lease,
      'owner_id'=>'owner-a', 'command_id'=>@session.snapshot['next_command_id'],
      'expires_at_ms'=>Time.now.to_f * 1000 + 7000,
      'expected_context'=>[], 'entity_ids'=>['101'], 'delta_mm'=>[1000,0,0]}.merge(fields))
    @sent.reverse.find { |m| m['type']=='result' }
  end

  def test_repeated_reads_edits_save_and_save_as_keep_document_identity
    original = model_id
    @session.grant
    @active.revision += 1
    @active.title, @active.path = 'Saved', 'saved.skp'
    @session.tick
    assert_equal original, model_id
    @active.title, @active.path = 'Save As', 'new-name.skp'
    3.times { assert_equal original, model_id }
    assert_equal 'mcp', @session.authority
  end

  def test_new_model_renews_id_even_with_same_wrapper_and_empty_metadata
    original = model_id
    wrapper = @active
    @identity.onNewModel(@active)
    assert_same wrapper, @active
    refute_equal original, model_id
    assert_equal '', @active.path
    assert_equal '', @active.title
  end

  def test_opening_same_file_again_renews_id_with_unchanged_wrapper_and_path
    @active.title, @active.path = 'A', 'same.skp'
    original = model_id
    @session.grant
    @identity.onOpenModel(@active)
    refute_equal original, model_id
    assert_equal 'same.skp', @active.path
    assert_equal 'user', @session.authority
    assert_nil @session.lease
  end

  def test_new_model_revokes_immediately_and_rejects_queued_old_command_before_timer
    @session.grant
    old_id, old_lease = model_id, @session.lease
    command_id = @session.snapshot['next_command_id']
    @identity.onNewModel(@active)
    assert_equal 'user', @session.authority
    assert_nil @session.lease
    result = request('move_entities', 'model_id'=>old_id, 'lease'=>old_lease, 'command_id'=>command_id)
    assert_equal 'model_mismatch', result['status']
    assert_equal model_id, result['model_id']
    assert_empty @writes
    assert_equal command_id, @session.snapshot['next_command_id']
  end

  def test_old_model_reads_and_discovery_do_not_reach_reader
    old_id = model_id
    @identity.onOpenModel(@active)
    %w[get_model_summary get_selection_info find_entities get_children].each do |method|
      assert_equal 'model_mismatch', request(method, 'model_id'=>old_id)['status']
    end
    assert_empty @reads
    assert request('get_model_summary')['ok']
    assert_equal ['get_model_summary'], @reads
  end

  def test_new_document_needs_new_permission_and_old_lease_stays_invalid
    @session.grant
    old_lease = @session.lease
    @identity.onNewModel(@active)
    assert_equal 'authority_or_model_mismatch', request('move_entities', 'lease'=>old_lease)['status']
    assert_empty @writes
    @session.grant
    refute_equal old_lease, @session.lease
    assert_equal 'authority_or_model_mismatch', request('move_entities', 'lease'=>old_lease)['status']
    assert request('move_entities')['ok']
    assert_equal ['move_entities'], @writes
  end

  def test_history_counter_and_session_survive_but_old_execution_is_never_replayed_into_new_model
    @session.grant
    original = request('move_entities')
    old_id, session_id = model_id, @session.session_id
    next_id = @session.snapshot['next_command_id']
    @identity.onNewModel(@active)
    assert_equal session_id, @session.session_id
    assert_equal next_id, @session.snapshot['next_command_id']
    assert_equal 'model_mismatch', request('move_entities', 'model_id'=>old_id, 'command_id'=>original['command_id'])['status']
    assert_equal original['result'], request('get_command_result', 'model_id'=>old_id, 'command_id'=>original['command_id'])['result']
    @session.grant
    assert_equal 'command_id_conflict', request('move_entities', 'command_id'=>original['command_id'])['status']
    assert_equal 1, @writes.length
  end

  def test_model_replacement_cancels_demo_before_next_timer
    @session.grant
    job_id = request('demo')['job_id']
    @identity.onOpenModel(@active)
    assert_nil @session.job
    assert_equal 'user', @session.authority
    assert_equal 'canceled', request('get_job', 'job_id'=>job_id)['job']['status']
  end

  def test_wrapper_change_fallback_also_revokes_and_renews
    @session.grant
    old_id = model_id
    @active = Model.new('', '', 0)
    refute_equal old_id, model_id
    assert_equal 'user', @session.authority
    assert_nil @session.lease
  end

  def test_grant_refreshes_identity_if_wrapper_changes_without_notification
    @session.grant
    old_id, old_lease = model_id, @session.lease
    @active = Model.new('', '', 0)
    @session.grant
    refute_equal old_id, model_id
    refute_equal old_lease, @session.lease
    assert_equal 'mcp', @session.authority
  end

  def test_activation_of_same_model_is_stable_and_switching_models_renews
    original = model_id
    @identity.onActivateModel(@active)
    assert_equal original, model_id
    @active = Model.new('B', 'b.skp', 0)
    @identity.onActivateModel(@active)
    refute_equal original, model_id
  end

  def test_multiple_events_before_timer_each_get_a_new_document_id
    first = model_id
    @identity.onNewModel(@active)
    second = model_id
    @identity.onOpenModel(@active)
    third = model_id
    assert_equal 3, [first,second,third].uniq.length
    assert @identity.expectsStartupModelNotifications
    assert_kind_of Sketchup::AppObserver, @identity
  end
end
