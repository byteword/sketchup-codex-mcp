# encoding: UTF-8
require 'minitest/autorun'
require_relative 'support/creation_double'
require_relative '../extension/su_pipe_probe/command_executor'

class CreationCommandsTest < Minitest::Test
  def setup
    @model = SketchupDouble::Model.new
    @source = @model.add(101)
    @executor = SUPipeProbe::CommandExecutor.new(@model)
  end
  def box(args = {})
    @executor.call('create_box', {'expected_context'=>[], 'name'=>'A동', 'origin_mm'=>[100,200,300], 'size_mm'=>[1000,2000,3000]}.merge(args))
  end
  def duplicate(args = {})
    @executor.call('duplicate_entities', {'expected_context'=>[], 'entity_ids'=>['101'], 'delta_mm'=>[1000,0,0]}.merge(args))
  end
  def rejected(code, &block)
    error = assert_raises(SUPipeProbe::CommandError, &block)
    assert_equal code, error.code
  end
  def created(data)
    @model.find_entity_by_persistent_id(data['created'].first['persistent_id'].to_i)
  end

  def test_box_has_exact_model_axis_bounds_outward_faces_and_one_undo
    @model.selection.add([@source])
    camera = @model.active_view.camera
    data = box
    group = created(data)
    assert_equal 'Group', group.typename
    assert_equal 'A동', group.name
    assert_equal [100,200,300], data['created'][0]['model_bounds']['min']
    assert_equal [1100,2200,3300], data['created'][0]['model_bounds']['max']
    assert_equal 6, group.entities.length
    assert group.manifold?
    assert_equal 'Layer0', group.layer.name
    assert group.entities.all? { |face| face.layer.name == 'Layer0' }
    center = group.definition.bounds.center.to_a
    group.entities.each do |face|
      midpoint = face.points.transpose.map { |values| values.sum / values.length.to_f }
      outward = Geom::Vector3d.new(midpoint.zip(center).map { |a,b| a-b })
      assert_operator face.normal.dot(outward), :>, 0
    end
    assert_equal [@source], @model.selection
    assert_same camera, @model.active_view.camera
    assert_equal 1, @model.commits
    @model.undo
    refute group.valid?
    assert_equal [@source], @model.entities.to_a
    refute @model.modified?
  end

  def test_previews_do_not_create_ids_definitions_or_undo_entries
    assert_equal [], box('dry_run'=>true)['planned']['parent_path']
    assert_equal [1000,0,0], duplicate('dry_run'=>true)['delta_mm']
    refute box('dry_run'=>true).key?('created')
    refute duplicate('dry_run'=>true).key?('created')
    assert_equal [@source], @model.entities.to_a
    assert_equal 1, @model.definitions.length
    assert_equal 0, @model.starts
  end

  def nested_context
    parent = @model.add(500)
    @model.active_path = [parent]
    @model.active_entities = parent.entities
    @source.parent = parent.definition
    parent.entities << @source
    @model.edit_transform = Geom::Transformation.new(Matrix[[0,-3,0,100],[2,0,0,200],[0,0,-4,0],[0,0,0,1]])
    parent
  end

  def test_box_remains_model_axis_aligned_through_rotated_mirrored_scaled_parent
    parent = nested_context
    data = box('expected_context'=>['500'])
    group = created(data)
    assert_equal parent.definition, group.parent
    assert_equal [100,200,300], data['created'][0]['model_bounds']['min']
    assert_equal [1100,2200,3300], data['created'][0]['model_bounds']['max']
    assert_equal ['500',group.persistent_id.to_s], data['created'][0]['instance_path']
    world = (@model.edit_transform * group.transformation).matrix
    assert_in_delta 1.0, world[0,0], 1e-12
    assert_in_delta 1.0, world[1,1], 1e-12
    assert_in_delta 1.0, world[2,2], 1e-12
  end

  def test_invalid_sizes_origins_and_names_fail_before_undo
    [{'size_mm'=>[0,1,1]}, {'size_mm'=>[0.9,1,1]}, {'size_mm'=>[-1,1,1]},
     {'size_mm'=>[1_000_001,1,1]}, {'origin_mm'=>[Float::INFINITY,0,0]},
     {'size_mm'=>[true,1,1]}, {'name'=>''}, {'name'=>"bad\0name"}, {'name'=>'🙂'*257}].each do |args|
      rejected('invalid_arguments') { box(args) }
    end
    assert_equal 0, @model.starts
  end

  def test_minimum_dimensions_and_zero_origin_are_supported
    data = box('origin_mm'=>[0,0,0], 'size_mm'=>[1,1,1], 'name'=>'🙂'*256)
    assert_equal [1,1,1], data['created'][0]['model_bounds']['max']
    assert created(data).manifold?
  end

  def test_face_failure_removes_new_group_and_leaves_existing_model
    @model.fail_face_after = 3
    assert_raises(RuntimeError) { box }
    assert_equal [@source], @model.entities.to_a
    assert_equal 1, @model.definitions.length
    assert_equal 1, @model.aborts
    assert_equal 0, @model.commits
    refute @model.modified?
  end

  def test_copied_group_is_independent_and_preserves_geometry_and_properties
    original = created(box)
    original.hidden = true
    original.layer = @model.layers['구조']
    original.material = @model.materials[0]
    original.set_attribute('custom','note','메모')
    original.casts_shadows = false
    data = duplicate('entity_ids'=>[original.persistent_id.to_s])
    copy = created(data)
    refute_same original.definition, copy.definition
    assert original.manifold?
    assert copy.manifold?
    assert_equal original.entities.map(&:points), copy.entities.map(&:points)
    assert_equal original.name, copy.name
    assert_equal original.layer, copy.layer
    assert_equal original.material, copy.material
    assert copy.hidden?
    refute copy.casts_shadows?
    assert_equal '메모', copy.get_attribute('custom','note')
    assert_equal [1100,200,300], data['created'][0]['model_origin_mm']
    assert_equal [100,200,300], (Geom::Point3d.new(0,0,0).transform(original.transformation).to_a.map { |n| (n*25.4).round(6) })
    @model.undo
    assert original.valid?
    refute copy.valid?
    assert_equal 1, original.definition.instances.length
  end

  def test_copied_component_shares_definition_and_keeps_instance_attributes
    source = @model.add(102,'ComponentInstance')
    source.set_attribute('dynamic_attributes', 'label', ['구조', 3, false])
    source.hidden = true
    source.casts_shadows = false
    source.receives_shadows = false
    source.layer = @model.layers['구조']
    data = duplicate('entity_ids'=>['102'], 'delta_mm'=>[0,0,0])
    copy = created(data)
    assert_same source.definition, copy.definition
    refute_equal source.persistent_id, copy.persistent_id
    assert_equal ['구조',3,false], copy.get_attribute('dynamic_attributes','label')
    refute_same source.get_attribute('dynamic_attributes','label'), copy.get_attribute('dynamic_attributes','label')
    assert copy.hidden?
    refute copy.casts_shadows?
    refute copy.receives_shadows?
    assert_equal source.layer, copy.layer
    assert_equal [0,0,0], data['created'][0]['model_origin_mm']
    @model.undo
    assert_equal 1, source.definition.instances.length
    refute copy.valid?
  end

  def test_copy_preserves_full_transform_and_model_axis_delta_inside_parent
    nested_context
    @source.transformation = Geom::Transformation.new(Matrix[[2,1,0,10],[0,-1,0,20],[0,0,3,30],[0,0,0,1]])
    before = (@model.edit_transform * @source.transformation).matrix
    data = duplicate('expected_context'=>['500'], 'delta_mm'=>[1000,2000,-3000])
    after = (@model.edit_transform * created(data).transformation).matrix
    3.times do |i|
      3.times { |j| assert_in_delta before[i,j], after[i,j], 1e-10 }
      assert_in_delta before[i,3] + [1000,2000,-3000][i]/25.4, after[i,3], 1e-10
    end
    assert_equal before, (@model.edit_transform * @source.transformation).matrix
  end

  def test_multiple_copies_undo_together_and_partial_failure_rolls_back
    @model.add(102,'ComponentInstance')
    data = duplicate('entity_ids'=>['101','102'])
    assert_equal 2, data['created'].length
    assert_equal 4, @model.entities.length
    assert_equal 1, @model.commits
    @model.undo
    assert_equal 2, @model.entities.length
    @model.fail_spawn_after = 2
    assert_raises(RuntimeError) { duplicate('entity_ids'=>['101','102']) }
    assert_equal 2, @model.entities.length
    assert_equal 1, @source.definition.instances.length
    assert_equal 1, @model.aborts
    refute @model.modified?
  end

  def test_locked_glued_stale_and_wrong_context_sources_are_rejected
    @source.locked = true
    rejected('entity_locked') { duplicate }
    @source.locked = false
    @source.glued_to = Object.new
    rejected('unsupported_glued_entity') { duplicate }
    @source.glued_to = nil
    rejected('entity_not_found') { duplicate('entity_ids'=>['999']) }
    rejected('context_mismatch') { box('expected_context'=>['999']) }
    @source.parent = Object.new
    rejected('entity_context_mismatch') { duplicate }
    assert_equal 0, @model.starts
  end

  def test_shared_or_locked_ancestor_blocks_creation_and_copy
    parent = nested_context
    parent.definition.instances << Object.new
    rejected('shared_edit_context') { box('expected_context'=>['500']) }
    rejected('shared_edit_context') { duplicate('expected_context'=>['500']) }
    parent.definition.instances.pop
    parent.locked = true
    rejected('locked_context') { box('expected_context'=>['500']) }
    assert_equal 0, @model.starts
  end

  def test_singular_parent_transform_is_rejected_before_creation
    @model.edit_transform = Geom::Transformation.new(Matrix[[0,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]])
    rejected('invalid_transform') { box }
    rejected('invalid_transform') { duplicate }
    assert_equal 0, @model.starts
  end

  def test_component_attribute_budget_rejects_without_silent_loss
    source = @model.add(102,'ComponentInstance')
    257.times { |i| source.set_attribute('custom',i.to_s,i) }
    rejected('attributes_too_large') { duplicate('entity_ids'=>['102']) }
    assert_equal 2, @model.entities.length
    assert_equal 0, @model.starts
  end

  def test_oversized_result_aborts_and_does_not_leave_copies
    @executor.stub(:instance_snapshot, {'padding'=>'🙂'*20_000,'model_origin_mm'=>[1000,0,0]}) do
      rejected('result_too_large') { duplicate }
    end
    assert_equal [@source], @model.entities.to_a
    assert_equal 1, @model.aborts
    refute @model.modified?
  end
  def test_component_attribute_write_that_silently_fails_rolls_back
    source = @model.add(102,'ComponentInstance')
    source.set_attribute('custom','note','keep')
    original_spawn = @model.method(:spawn)
    failed_spawn = lambda do |collection, type|
      entity = original_spawn.call(collection,type)
      entity.define_singleton_method(:set_attribute) { |*_args| nil }
      entity
    end
    @model.stub(:spawn,failed_spawn) do
      rejected('postcondition_failed') { duplicate('entity_ids'=>['102']) }
    end
    assert_equal 2, @model.entities.length
    assert_equal 1, source.definition.instances.length
    assert_equal 'keep', source.get_attribute('custom','note')
    assert_equal 1, @model.aborts
  end


end
