# encoding: UTF-8
require 'minitest/autorun'
require_relative 'support/drawing_double'
require_relative '../extension/su_pipe_probe/command_executor'
class BasicCommandsTest < Minitest::Test
  def setup
    @model=SketchupDouble::Model.new
    @executor=SUPipeProbe::CommandExecutor.new(@model)
    @reader=SUPipeProbe::ModelReader.new(@model)
  end
  def call(method,args={}); @executor.call(method,{'expected_context'=>(@model.active_path || []).map { |e| e.persistent_id.to_s }}.merge(args)); end
  def rectangle(fields={}); call('create_rectangle',{'name'=>'面🙂','origin_mm'=>[0,0,0],'size_mm'=>[1000,2000],'plane'=>'XY'}.merge(fields)); end
  def id(result); result['created'].first['persistent_id']; end
  def info(path); @reader.call('get_entity_info',{'instance_path'=>path})['item']; end
  def close(actual,expected); assert_in_delta expected,actual,0.001; end
  def error(code)
    ex=assert_raises(SUPipeProbe::CommandError) { yield }
    assert_equal code,ex.code
  end
  def test_rectangle_planes_default_tag_area_and_single_undo
    %w[XY XZ YZ].each do |plane|
      result=rectangle('plane'=>plane,'origin_mm'=>[100,200,300])
      item=info([id(result)])
      close item['direct_geometry']['face_area_mm2'],2_000_000
      assert_equal 1,item['direct_geometry']['by_type']['Face']
      assert_equal 4,item['direct_geometry']['by_type']['Edge']
      assert_equal 'Layer0',item['tag']['name']
      @model.undo
      assert_empty @model.entities.to_a
    end
  end
  def test_circle_segments_polygonal_area_and_axes
    %w[XY XZ YZ].each do |plane|
      result=call('create_circle','name'=>'circle','origin_mm'=>[1000,2000,3000],'radius_mm'=>500,'plane'=>plane,'segments'=>16)
      item=info([id(result)])
      close item['direct_geometry']['face_area_mm2'],16*0.5*500**2*Math.sin(2*Math::PI/16)
      assert_equal 16,item['direct_geometry']['by_type']['Edge']
    end
  end
  def test_polyline_length_and_raw_edge_query
    result=call('create_polyline','name'=>'line','points_mm'=>[[100,200,300],[1100,200,300],[1100,2200,300]])
    item=info([id(result)])
    close item['direct_geometry']['edge_length_mm'],3000
    child=item['direct_children'].first
    edge=info(child['instance_path'])
    close edge['length_mm'],1000
    assert_equal [100.0,200.0,300.0],edge['endpoints_mm'].first
  end
  def test_drawing_preview_and_invalid_inputs_do_not_modify
    assert rectangle('dry_run'=>true)['dry_run']
    assert_equal 0,@model.starts
    error('invalid_arguments') { rectangle('size_mm'=>[0,1]) }
    error('invalid_arguments') { rectangle('plane'=>'AB') }
    error('invalid_arguments') { call('create_circle','name'=>'c','origin_mm'=>[0,0,0],'plane'=>'XY','radius_mm'=>true) }
    error('invalid_arguments') { call('create_polyline','name'=>'p','points_mm'=>[[0,0,0],[0,0,0]]) }
    error('invalid_arguments') { call('create_polyline','name'=>'p','points_mm'=>[[0,0,0],[0.1,0,0]]) }
    assert_empty @model.entities.to_a
  end
  def test_drawing_failure_aborts_new_group
    @model.fail_face_after=1
    assert_raises(RuntimeError) { rectangle }
    assert_empty @model.entities.to_a
    assert_equal 1,@model.aborts
  end
  def test_nested_rotated_scaled_mirrored_context_keeps_model_axis_profile
    parent=@model.add(101)
    parent.transformation=Geom::Transformation.rotation(Geom::Point3d.new(0,0,0),Geom::Vector3d.new(0,0,1),0.4)*Geom::Transformation.scaling(Geom::Point3d.new(0,0,0),-2,3,1)
    @model.active_path,@model.active_entities,@model.edit_transform=[parent],parent.entities,parent.transformation
    result=rectangle('origin_mm'=>[100,200,300])
    item=info(['101',id(result)])
    item['model_bounds']['min'].zip([100,200,300]).each { |a,b| close a,b }
    close item['direct_geometry']['face_area_mm2'],2_000_000
    edge=item['direct_children'].find { |e| e['type']=='Edge' }
    close info(edge['instance_path'])['length_mm'],1000
  end
  def test_model_axis_rotation_scale_and_undo
    entity=id(rectangle)
    call('rotate_entities','entity_ids'=>[entity],'pivot_mm'=>[0,0,0],'axis'=>[0,0,2],'angle_degrees'=>90)
    close info([entity])['model_bounds']['min'][0],-2000
    call('scale_entities','entity_ids'=>[entity],'pivot_mm'=>[0,0,0],'factors'=>[2,1,1])
    close info([entity])['model_bounds']['min'][0],-4000
    @model.undo
    close info([entity])['model_bounds']['min'][0],-2000
  end
  def test_transform_preview_noops_and_invalid_axis_scale
    entity=id(rectangle)
    starts=@model.starts
    args={'entity_ids'=>[entity],'pivot_mm'=>[0,0,0],'axis'=>[0,0,1],'angle_degrees'=>30}
    assert call('rotate_entities',args.merge('dry_run'=>true))['dry_run']
    assert call('rotate_entities',args.merge('angle_degrees'=>0))['no_change']
    error('invalid_arguments') { call('rotate_entities',args.merge('axis'=>[0,0,0])) }
    error('invalid_arguments') { call('scale_entities','entity_ids'=>[entity],'pivot_mm'=>[0,0,0],'factors'=>[1,0,1]) }
    assert_equal starts,@model.starts
  end
  def test_transform_rolls_back_after_native_setter_failure
    entity=id(rectangle)
    before=info([entity])['model_bounds']
    @model.find_entity_by_persistent_id(entity.to_i).fail_write=:transformation
    assert_raises(RuntimeError) { call('scale_entities','entity_ids'=>[entity],'pivot_mm'=>[0,0,0],'factors'=>[2,3,1]) }
    assert_equal before,info([entity])['model_bounds']
  end
  def test_transform_wire_matrices_use_mm_translation
    entity=id(rectangle('origin_mm'=>[100,200,300]))
    result=call('scale_entities','entity_ids'=>[entity],'pivot_mm'=>[100,200,300],'factors'=>[2,1,1])
    assert_equal 'mm',result['matrix_translation_unit']
    result['before'].first['local_transform'][12,3].zip([100,200,300]).each { |a,b| close a,b }
    result['planned_local_transforms'].first[12,3].zip([100,200,300]).each { |a,b| close a,b }
  end
  def test_erase_preview_lock_refusal_and_undo
    entity=id(rectangle)
    assert call('erase_entities','entity_ids'=>[entity],'dry_run'=>true)['dry_run']
    call('update_entity_properties','entity_ids'=>[entity],'properties'=>{'locked'=>true})
    error('entity_locked') { call('erase_entities','entity_ids'=>[entity]) }
    call('update_entity_properties','entity_ids'=>[entity],'properties'=>{'locked'=>false})
    assert_equal [entity],call('erase_entities','entity_ids'=>[entity])['erased_ids']
    assert_empty @model.entities.to_a
    @model.undo
    assert_equal entity,info([entity])['persistent_id']
  end
  def test_push_pull_positive_negative_and_undo
    [3000,-3000].each do |distance|
      entity=id(rectangle)
      assert call('push_pull','entity_ids'=>[entity],'distance_mm'=>distance,'dry_run'=>true)['dry_run']
      call('push_pull','entity_ids'=>[entity],'distance_mm'=>distance)
      item=info([entity])
      assert item['manifold']
      close item['model_bounds']['size'][2],3000
      @model.undo
      close info([entity])['model_bounds']['size'][2],0
    end
  end
  def test_push_pull_rejects_shared_or_nonuniform_geometry
    entity=id(rectangle)
    source=@model.find_entity_by_persistent_id(entity.to_i)
    copy=source.copy
    error('shared_definition') { call('push_pull','entity_ids'=>[entity],'distance_mm'=>1000) }
    copy.make_unique
    source.transformation=Geom::Transformation.scaling(Geom::Point3d.new(0,0,0),2,1,1)
    error('unsupported_profile_transform') { call('push_pull','entity_ids'=>[entity],'distance_mm'=>1000) }
  end
  def test_read_only_raw_face_paths_and_wrong_parent_rejection
    one,two=id(rectangle),id(rectangle)
    face=info([one])['direct_children'].find { |e| e['type']=='Face' }
    starts=@model.starts
    close info(face['instance_path'])['area_mm2'],2_000_000
    assert_raises(ArgumentError) { info([two,face['persistent_id']]) }
    assert_raises(ArgumentError) { info([]) }
    assert_equal starts,@model.starts
  end
  def test_native_suite_rolls_back_and_preserves_user_selection_camera_geometry
    old=id(rectangle('name'=>'user-owned'))
    @model.selection.add([@model.find_entity_by_persistent_id(old.to_i)])
    before=info([old])
    result=call('run_self_test','confirm_test_model'=>true)
    assert result['passed'],result.inspect
    assert result['cleanup_verified']
    refute result['individual_undo_tested']
    assert_equal 25,result['passed_count']
    assert_equal [old],@model.selection.map { |e| e.persistent_id.to_s }
    assert_equal before['model_bounds'],info([old])['model_bounds']
    assert_equal 1,@model.entities.length
  end
  def test_grouping_preserves_world_transforms_and_undo_restores_parents
    one,two=id(rectangle),id(rectangle('origin_mm'=>[3000,4000,0]))
    before=[one,two].map { |i| info([i])['model_bounds'] }
    assert call('group_entities','entity_ids'=>[one,two],'dry_run'=>true)['dry_run']
    result=call('group_entities','entity_ids'=>[one,two])
    assert_equal 1,@model.entities.length
    result['child_paths'].zip(before).each { |p,b| assert_equal b,info(p)['model_bounds'] }
    assert_raises(ArgumentError) { info([one]) }
    @model.undo
    assert_equal 2,@model.entities.length
    [one,two].zip(before).each { |i,b| assert_equal b,info([i])['model_bounds'] }
  end
  def test_make_unique_preserves_dimensions_and_separates_shared_definition
    one=id(rectangle)
    original=@model.find_entity_by_persistent_id(one.to_i)
    copy=original.copy
    assert_equal original.definition,copy.definition
    before=info([one])['model_bounds']
    call('make_unique','entity_ids'=>[one])
    refute_equal original.definition,copy.definition
    assert_equal before,info([one])['model_bounds']
    @model.undo
    assert_equal original.definition,copy.definition
  end
  def test_child_pages_include_raw_face_beyond_first_page
    entity=id(call('create_circle','name'=>'large circle','origin_mm'=>[0,0,0],'plane'=>'XY','radius_mm'=>500,'segments'=>128))
    children=[]; offset=0
    loop do
      item=@reader.call('get_entity_info',{'instance_path'=>[entity],'child_offset'=>offset,'child_limit'=>8})['item']
      children.concat(item['direct_children'])
      offset=item['next_child_offset']; break unless offset
    end
    assert_equal 129,children.length
    assert_equal 129,children.map { |e| e['persistent_id'] }.uniq.length
    face=children.find { |e| e['type']=='Face' }
    close info(face['instance_path'])['area_mm2'],128*0.5*500**2*Math.sin(2*Math::PI/128)
    assert_raises(ArgumentError) { @reader.call('get_entity_info',{'instance_path'=>[entity],'child_limit'=>true}) }
  end
  def test_suite_requires_explicit_test_target_and_preview_has_no_operation
    error('invalid_arguments') { call('run_self_test','confirm_test_model'=>false) }
    result=call('run_self_test','confirm_test_model'=>true,'dry_run'=>true)
    assert_equal 24,result['planned_checks'].length
    assert_equal 0,@model.starts
  end
  def test_suite_stops_on_failure_and_still_removes_temporary_objects
    @model.fail_face_after=1
    result=call('run_self_test','confirm_test_model'=>true)
    refute result['passed']
    assert_equal 1,result['failed_count']
    assert result['cleanup_verified']
    assert_empty @model.entities.to_a
  end
  def test_suite_failed_rollback_is_unknown_and_never_retried
    @model.define_singleton_method(:abort_operation) { false }
    error('outcome_unknown') { call('run_self_test','confirm_test_model'=>true) }
    assert_equal 1,@model.starts
  end
  def test_suite_skips_special_camera_checks_without_changing_camera
    original=@model.active_view.camera
    original.special=true
    result=call('run_self_test','confirm_test_model'=>true)
    assert result['passed']
    assert_equal 5,result['skipped_count']
    assert_same original,@model.active_view.camera
    assert result['cleanup_verified']
  end
  def test_suite_cooperative_deadline_stops_and_cleans_up
    clock=-2.0
    suite=SUPipeProbe::NativeSelfTest.new(@model,lambda { clock+=2.0 })
    result=suite.call({'confirm_test_model'=>true,'expected_context'=>[]})
    refute result['passed']
    assert result['checks'].any? { |c| c['message'].to_s.include?('budget exceeded') }
    assert result['cleanup_verified']
    assert_empty @model.entities.to_a
  end
end
