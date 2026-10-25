# encoding: UTF-8
require 'minitest/autorun'
require_relative 'support/sketchup_double'
require_relative '../extension/su_pipe_probe/command_executor'

class CommandExecutorTest < Minitest::Test
  def setup
    @model = SketchupDouble::Model.new
    @a, @b = @model.add(101), @model.add(102, 'ComponentInstance')
    @executor = SUPipeProbe::CommandExecutor.new(@model)
  end
  def call(method, args = {})
    @executor.call(method, {'expected_context'=>[], 'entity_ids'=>['101']}.merge(args))
  end
  def rejected(code, &block)
    error = assert_raises(SUPipeProbe::CommandError, &block)
    assert_equal code, error.code
  end
  def test_selection_replace_add_remove_and_clear_without_undo
    call('set_selection', 'mode'=>'replace')
    assert_equal [@a], @model.selection
    call('set_selection', 'mode'=>'add', 'entity_ids'=>['102'])
    assert_equal [@a,@b], @model.selection
    call('set_selection', 'mode'=>'remove')
    assert_equal [@b], @model.selection
    call('set_selection', 'mode'=>'clear', 'entity_ids'=>[])
    assert_empty @model.selection
    assert_equal 0, @model.starts
    refute @model.modified?
  end
  def test_selection_failure_restores_previous_selection
    @model.selection.add([@a])
    @model.selection.fail_next_add = true
    assert_raises(RuntimeError) { call('set_selection', 'mode'=>'replace', 'entity_ids'=>['102']) }
    assert_equal [@a], @model.selection
  end
  def test_dry_run_does_not_change_any_model_or_ui_state
    call('set_selection', 'mode'=>'replace', 'dry_run'=>true)
    call('update_entity_properties', 'properties'=>{'name'=>'changed'}, 'dry_run'=>true)
    call('move_entities', 'delta_mm'=>[1000,0,0], 'dry_run'=>true)
    camera = @model.active_view.camera
    call('set_view', 'preset'=>'top', 'dry_run'=>true)
    call('zoom', 'scope'=>'entities', 'dry_run'=>true)
    assert_empty @model.selection
    assert_equal 'block', @a.name
    assert_equal [0,0,0], @a.transformation.origin.to_a
    assert_same camera, @model.active_view.camera
    assert_equal 0, @model.starts
  end
  def test_properties_on_two_entities_commit_once_and_undo_once
    result = call('update_entity_properties', 'entity_ids'=>['101','102'],
      'properties'=>{'name'=>'A동', 'tag'=>'구조', 'material'=>'콘크리트', 'hidden'=>true, 'locked'=>true})
    assert result['undoable']
    assert_equal 1, @model.commits
    assert_equal 'A동', @a.name
    assert_equal '구조', @b.layer.name
    assert_equal '콘크리트', @b.material.name
    assert @a.hidden?
    assert @a.locked?
    @model.undo
    assert_equal 'block', @a.name
    assert_equal 'Layer0', @b.layer.name
    assert_nil @a.material
    refute @a.hidden?
    refute @a.locked?
  end
  def test_partial_property_failure_aborts_all_targets
    @b.fail_write = :name
    assert_raises(RuntimeError) { call('update_entity_properties', 'entity_ids'=>['101','102'], 'properties'=>{'name'=>'changed'}) }
    assert_equal 'block', @a.name
    assert_equal 'block', @b.name
    assert_equal 1, @model.aborts
    assert_equal 0, @model.commits
    refute @model.modified?
  end
  def test_existing_material_can_be_removed
    @a.material = @model.materials[0]
    call('update_entity_properties', 'properties'=>{'material'=>nil})
    assert_nil @a.material
  end
  def test_locked_entity_only_allows_separate_unlock
    @a.locked = true
    rejected('entity_locked') { call('move_entities', 'delta_mm'=>[1,0,0]) }
    rejected('entity_locked') { call('update_entity_properties', 'properties'=>{'locked'=>false, 'name'=>'changed'}) }
    call('update_entity_properties', 'properties'=>{'locked'=>false})
    refute @a.locked?
  end
  def test_context_and_entity_parent_are_both_checked
    rejected('context_mismatch') { call('move_entities', 'expected_context'=>['999'], 'delta_mm'=>[1,0,0]) }
    @a.parent = Object.new
    rejected('entity_context_mismatch') { call('move_entities', 'delta_mm'=>[1,0,0]) }
    assert_equal 0, @model.starts
  end
  def test_missing_deleted_and_unsupported_entities_are_rejected
    rejected('entity_not_found') { call('set_selection', 'mode'=>'replace', 'entity_ids'=>['999']) }
    @a.valid = false
    rejected('entity_not_found') { call('move_entities', 'delta_mm'=>[1,0,0]) }
    @a.valid, @a.type = true, 'Edge'
    rejected('unsupported_entity') { call('move_entities', 'delta_mm'=>[1,0,0]) }
  end
  def test_invalid_properties_and_ids_are_rejected_before_undo
    rejected('tag_not_found') { call('update_entity_properties', 'properties'=>{'tag'=>'missing'}) }
    rejected('material_not_found') { call('update_entity_properties', 'properties'=>{'material'=>'missing'}) }
    rejected('invalid_arguments') { call('update_entity_properties', 'properties'=>{'ruby'=>'puts 1'}) }
    rejected('invalid_arguments') { call('update_entity_properties', 'properties'=>{'hidden'=>'yes'}) }
    rejected('invalid_arguments') { call('move_entities', 'entity_ids'=>['101','101'], 'delta_mm'=>[1,0,0]) }
    assert_equal 0, @model.starts
  end
  def test_model_axes_move_through_rotated_scaled_mirrored_parent
    parent = @model.add(200)
    @model.active_path = [parent]
    @model.active_entities = SketchupDouble::Collection.new(parent.definition, [@a])
    @a.parent = parent.definition
    @model.edit_transform = Geom::Transformation.new(Matrix[[0,-3,0,100],[2,0,0,200],[0,0,-4,0],[0,0,0,1]])
    result = call('move_entities', 'expected_context'=>['200'], 'delta_mm'=>[1000,2000,-3000])
    assert_equal [3540.0,7080.0,-3000.0], result['after'][0]['model_origin_mm']
    assert_equal 1, @model.commits
    @model.undo
    assert_equal [0,0,0], @a.transformation.origin.to_a
  end
  def test_shared_and_locked_ancestors_are_rejected
    parent = @model.add(200)
    @model.active_path = [parent]
    parent.locked = true
    rejected('locked_context') { call('move_entities', 'expected_context'=>['200'], 'delta_mm'=>[1,0,0]) }
    parent.locked = false
    parent.definition.instances << Object.new
    rejected('shared_edit_context') { call('move_entities', 'expected_context'=>['200'], 'delta_mm'=>[1,0,0]) }
  end
  def test_singular_and_non_finite_moves_are_rejected
    @model.edit_transform = Geom::Transformation.new(Matrix[[0,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]])
    rejected('invalid_transform') { call('move_entities', 'delta_mm'=>[1,0,0]) }
    rejected('invalid_arguments') { call('move_entities', 'delta_mm'=>[Float::NAN,0,0]) }
    assert_equal 0, @model.starts
  end
  def test_move_failure_rolls_back_previous_targets
    @b.fail_write = :transformation
    assert_raises(RuntimeError) { call('move_entities', 'entity_ids'=>['101','102'], 'delta_mm'=>[1000,0,0]) }
    assert_equal [0,0,0], @a.transformation.origin.to_a
    assert_equal [0,0,0], @b.transformation.origin.to_a
    assert_equal 1, @model.aborts
  end
  def test_each_view_preset_and_zoom_preserve_selection_and_undo
    @model.selection.add([@a])
    %w[top front right isometric].each do |preset|
      result = call('set_view', 'preset'=>preset)
      refute result['after']['perspective']
      assert_equal preset, result['preset']
    end
    call('zoom', 'scope'=>'entities')
    assert_equal [@a], @model.active_view.last_zoom
    call('zoom', 'scope'=>'model', 'entity_ids'=>[])
    assert_equal :model, @model.active_view.last_zoom
    assert_equal [@a], @model.selection
    assert_equal 0, @model.starts
    refute @model.modified?
  end
  def test_failed_zoom_restores_camera_projection_and_height
    original = @model.active_view.camera
    original.height = 777
    @model.active_view.fail_zoom = true
    assert_raises(RuntimeError) { call('set_view', 'preset'=>'top') }
    restored = @model.active_view.camera
    assert_equal original.eye.to_a, restored.eye.to_a
    assert restored.perspective?
    assert_equal original.fov, restored.fov
  end
  def test_special_camera_is_rejected_without_change
    @model.active_view.camera.special = true
    rejected('unsupported_camera') { call('zoom', 'scope'=>'model', 'entity_ids'=>[]) }
  end
  def test_large_result_aborts_instead_of_committing
    # Enough old/new Unicode names to exceed the fixed response frame budget.
    entities = 25.times.map { |i| @model.add(300+i) }
    entities.each { |e| e.name = '🙂' * 256 }
    rejected('result_too_large') { call('update_entity_properties', 'entity_ids'=>entities.map { |e| e.persistent_id.to_s }, 'properties'=>{'name'=>'🙂' * 256}) }
    assert_equal 1, @model.aborts
    assert_equal 0, @model.commits
  end
end
