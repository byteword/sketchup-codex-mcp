# encoding: UTF-8
require 'minitest/autorun'
require 'json'
require_relative '../extension/su_pipe_probe/command_executor'
require_relative 'support/sliding_window_double'
module UI
  def self.refresh_inspectors; nil; end
end
class LibraryPlanTest < Minitest::Test
  def setup
    @model=SlidingWindowDouble::Model.new
    @model.active_view.define_singleton_method(:invalidate) { self }
    @model.materials.add('panel')
    @executor=SUPipeProbe::CommandExecutor.new(@model)
    @plan={'format_version'=>'sketchup-plan/1','units'=>'mm','root'=>'assembly',
      'nodes'=>[{'kind'=>'group','id'=>'assembly','name'=>'Panel'},
       {'kind'=>'mesh','id'=>'panel','parent'=>'assembly','name'=>'Panel',
        'points_mm'=>[[0,0,0],[1200,0,0],[1200,100,0],[0,100,0],[0,0,900],[1200,0,900],[1200,100,900],[0,100,900]],
        'faces'=>[[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]],
        'face_roles'=>Array.new(6,'panel'),'solid'=>true,'cleanup'=>'none'}],
      'assertions'=>[{'kind'=>'bounds','node'=>'assembly','min_mm'=>[0,0,0],'max_mm'=>[1200,100,900],'tolerance_mm'=>0.001},
                     {'kind'=>'solid','node'=>'panel'}]}
    @args={'expected_context'=>[],'plans'=>[@plan],'bindings'=>{'origin_mm'=>[2000,0,0],'materials'=>{'panel'=>'panel'}},'verify_only'=>false}
  end
  def execute(fields={}); @executor.call('apply_library_plan',@args.merge(fields)); end
  def test_one_operation_material_roles_bounds_and_undo
    result=execute
    assert_equal 1,@model.starts; assert_equal 1,@model.commits
    assert_equal [2000,0,0],result['plans'][0]['geometry_bounds']['min']
    assert_equal [3200,100,900],result['plans'][0]['geometry_bounds']['max']
    root=@model.find_entity_by_persistent_id(result['created'][0]['persistent_id'].to_i)
    assert_equal 1,root.entities.length
    mesh=root.entities.first; assert mesh.manifold?
    assert mesh.entities.select { |e| e.typename=='Face' }.all? { |f| f.material==@model.materials['panel'] && f.back_material==f.material }
    @model.undo; assert_empty @model.entities.to_a
  end
  def test_verify_runs_same_native_path_but_aborts
    result=execute('verify_only'=>true)
    assert result['cleanup_verified']; refute result['undoable']; assert_empty result['created']
    assert_equal 1,@model.aborts; assert_equal 0,@model.commits; assert_empty @model.entities.to_a
  end
  def test_missing_material_and_bad_parent_reject_before_operation
    @args['bindings']['materials']={}
    assert_raises(SUPipeProbe::CommandError) { execute }
    assert_equal 0,@model.starts
    @args['bindings']['materials']={'panel'=>'panel'}
    @plan['nodes'][1]['parent']='missing'
    assert_raises(SUPipeProbe::CommandError) { execute }
    assert_equal 0,@model.starts
  end
  def test_bounds_failure_rolls_back_and_preserves_replacement
    original=@model.add(101); @args['bindings']['replace_entity_id']='101'
    @plan['assertions'][0]['max_mm']=[1201,100,900]
    assert_raises(SUPipeProbe::CommandError) { execute }
    assert original.valid?; assert_equal [original],@model.entities.to_a; assert_equal 1,@model.aborts
  end
  def test_successful_replacement_undo_restores_original
    original=@model.add(101); @args['bindings']['replace_entity_id']='101'
    execute; refute original.valid?; @model.undo
    assert original.valid?; assert_equal [original],@model.entities.to_a
  end
  def test_multiple_verify_plans_one_abort
    result=execute('plans'=>[@plan,@plan],'verify_only'=>true)
    assert_equal 2,result['plans'].length; assert_equal 1,@model.starts; assert_equal 1,@model.aborts
    assert_empty @model.entities.to_a
  end
  def test_frame_cleanup_does_not_open_mesh
    @plan['nodes'][1]['cleanup']='material_safe'
    assert execute['plans'][0]['sections'][0]['solid']
  end
  def test_snapshot_fingerprint_changes_and_stale_plan_rejects_before_operation
    result=execute; root_id=result['created'][0]['persistent_id']
    query={'query'=>'target-subtree/1','instance_path'=>[root_id],'max_entities'=>100}
    snapshot=SUPipeProbe::LibrarySnapshotReader.new(@model).call(query)
    assert_operator snapshot['snapshot']['entities'].length,:>,2
    assert_equal snapshot['fingerprint'],SUPipeProbe::LibrarySnapshotReader.new(@model).call(query)['fingerprint']
    root=@model.find_entity_by_persistent_id(root_id.to_i)
    root.transformation=Geom::Transformation.translation([1,0,0])
    @args['fingerprints']=[query.merge('fingerprint'=>snapshot['fingerprint'])]
    error=assert_raises(SUPipeProbe::CommandError) { execute }
    assert_equal 'model_stale',error.code; assert_equal 1,@model.starts
  end

end
