# encoding: UTF-8
require 'minitest/autorun'
require_relative '../extension/su_pipe_probe/command_executor'
require_relative 'support/extended_double'
class RawDrawingTest < Minitest::Test
  def setup
    @model=SketchupDouble::Model.new
    @executor=SUPipeProbe::CommandExecutor.new(@model)
  end
  def draw(kind,options,extra={})
    @executor.call('draw_geometry',{'expected_context'=>[],'kind'=>kind,'options'=>options}.merge(extra))
  end
  def square; [[0,0,0],[1000,0,0],[1000,1000,0],[0,1000,0]]; end
  def test_default_face_is_raw_and_one_undo
    result=draw('face',{'points_mm'=>square})
    assert_equal 'none',result['grouping']; assert_equal 0,result['group_count']
    assert @model.entities.none? { |e| e.typename=='Group' }
    assert_equal 1,@model.entities.count { |e| e.typename=='Face' }
    assert_equal 1,@model.starts; assert_equal 1,@model.commits
    @model.undo;assert_empty @model.entities.to_a
  end
  def test_group_can_still_be_requested
    result=draw('face',{'points_mm'=>square},{'grouping'=>'group'})
    assert_equal 'Group',@model.find_entity_by_persistent_id(result['created'][0]['persistent_id'].to_i).typename
  end
  def test_native_curve_and_raw_points
    draw('arc_center',{'origin_mm'=>[0,0,0],'plane'=>'XY','radius_mm'=>100,'start_degrees'=>0,'sweep_degrees'=>90,'segments'=>12})
    assert_equal 12,@model.entities.count { |e| e.typename=='Edge' }
    draw('points',{'points_mm'=>[[10,20,30]]})
    assert_equal 1,@model.entities.count { |e| e.typename=='ConstructionPoint' }
    assert @model.entities.none? { |e| e.typename=='Group' }
  end
  def test_rectangle_circle_and_polyline_do_not_group
    draw('rectangle',{'origin_mm'=>[1000,2000,0],'plane'=>'XY','size_mm'=>[100,200]})
    draw('circle',{'origin_mm'=>[0,0,0],'plane'=>'XZ','radius_mm'=>100,'segments'=>16})
    draw('polyline',{'points_mm'=>[[0,0,100],[100,0,100],[100,100,100]]})
    assert @model.entities.none? { |e| e.typename=='Group' }
    assert_equal 2,@model.entities.count { |e| e.typename=='Face' }
  end
  def test_bad_inputs_preview_and_rollback
    assert draw('face',{'points_mm'=>square},{'dry_run'=>true})['dry_run'];assert_equal 0,@model.starts
    assert_raises(SUPipeProbe::CommandError) { draw('face',{'points_mm'=>square},{'grouping'=>'invalid'}) }
    assert_raises(SUPipeProbe::CommandError) { draw('rectangle',{'origin_mm'=>[0,0,0],'plane'=>'XY','size_mm'=>[100,200],'unexpected'=>1}) }
    @model.fail_face_after=1
    assert_raises(RuntimeError) { draw('face',{'points_mm'=>square}) }
    assert_empty @model.entities.to_a
  end
  def test_typed_library_plan_draws_without_groups_and_aborts_as_one
    @model.active_view.define_singleton_method(:invalidate) { nil }
    steps=[{'method'=>'draw_geometry','arguments'=>{'kind'=>'face','options'=>{'points_mm'=>square}}},
           {'method'=>'draw_geometry','arguments'=>{'kind'=>'points','options'=>{'points_mm'=>[[1,2,3]]}}}]
    args={'expected_context'=>[],'bindings'=>{},'plans'=>[{'format_version'=>'sketchup-operations/1','units'=>'mm','steps'=>steps}]}
    result=@executor.call('apply_library_plan',args)
    assert_equal 1,@model.starts;assert_equal 1,@model.commits;assert_equal 2,result['plans'][0]['step_count']
    assert @model.entities.none? { |e| e.typename=='Group' }
    @model.undo
    result=@executor.call('apply_library_plan',args.merge('verify_only'=>true))
    assert result['cleanup_verified'];assert_empty @model.entities.to_a
  end
  def test_typed_plan_failure_rolls_back_prior_raw_geometry
    steps=[{'method'=>'draw_geometry','arguments'=>{'kind'=>'face','options'=>{'points_mm'=>square}}},
           {'method'=>'draw_geometry','arguments'=>{'kind'=>'points','options'=>{'points_mm'=>[]}}}]
    args={'expected_context'=>[],'bindings'=>{},'plans'=>[{'format_version'=>'sketchup-operations/1','units'=>'mm','steps'=>steps}]}
    assert_raises(SUPipeProbe::CommandError) { @executor.call('apply_library_plan',args) }
    assert_empty @model.entities.to_a;assert_equal 1,@model.aborts
  end

  def test_raw_root_edit_material_erase_and_undo
    id=draw('face',{'points_mm'=>square})['created'][0]['persistent_id']
    @executor.call('edit_geometry',{'expected_context'=>[],'action'=>'properties','options'=>{'entity_ids'=>[id],'material'=>'콘크리트'}})
    face=@model.find_entity_by_persistent_id(id.to_i);assert_equal '콘크리트',face.material.name
    @executor.call('edit_geometry',{'expected_context'=>[],'action'=>'erase','options'=>{'entity_ids'=>[id]}})
    refute face.valid?;@model.undo;assert face.valid?
    assert @model.entities.none? { |e| e.typename=='Group' }
  end
  def test_raw_coordinates_in_translated_edit_context
    parent=@model.add(1);parent.transformation=Geom::Transformation.translation([10,0,0])
    @model.active_path=[parent];@model.active_entities=parent.entities;@model.edit_transform=parent.transformation
    value=draw('polyline',{'points_mm'=>[[254,0,0],[279.4,0,0]]},{'expected_context'=>['1']})
    edge=@model.find_entity_by_persistent_id(value['created'][0]['persistent_id'].to_i)
    assert_in_delta 0,edge.start.position.to_a[0],1e-8;assert_in_delta 1,edge.end.position.to_a[0],1e-8
    assert_equal ['1',edge.persistent_id.to_s],value['created'][0]['instance_path']
    @model.entities.add_instance(parent.definition,parent.transformation)
    assert_raises(SUPipeProbe::CommandError) { draw('points',{'points_mm'=>[[0,0,0]]},{'expected_context'=>['1']}) }
  end

end
