# encoding: UTF-8
require 'minitest/autorun'
require_relative 'support/extended_double'
require_relative '../extension/su_pipe_probe/command_executor'
module UI
  class << self
    attr_accessor :refreshes,:on_refresh
    def refresh_inspectors
      self.refreshes=(refreshes || 0)+1
      on_refresh.call if on_refresh
    end
  end
end
class UiUpdatesTest < Minitest::Test
  def setup
    UI.refreshes=0; UI.on_refresh=nil
    @model=SketchupDouble::Model.new; @executor=SUPipeProbe::CommandExecutor.new(@model)
    @flags=[]; flags=@flags
    original=@model.method(:start_operation)
    @model.define_singleton_method(:start_operation) { |label,disable| flags<<disable; original.call(label,disable) }
    @redraws=0; test=self
    @model.active_view.define_singleton_method(:invalidate) { test.instance_variable_set(:@redraws,test.instance_variable_get(:@redraws)+1); self }
  end
  def teardown; UI.on_refresh=nil; assert_empty SUPipeProbe::UiUpdateScope.active; end
  def call(method,args={}); @executor.call(method,{'expected_context'=>[]}.merge(args)); end
  def box(name='box'); {'name'=>name,'origin_mm'=>[0,0,0],'size_mm'=>[100,100,100]}; end
  def step(method,args); {'method'=>method,'arguments'=>args}; end
  def batch(steps,fields={}); call('run_batch',{'steps'=>steps}.merge(fields)); end
  def error(code)
    e=assert_raises(SUPipeProbe::CommandError) { yield }; assert_equal code,e.code; e
  end
  def test_single_operation_suppresses_and_refreshes_after_commit_once
    UI.on_refresh=lambda { assert_equal 1,@model.commits; assert_equal 0,@model.aborts }
    result=call('create_box',box)
    assert_equal [true],@flags; assert_equal 1,@redraws; assert_equal 1,UI.refreshes
    assert result['ui_update']['operation_closed']; assert result['ui_update']['inspectors_refresh_requested']
    assert_equal false,result['ui_update']['outliner_visibility_changed']
  end
  def test_explicit_normal_mode_does_not_force_expensive_inspector_refresh
    result=call('create_box',box.merge('ui_updates'=>'normal'))
    assert_equal [false],@flags; assert_equal 0,UI.refreshes; assert_equal 1,@redraws
    refute result['ui_update']['suppression_requested']
    refute result['ui_update']['inspectors_refresh_requested']
  end
  def test_preview_and_invalid_policy_do_not_start_or_refresh
    call('create_box',box.merge('dry_run'=>true))
    error('invalid_arguments') { call('create_box',box.merge('ui_updates'=>'off')) }
    assert_empty @flags; assert_equal 0,@redraws; assert_equal 0,UI.refreshes
  end
  def test_exception_rolls_back_before_final_ui_refresh
    @model.fail_face_after=1
    UI.on_refresh=lambda { assert_equal 1,@model.aborts; assert_empty @model.entities.to_a }
    assert_raises(RuntimeError) { call('create_box',box) }
    assert_equal 1,UI.refreshes; assert_equal 1,@redraws; assert_equal 1,@model.aborts
  end
  def test_postcommit_refresh_error_is_a_warning_without_repeating_geometry
    UI.on_refresh=lambda { raise 'Inspector unavailable' }
    result=call('create_box',box)
    assert_equal 1,@model.entities.length; assert_equal 1,@model.commits; assert_equal 0,@model.aborts
    assert_includes result['ui_update']['warnings'].first,'Inspector unavailable'
    refute result['ui_update']['inspectors_refresh_requested']; assert_equal 1,UI.refreshes
  end
  def test_view_redraw_failure_does_not_skip_inspector_refresh
    @model.active_view.define_singleton_method(:invalidate) { raise 'Viewport unavailable' }
    result=call('create_box',box)
    assert_equal 1,UI.refreshes; assert result['ui_update']['inspectors_refresh_requested']
    assert_includes result['ui_update']['warnings'].first,'Viewport unavailable'
  end
  def test_start_failure_does_not_abort_an_unowned_operation_or_refresh
    @model.define_singleton_method(:start_operation) { |_label,_disable| false }
    error('operation_failed') { call('create_box',box) }
    assert_equal 0,@model.aborts; assert_equal 0,UI.refreshes; assert_equal 0,@redraws
  end
  def test_commit_failure_attempts_one_rollback_and_refresh
    @model.define_singleton_method(:commit_operation) { false }
    error('operation_failed') { call('create_box',box) }
    assert_equal 1,@model.aborts; assert_empty @model.entities.to_a; assert_equal 1,UI.refreshes
  end
  def test_unknown_rollback_does_not_force_inspectors_over_half_built_geometry
    @model.fail_face_after=1
    @model.define_singleton_method(:abort_operation) { false }
    error('outcome_unknown') { call('create_box',box) }
    assert_equal 0,UI.refreshes; assert_equal 0,@redraws; assert_equal 1,@model.starts
  end
  def test_ruby_interruption_releases_operation_and_ui
    scope=SUPipeProbe::UiUpdateScope.new(@model)
    assert_raises(Interrupt) { scope.run('interruption') { raise Interrupt,'cancel' } }
    assert scope.closed; assert scope.aborted; assert_equal 1,@model.aborts; assert_equal 1,UI.refreshes
  end
  def test_reentrant_scope_cannot_implicitly_close_outer_native_operation
    scope=SUPipeProbe::UiUpdateScope.new(@model)
    scope.run('outer') do
      error('operation_busy') { SUPipeProbe::UiUpdateScope.new(@model).run('inner') { {} } }
      assert_equal 1,@model.starts
      {}
    end
    assert_equal 1,@model.commits; assert_equal 1,UI.refreshes
  end
  def test_large_batch_has_one_undo_and_one_inspector_refresh
    result=batch(40.times.map { |i| step('create_box',box('box'+i.to_s)) })
    assert_equal 40,@model.entities.length; assert_equal 1,@model.starts; assert_equal 1,@model.commits
    assert_equal [true],@flags; assert_equal 1,UI.refreshes; assert_equal 1,@redraws
    assert_equal 40,result['results'].map { |r| r['created_ids'].first }.uniq.length
    @model.undo; assert_empty @model.entities.to_a
  end
  def test_middle_step_failure_restores_earlier_objects_and_has_no_partial_commit
    e=error('batch_step_failed') { batch([step('create_box',box),step('move_entities',{'entity_ids'=>['999'],'delta_mm'=>[1,0,0]}),step('create_box',box)]) }
    assert_includes e.message,'Step 2'; assert_equal 0,@model.commits; assert_equal 1,@model.aborts
    assert_empty @model.entities.to_a; assert_equal 1,UI.refreshes
  end
  def test_batch_preview_and_rejected_methods_never_suppress_ui
    preview=batch([step('create_box',box),step('create_box',box)],'dry_run'=>true)
    assert preview['dry_run']; assert_equal 0,@model.starts
    %w[run_batch scene set_view set_selection run_self_test].each { |method| error('invalid_arguments') { batch([step(method,{})]) } }
    error('invalid_arguments') { batch([step('create_box',box.merge('expected_context'=>[]))]) }
    assert_equal 0,@model.starts; assert_equal 0,UI.refreshes
  end
  def test_batch_normal_policy_applies_to_the_entire_operation
    result=batch([step('create_box',box),step('create_box',box)],'ui_updates'=>'normal')
    assert_equal [false],@flags; assert_equal 'normal',result['ui_update']['mode']; assert_equal 0,UI.refreshes
  end
  def test_native_acceptance_restores_geometry_before_one_inspector_refresh
    UI.on_refresh=lambda { assert_empty @model.entities.to_a; assert_equal 1,@model.aborts }
    result=call('run_self_test','confirm_test_model'=>true,'suite'=>'all')
    assert result['passed'],result['checks'].inspect; assert result['cleanup_verified']
    assert_equal 1,@model.starts; assert_equal 1,UI.refreshes; assert_equal 1,@redraws
    assert result['ui_update']['inspectors_refresh_requested']
  end
  def test_batch_deadline_aborts_completed_steps_and_refreshes_once
    times=[0,0,5]
    @executor.define_singleton_method(:batch_clock) { times.shift || 5 }
    error('batch_budget_exceeded') { batch([step('create_box',box),step('create_box',box)]) }
    assert_empty @model.entities.to_a; assert_equal 1,@model.aborts; assert_equal 0,@model.commits; assert_equal 1,UI.refreshes
  end
  def test_batch_bounds_and_repeated_different_requests_release_ui_each_time
    error('invalid_arguments') { batch([]) }
    error('invalid_arguments') { batch(65.times.map { step('create_box',box) }) }
    batch([step('create_box',box)]); batch([step('create_box',box)])
    assert_equal 2,@model.entities.length; assert_equal 2,@model.starts; assert_equal 2,UI.refreshes
  end
end
