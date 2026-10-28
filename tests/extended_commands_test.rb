# encoding: UTF-8
require 'minitest/autorun'
require_relative 'support/extended_double'
require_relative '../extension/su_pipe_probe/command_executor'
class ExtendedCommandsTest < Minitest::Test
  def setup; @model=SketchupDouble::Model.new; @executor=SUPipeProbe::CommandExecutor.new(@model); @reader=SUPipeProbe::ModelReader.new(@model); end
  def call(method,fields={}); @executor.call(method,{'expected_context'=>[]}.merge(fields)); end
  def geometry(kind,options,dry=false); call('create_geometry','kind'=>kind,'name'=>'test🙂','options'=>options,'dry_run'=>dry); end
  def id(result); result['created'].first['persistent_id']; end
  def item(pid); @reader.call('get_entity_info','instance_path'=>[pid])['item']; end
  def entity(pid); @model.find_entity_by_persistent_id(pid.to_i); end
  def square; [[0,0,0],[1000,0,0],[1000,1000,0],[0,1000,0]]; end
  def raw(pid,action,options,fields={}); call('edit_geometry',{'container_id'=>pid,'action'=>action,'options'=>options}.merge(fields)); end
  def resource(kind,action,options,dry=false); call('manage_resource','kind'=>kind,'action'=>action,'options'=>options,'dry_run'=>dry); end
  def component(action,options); call('component','action'=>action,'options'=>options); end
  def error(code); e=assert_raises(SUPipeProbe::CommandError) { yield }; assert_equal code,e.code; end
  def test_geometry_uses_isolated_groups_correct_area_and_one_undo
    pid=id(geometry('offset','points_mm'=>square,'distance_mm'=>100))
    assert_in_delta 1_440_000,item(pid)['direct_geometry']['face_area_mm2'],0.001
    assert_equal 1,@model.starts; assert_equal 1,@model.commits
    assert_equal 1,@model.entities.length
    @model.undo; assert_empty @model.entities.to_a
  end
  def test_arc_modes_precision_and_bezier_endpoints
    cases=[['arc_center',{'origin_mm'=>[0,0,0],'plane'=>'XY','radius_mm'=>100,'start_degrees'=>0,'sweep_degrees'=>-90}],['arc_two_point',{'points_mm'=>[[0,0,0],[200,0,0]],'plane'=>'XY','bulge_mm'=>50}],['arc_three_point',{'points_mm'=>[[100,0,0],[0,100,0],[-100,0,0]]}],['bezier',{'points_mm'=>[[0,0,0],[100,100,0],[200,0,0]]}]]
    cases.each do |kind,o|
      pid=id(geometry(kind,o.merge('segments'=>12))); assert_equal 12,item(pid)['direct_geometry']['by_type']['Edge']
      assert_equal 0,item(pid)['direct_geometry']['by_type'].fetch('Face',0)
    end
  end
  def test_all_new_draw_kinds_and_invalid_previews
    geometry('face','points_mm'=>square); geometry('polygon','origin_mm'=>[0,0,0],'plane'=>'XZ','radius_mm'=>100,'sides'=>5)
    geometry('freehand','points_mm'=>[[0,0,0],[0,100,0],[100,100,0]])
    p=id(geometry('polyhedron','points_mm'=>[[0,0,0],[100,0,0],[0,100,0],[0,0,100]],'faces'=>[[0,2,1],[0,1,3],[1,2,3],[2,0,3]])); assert item(p)['manifold']
    p=id(geometry('revolve','points_mm'=>[[0,0,0],[100,0,0],[100,0,100],[0,0,100]],'pivot_mm'=>[0,0,0],'axis'=>[0,0,1],'sweep_degrees'=>360,'segments'=>12)); assert item(p)['manifold']
    p=id(geometry('sweep','points_mm'=>square,'path_mm'=>[[500,500,0],[500,500,1000]])); assert item(p)['manifold']
    starts=@model.starts
    error('invalid_arguments') { geometry('polygon','origin_mm'=>[0,0,0],'plane'=>'XY','radius_mm'=>10,'sides'=>true) }
    error('invalid_arguments') { geometry('face','points_mm'=>square,'arbitrary'=>1) }
    error('invalid_geometry') { geometry('arc_three_point','points_mm'=>[[0,0,0],[1,0,0],[2,0,0]]) }
    assert_equal starts,@model.starts
  end
  def test_sweep_removes_center_guide_without_removing_solid_edges
    pid=id(geometry('sweep','points_mm'=>square,'path_mm'=>[[500,500,0],[500,500,1000]]))
    group=entity(pid)
    assert group.manifold?
    assert_equal 6,group.entities.count { |e| e.typename=='Face' }
    assert_equal 12,group.entities.count { |e| e.typename=='Edge' }
    assert group.entities.select { |e| e.typename=='Edge' }.all? { |edge| edge.faces.length==2 }
    assert_equal 1,@model.commits
    @model.undo; assert_empty @model.entities.to_a
  end
  def test_sweep_keeps_guide_edges_that_form_the_solid_boundary
    pid=id(geometry('sweep','points_mm'=>square,'path_mm'=>[[0,0,0],[0,0,1000]]))
    assert item(pid)['manifold']
    assert_equal 12,entity(pid).entities.count { |e| e.typename=='Edge' }
  end
  def test_sweep_native_failure_aborts_even_when_geometry_was_created
    @model.fail_followme=true
    error('geometry_failed') { geometry('sweep','points_mm'=>square,'path_mm'=>[[500,500,0],[500,500,1000]]) }
    assert_equal 1,@model.aborts
    assert_equal 0,@model.commits
    assert_empty @model.entities.to_a
  end
  NativeLength=Struct.new(:value) do
    def <(threshold); value < threshold.to_f && (value-threshold.to_f).abs>1e-6; end
    def to_f; value.to_f; end
  end
  def with_native_length_comparison
    original=Geom::Point3d.instance_method(:distance)
    Geom::Point3d.send(:define_method,:distance) { |other| NativeLength.new(original.bind(self).call(other)) }
    yield
  ensure
    Geom::Point3d.send(:define_method,:distance,original)
  end
  def test_native_length_point_move_uses_numeric_distance
    pid=id(geometry('points','points_mm'=>[[100,200,300]]))
    point=item(pid)['direct_children'].first['persistent_id']
    refute NativeLength.new(0)<1e-7
    with_native_length_comparison { raw(pid,'move_points','entity_ids'=>[point],'delta_mm'=>[100,200,300]) }
    assert_equal [200.0,400.0,600.0],@reader.call('get_entity_info','instance_path'=>[pid,point])['item']['position_mm']
  end
  def test_native_length_vertex_move_uses_numeric_distance
    pid=id(geometry('freehand','points_mm'=>[[0,0,0],[100,0,0]]))
    edge=item(pid)['direct_children'].first['persistent_id']
    with_native_length_comparison { raw(pid,'move_vertices','vertex_moves'=>[{'edge_id'=>edge,'endpoint'=>'start','position_mm'=>[-100,0,0]}]) }
    assert_equal [-100.0,0.0,0.0],@reader.call('get_entity_info','instance_path'=>[pid,edge])['item']['endpoints_mm'].first
  end
  def test_raw_move_still_rejects_an_actual_coordinate_mismatch
    pid=id(geometry('points','points_mm'=>[[0,0,0]])); point=item(pid)['direct_children'].first['persistent_id']
    @model.ignore_vector_moves=true
    with_native_length_comparison { error('postcondition_failed') { raw(pid,'move_points','entity_ids'=>[point],'delta_mm'=>[100,0,0]) } }
    assert_equal [0.0,0.0,0.0],@reader.call('get_entity_info','instance_path'=>[pid,point])['item']['position_mm']
    assert_equal 1,@model.aborts
  end
  def test_explode_returns_only_unique_addressable_drawing_children
    pid=id(geometry('face','points_mm'=>square))
    result=component('explode','entity_ids'=>[pid])
    paths=result['result_paths']; assert_equal 5,result['result_count']
    assert_equal paths.uniq,paths
    assert paths.all? { |path| path.last.match(/\A[1-9][0-9]*\z/) }
    assert_equal %w[Edge Edge Edge Edge Face],paths.map { |path| entity(path.last).typename }.sort
    grouped=call('group_entities','entity_ids'=>paths.map(&:last))
    assert_in_delta 1_000_000,item(id(grouped))['direct_geometry']['face_area_mm2'],0.001
  end
  def test_explode_page_limit_counts_drawing_children_only
    @model.explode_internal_count=200
    pid=id(geometry('face','points_mm'=>square))
    result=component('explode','entity_ids'=>[pid])
    assert_equal 5,result['result_count']; assert_equal 5,result['result_paths'].length
    refute result['paths_truncated']
  end
  def test_drawing_api_failure_rolls_back_without_orphans
    @model.fail_face_after=1
    assert_raises(RuntimeError) { geometry('face','points_mm'=>square) }
    assert_equal 1,@model.aborts; assert_empty @model.entities.to_a
  end
  def test_component_create_replace_metadata_and_ungroup
    a=id(geometry('face','points_mm'=>square)); b=id(geometry('points','points_mm'=>[[100,100,100]]))
    c=id(component('convert','entity_ids'=>[a],'name'=>'face component')); d=('definition:'+entity(c).definition.entityID.to_s)
    copy=id(component('instantiate','definition_id'=>d,'origin_mm'=>[2000,0,0]))
    assert_same entity(c).definition,entity(copy).definition
    other=id(component('convert','entity_ids'=>[b])); before=entity(copy).transformation.to_a
    component('replace','entity_ids'=>[copy],'definition_id'=>('definition:'+entity(other).definition.entityID.to_s))
    assert_equal before,entity(copy).transformation.to_a
    assert_same entity(other).definition,entity(copy).definition
    component('metadata','definition_id'=>d,'description'=>'description','affect_all_instances'=>true)
    assert_equal 'description',entity(c).definition.description
    result=component('explode','entity_ids'=>[copy]); refute entity(copy).valid?; assert_equal 1,result['result_count']
  end
  def test_shared_component_edit_needs_confirmation_and_rejects_locked_occurrence
    c=id(component('convert','entity_ids'=>[id(geometry('face','points_mm'=>square))])); d=('definition:'+entity(c).definition.entityID.to_s)
    copy=id(component('instantiate','definition_id'=>d,'origin_mm'=>[2000,0,0]))
    error('shared_definition') { raw(c,'add_points','points_mm'=>[[1,2,3]]) }
    raw(c,'add_points',{'points_mm'=>[[1,2,3]]},'affect_all_instances'=>true)
    assert_equal 1,item(copy)['direct_geometry']['by_type']['ConstructionPoint']
    entity(copy).locked=true
    error('entity_locked') { raw(c,'add_points',{'points_mm'=>[[1,2,3]]},'affect_all_instances'=>true) }
  end
  def test_component_rejects_recursive_definition_and_wrong_target_types
    a=id(component('convert','entity_ids'=>[id(geometry('face','points_mm'=>square))])); group=entity(a)
    @model.active_path=[group]; @model.active_entities=group.entities
    error('recursive_definition') { @executor.call('component','expected_context'=>[a],'action'=>'instantiate','options'=>{'definition_id'=>('definition:'+group.definition.entityID.to_s),'origin_mm'=>[0,0,0]}) }
    @model.active_path=nil; @model.active_entities=@model.entities
    error('unsupported_entity') { component('convert','entity_ids'=>[a]) }
    error('invalid_arguments') { component('metadata','definition_id'=>('definition:'+group.definition.entityID.to_s),'description'=>'bad','affect_all_instances'=>false) }
  end
  def test_converting_one_shared_group_leaves_other_group_independent
    a=entity(id(geometry('face','points_mm'=>square))); b=a.copy
    result=component('convert','entity_ids'=>[a.persistent_id.to_s])
    assert_equal 'ComponentInstance',entity(id(result)).typename
    assert_equal 'Group',b.typename
    refute_same a.definition,b.definition
  end
  def test_raw_child_parent_checks_and_face_rebuild_reverse_and_materials
    p=id(geometry('face','points_mm'=>square)); q=id(geometry('face','points_mm'=>square)); children=item(p)['direct_children']; face=children.find { |e| e['type']=='Face' }['persistent_id']; edges=children.select { |e| e['type']=='Edge' }.map { |e| e['persistent_id'] }
    error('entity_context_mismatch') { raw(q,'erase','entity_ids'=>[face]) }
    normal=entity(face).normal.to_a
    raw(p,'reverse_faces','entity_ids'=>[face]); assert entity(face).normal.dot(Geom::Vector3d.new(normal))<0
    resource('materials','create','name'=>'paint','color_rgb'=>[10,20,30])
    raw(p,'properties','entity_ids'=>[face],'material'=>'paint','back_material'=>'paint','hidden'=>true)
    assert_equal 'paint',entity(face).material.name; assert_equal 'paint',entity(face).back_material.name; assert entity(face).hidden?
    raw(p,'erase','entity_ids'=>[face]); raw(p,'rebuild_faces','entity_ids'=>edges)
    assert_in_delta 1_000_000,item(p)['direct_geometry']['face_area_mm2'],0.001
  end
  def test_construction_point_and_vertex_model_axis_movement
    p=id(geometry('points','points_mm'=>[[0,0,0]])); entity(p).transformation=Geom::Transformation.scaling(Geom::Point3d.new(0,0,0),2,3,4)
    point=item(p)['direct_children'].first['persistent_id']; raw(p,'move_points','entity_ids'=>[point],'delta_mm'=>[100,200,300])
    data=@reader.call('get_entity_info','instance_path'=>[p,point])['item']; assert_equal [100.0,200.0,300.0],data['position_mm']
    line=id(geometry('freehand','points_mm'=>[[0,0,0],[100,0,0]])); edge=item(line)['direct_children'].first['persistent_id']
    raw(line,'move_vertices','vertex_moves'=>[{'edge_id'=>edge,'endpoint'=>'start','position_mm'=>[-100,0,0]}])
    assert_equal [-100.0,0.0,0.0],@reader.call('get_entity_info','instance_path'=>[line,edge])['item']['endpoints_mm'].first
  end
  def test_mirror_model_axis_and_camera_projection
    p=id(geometry('face','points_mm'=>square)); call('mirror_entities','entity_ids'=>[p],'axis'=>'X','pivot_mm'=>[100,0,0])
    assert_in_delta(-800,item(p)['model_bounds']['min'][0],0.001)
    fields={'eye_mm'=>[1000,-1000,1000],'target_mm'=>[0,0,0],'up'=>[0,0,1],'perspective'=>false,'height_mm'=>5000}
    result=call('configure_camera',fields); assert_equal false,result['after']['perspective']; assert_in_delta 5000,result['after']['height_mm'],0.001
    before=@executor.send(:camera_state,@model.active_view.camera)
    error('invalid_geometry') { call('configure_camera',fields.merge('target_mm'=>fields['eye_mm'])) }
    assert_equal before,@executor.send(:camera_state,@model.active_view.camera)
  end
  def test_resources_paging_modify_purge_and_protected_tag
    resource('tags','create','name'=>'A'); resource('tags','create','name'=>'B')
    page=@reader.call('get_resources','kind'=>'tags','limit'=>1); assert_equal 1,page['next_offset']; assert_equal 'Layer0',page['items'].first['name']
    resource('tags','update','name'=>'A','new_name'=>'C','visible'=>false); refute @model.layers['C'].visible?
    p=id(geometry('face','points_mm'=>square)); entity(p).layer=@model.layers['C']; resource('tags','delete','name'=>'C'); assert_equal @model.layers[0],entity(p).layer
    error('protected_resource') { resource('tags','delete','name'=>'Layer0') }
    error('invalid_arguments') { resource('materials','purge_unused','confirm_model_wide'=>false) }
    resource('materials','create','name'=>'unused material'); resource('materials','purge_unused','confirm_model_wide'=>true); refute @model.materials['unused material']
    error('resource_exists') { resource('tags','create','name'=>'B') }
  end
  def test_resource_failure_rolls_back_created_or_deleted_items
    resource('materials','create','name'=>'paint'); @model.materials.fail_remove=true
    assert_raises(RuntimeError) { resource('materials','delete','name'=>'paint') }; assert @model.materials['paint']
    assert_equal 1,@model.aborts
  end
  def test_resource_pages_respect_utf8_budget_without_2019_persistent_ids
    25.times do |i|
      pid=id(geometry('points','points_mm'=>[[i,0,0]]))
      entity(pid).definition.description='🙂'*1024
    end
    args={'kind'=>'definitions','limit'=>25}; page=@reader.call('get_resources',args)
    assert_operator JSON.generate(page).bytesize,:<,40_000
    assert_operator page['next_offset'],:>,0
    assert_operator page['items'].length,:<,25
    all=page['items']; while page['next_offset']; page=@reader.call('get_resources',args.merge('offset'=>page['next_offset'])); all+=page['items']; end
    assert_equal 25,all.length
    assert_equal 25,all.map { |r| r['definition_id'] }.uniq.length
  end
  def test_scene_camera_only_lifecycle_and_conservative_failure
    call('scene','action'=>'create','name'=>'S','options'=>{})
    call('scene','action'=>'update','name'=>'S','options'=>{'new_name'=>'T','description'=>'camera only'})
    assert_equal 'camera only',@model.pages['T'].description
    call('scene','action'=>'apply','name'=>'T','options'=>{})
    refute call('scene','action'=>'delete','name'=>'T','options'=>{})['undoable']; refute @model.pages['T']
    call('scene','action'=>'create','name'=>'failure','options'=>{}); @model.pages.fail_remove=true
    error('outcome_unknown') { call('scene','action'=>'delete','name'=>'failure','options'=>{}) }
  end
  def test_smoothing_and_simplify_reject_boundaries_without_mutation
    p=id(geometry('face','points_mm'=>square)); edge=item(p)['direct_children'].find { |e| e['type']=='Edge' }['persistent_id']; starts=@model.starts
    error('unsupported_profile') { raw(p,'simplify','entity_ids'=>[edge]) }; assert_equal starts,@model.starts
    raw(p,'soften','entity_ids'=>[edge],'angle_degrees'=>30); refute entity(edge).soft?
    entity(edge).soft=true; entity(edge).smooth=true
    raw(p,'unsoften','entity_ids'=>[edge]); refute entity(edge).soft?; refute entity(edge).smooth?
  end
  def test_simplify_preserves_coplanar_surface_area
    p=id(geometry('face','points_mm'=>square.first(3)))
    raw(p,'add_face','points_mm'=>[square[0],square[2],square[3]])
    edge=entity(p).entities.find { |e| e.typename=='Edge' && e.faces.length==2 }
    raw(p,'simplify','entity_ids'=>[edge.persistent_id.to_s])
    assert_in_delta 1_000_000,item(p)['direct_geometry']['face_area_mm2'],0.001
  end
  def test_extended_suite_preview_contains_all_new_function_checks
    result=call('run_self_test','suite'=>'all','confirm_test_model'=>true,'dry_run'=>true)
    assert_equal 55,result['planned_checks'].length
    assert_includes result['planned_checks'],'shared_component_edit'
    assert_includes result['planned_checks'],'surface_simplify'
    assert_equal 0,@model.starts
  end
  def test_full_native_suite_dispatch_and_cleanup_with_api_doubles
    result=call('run_self_test','suite'=>'all','confirm_test_model'=>true)
    assert result['passed'],result['checks'].select { |c| c['status']=='failed' }.inspect
    assert_equal 56,result['passed_count']
    assert result['cleanup_verified']; assert_empty @model.entities.to_a
  end
end
