# encoding: UTF-8
require 'minitest/autorun'
require 'json'
require_relative '../extension/su_pipe_probe/command_executor'
require_relative 'support/sliding_window_double'
module UI
  def self.refresh_inspectors; @refreshes=(@refreshes || 0)+1; end
  def self.refreshes; @refreshes || 0; end
end
class SlidingWindowTest < Minitest::Test
  def setup
    @model=SlidingWindowDouble::Model.new
    @model.active_view.define_singleton_method(:invalidate) { self }
    @materials={'frame'=>'white','glass'=>'glass','seal'=>'seal','hardware'=>'dark'}
    @materials.each_value { |name| @model.materials.add(name) }
    @model.materials['glass'].alpha=0.3
    @executor=SlidingWindowDouble::Executor.new(@model)
    @args={'expected_context'=>[],'name'=>'Window','origin_mm'=>[2000,0,0],'width_mm'=>1200,'height_mm'=>900,'depth_mm'=>100,'materials'=>@materials}
  end
  def plan(fields={}); SUPipeProbe::SlidingWindowPlan.build(@args.merge(fields)); end
  def create(fields={}); @executor.call('create_sliding_window',@args.merge(fields)); end
  def test_default_recipe_preserves_dimensions_clearance_and_outer_pulls
    p=plan
    assert_equal [1200,900,100],p['size_mm']; assert_equal [1200,100,900],p['size_axes_xyz_mm']
    assert_equal [575,810,24],p['leaf_size_mm']; assert_equal 535,p['travel_mm']
    assert_equal 4,p['group_count']; assert_equal 12,p['sash_depth_gap_mm']
    assert_equal [64,78,78],p['sections'].map { |s| s['faces'].length }
    left,right=p['sections'][1..2].map { |s| s['handle_bounds'] }
    assert_equal [56,20,405],left['min']; [1144,59,495].zip(right['max']).each { |a,b| assert_in_delta a,b,1e-8 }
    assert_operator left['max'][0],:<,100
    assert_operator right['min'][0],:>,1100
  end
  def test_default_geometry_matches_the_actual_optimized_063_prototype
    prototype=JSON.parse(File.read(File.join(__dir__,'fixtures/sliding-window-prototype.json'),:encoding=>'UTF-8'))
    canonical=lambda do |mesh|
      mesh['faces'].each_with_index.map do |face,i|
        [mesh['roles'][i],face.map { |j| mesh['points'][j].map { |v| (v*10000).round } }.sort]
      end.sort_by { |value| JSON.generate(value) }
    end
    plan['sections'].zip(prototype).each do |current,expected|
      assert_equal expected['section'],current['section']
      assert_equal canonical.call(expected),canonical.call(current)
    end
  end
  def test_varied_sizes_have_closed_oriented_meshes_and_finite_coordinates
    [[600,400,80],[900,1800,150],[1500,1200,100],[6000,3600,300]].each do |w,h,d|
      p=plan('width_mm'=>w,'height_mm'=>h,'depth_mm'=>d)
      p['sections'].each do |s|
        assert SUPipeProbe::SlidingWindowPlan.validate_mesh(s)
        assert s['points'].flatten.all? { |v| v.finite? }
        s['faces'].each { |f| @executor.send(:planar_polygon,f.map { |i| s['points'][i] }) }
      end
    end
  end
  def test_opening_moves_only_the_requested_sash_within_track_extent
    closed=plan; opened=plan('open_sash'=>'left','open_fraction'=>0.5)
    assert_equal closed['sections'][0],opened['sections'][0]
    assert_equal closed['sections'][2],opened['sections'][2]
    closed['sections'][1]['points'].zip(opened['sections'][1]['points']).each do |a,b|
      assert_in_delta 267.5,b[0]-a[0],1e-8; assert_equal a[1..2],b[1..2]
    end
    full=plan('open_sash'=>'right','open_fraction'=>1)
    assert_in_delta closed['sections'][1]['points'].map(&:first).min,full['sections'][2]['points'].map(&:first).min,1e-8
  end
  def test_invalid_combinations_fail_before_creating_an_operation
    [{'width_mm'=>true},{'depth_mm'=>79},{'frame_width_mm'=>100,'height_mm'=>400,'sash_width_mm'=>80},
     {'depth_mm'=>80,'glass_thickness_mm'=>12},{'overlap_mm'=>100},{'open_fraction'=>0.5},
     {'open_sash'=>'both'},{'glass_thickness_mm'=>Float::NAN}].each do |fields|
      assert_raises(SUPipeProbe::CommandError) { create(fields) }
    end
    assert_equal 0,@model.starts; assert_empty @model.entities.to_a
  end
  def test_preview_allocates_no_entities_or_undo_and_resolves_materials
    result=create('dry_run'=>true)
    assert result['dry_run']; refute result['undoable']
    assert_equal 220,result['planned']['initial_face_count']
    assert_equal 0,@model.starts; assert_empty @model.entities.to_a
    assert_raises(SUPipeProbe::CommandError) { create('materials'=>@materials.merge('glass'=>'missing')) }
    assert_equal 0,@model.starts
  end
  def test_builder_creates_four_groups_and_one_undo_with_internal_face_materials
    before=UI.refreshes; result=create
    assert_equal 1,@model.starts; assert_equal 1,@model.commits
    assert_equal 3,@executor.optimized_sections.length
    assert_equal before+1,UI.refreshes; assert result['ui_update']['operation_closed']
    root=@model.find_entity_by_persistent_id(result['created'].first['persistent_id'].to_i)
    assert_equal 3,root.entities.length
    assert_equal [2000,0,0],result['created'].first['model_bounds']['min']
    assert_equal [3200,100,900],result['created'].first['model_bounds']['max']
    result['sections'].each do |s|
      assert_equal [root.persistent_id.to_s,s['persistent_id']],s['instance_path']
      child=@model.find_entity_by_persistent_id(s['persistent_id'].to_i)
      assert child.manifold?
      assert_equal 0,child.entities.count { |e| %w[Group ComponentInstance].include?(e.typename) }
      next if s['section']=='fixed'
      assert_equal 6,child.entities.count { |e| e.typename=='Face' && e.material==@model.materials['glass'] && e.back_material==e.material }
      assert_equal 5,child.entities.count { |e| e.typename=='Face' && e.material==@model.materials['dark'] }
    end
    @model.undo; assert_empty @model.entities.to_a
  end
  def test_replacement_is_atomic_and_undo_restores_original
    original=@model.add(101); result=create('replace_entity_id'=>'101')
    refute original.valid?; assert_equal 1,@model.entities.length
    @model.undo
    assert original.valid?; assert_equal [original],@model.entities.to_a
    removed=@model.find_entity_by_persistent_id(result['created'].first['persistent_id'].to_i)
    assert removed.nil? || !removed.valid?
  end
  def test_locked_replacement_is_rejected_before_operation
    original=@model.add(101); original.locked=true
    assert_raises(SUPipeProbe::CommandError) { create('replace_entity_id'=>'101') }
    assert_equal 0,@model.starts; assert original.valid?
  end
  def test_face_failure_aborts_new_window_and_preserves_replacement
    original=@model.add(101); @model.fail_face_after=12
    assert_raises(RuntimeError) { create('replace_entity_id'=>'101') }
    assert_equal 1,@model.aborts; assert_equal 0,@model.commits
    assert original.valid?; assert_equal [original],@model.entities.to_a
  end
  def test_recipe_budget_aborts_every_created_section
    slow=Class.new(SlidingWindowDouble::Executor) { def window_clock; @clock=(@clock || 0)+1.0; end }.new(@model)
    e=assert_raises(SUPipeProbe::CommandError) { slow.call('create_sliding_window',@args) }
    assert_equal 'recipe_budget_exceeded',e.code; assert_equal 1,@model.aborts
    assert_empty @model.entities.to_a
  end
  def split_cube
    result=@executor.call('create_box',{'expected_context'=>[],'name'=>'cube','origin_mm'=>[0,0,0],'size_mm'=>[100,100,100]})
    group=@model.find_entity_by_persistent_id(result['created'].first['persistent_id'].to_i)
    face=group.entities.find { |e| e.typename=='Face' }; points=face.points.map(&:dup)
    group.entities.erase_entities([face])
    group.entities.add_face(points.first(3)); group.entities.add_face([points[0],points[2],points[3]])
    group
  end
  def test_native_optimizer_removes_an_untextured_coplanar_edge
    group=split_cube
    result=SUPipeProbe::CommandExecutor.new(@model).send(:window_optimize,group,Process.clock_gettime(Process::CLOCK_MONOTONIC))
    assert_equal 1,result['removed_coplanar_edges']; assert_equal 0,result['hidden_textured_seams']
    assert group.manifold?; assert_equal 6,group.entities.count { |e| e.typename=='Face' }
  end
  def test_native_optimizer_preserves_textured_uv_regions_and_hides_only_seam
    group=split_cube; group.material=@model.materials['white']; group.material.texture=Object.new
    result=SUPipeProbe::CommandExecutor.new(@model).send(:window_optimize,group,Process.clock_gettime(Process::CLOCK_MONOTONIC))
    assert_equal 0,result['removed_coplanar_edges']; assert_equal 1,result['hidden_textured_seams']
    assert group.manifold?; assert_equal 7,group.entities.count { |e| e.typename=='Face' }
  end
end
