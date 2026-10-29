# encoding: UTF-8
require 'minitest/autorun'
require 'tmpdir'
require_relative '../extension/su_pipe_probe/command_executor'
require_relative 'support/texture_view_double'
class TextureViewTest < Minitest::Test
  def setup
    @model=SketchupDouble::Model.new;@executor=SUPipeProbe::CommandExecutor.new(@model)
    @material=@model.materials[0];@material.texture='embedded.png'
  end
  def call(method,args={});@executor.call(method,{'expected_context'=>[]}.merge(args));end
  def query(kind,opts={});SUPipeProbe::NativeQueries.new(@model).call('query'=>kind,'options'=>opts);end
  def face
    group=@model.add(1);f=group.entities.add_face([[0,0,0],[10,0,0],[10,5,0],[0,5,0]])
    f.material=@material;f.back_material=@material;[group,f,[group.persistent_id.to_s,f.persistent_id.to_s]]
  end
  def camera
    {'eye_mm'=>[1000,-1000,1000],'target_mm'=>[0,0,0],'up'=>[0,0,1],'perspective'=>true}
  end
  def test_texture_snapshot_uses_world_frame_and_projective_uv
    group,f,path=face;group.transformation=Geom::Transformation.translation([20,0,0])*Geom::Transformation.scaling(Geom::Point3d.new(0,0,0),2,3,1)
    data=query('face_texture',{'instance_path'=>path})
    assert_in_delta 508,data['frame']['origin_mm'][0],1e-8
    assert_in_delta 508,data['frame']['width_mm'],1e-8
    assert_in_delta 381,data['frame']['height_mm'],1e-8
    assert_in_delta 10/1.1,data['sides']['front']['uv'][1][0],1e-8
    assert_equal 64,data['sides']['front']['texture']['image_width']
    assert_equal 0,@model.starts
  end
  def test_snapshot_fingerprint_detects_uv_and_ancestor_changes
    group,f,path=face;args={'query'=>'face-texture/1','instance_path'=>path,'max_entities'=>1}
    reader=SUPipeProbe::LibrarySnapshotReader.new(@model);initial=reader.call(args)
    f.uv_shift=0.2;refute_equal initial['fingerprint'],reader.call(args)['fingerprint']
    plan={'format_version'=>'sketchup-operations/1','units'=>'mm','steps'=>[{'method'=>'face_texture','arguments'=>{'instance_path'=>path,'action'=>'clear'}}]}
    assert_raises(SUPipeProbe::CommandError) { call('apply_library_plan',{'plans'=>[plan],'bindings'=>{},'fingerprints'=>[args.merge('fingerprint'=>initial['fingerprint'])]}) }
    assert_equal 0,@model.starts
    f.uv_shift=0;assert_equal initial['fingerprint'],reader.call(args)['fingerprint']
    group.locked=true;refute_equal initial['fingerprint'],reader.call(args)['fingerprint']
  end
  def test_clear_is_face_side_local_and_undoable
    group,f,path=face;group.material=@material
    call('face_texture',{'instance_path'=>path,'action'=>'clear','front'=>false})
    assert_nil f.back_material;assert_equal @material,f.material;assert_equal @material,group.material
    @model.undo;assert_equal @material,f.back_material
    call('face_texture',{'instance_path'=>path,'action'=>'clear','dry_run'=>true});assert_equal @material,f.material
  end
  def test_clear_rejects_shared_ancestors_and_bad_options
    group,f,path=face
    assert_raises(SUPipeProbe::CommandError) { call('face_texture',{'instance_path'=>path,'action'=>'clear','material'=>@material.name}) }
    @model.entities.add_instance(group.definition,group.transformation)
    assert_raises(SUPipeProbe::CommandError) { call('face_texture',{'instance_path'=>path,'action'=>'clear'}) }
    assert_equal 0,@model.starts
  end
  def test_face_clear_batch_rolls_back_both_sides
    _,f,path=face
    steps=[{'method'=>'face_texture','arguments'=>{'instance_path'=>path,'action'=>'clear','front'=>false}},
      {'method'=>'face_texture','arguments'=>{'instance_path'=>['99999'],'action'=>'clear'}}]
    assert_raises(SUPipeProbe::CommandError) { call('run_batch',{'steps'=>steps}) }
    assert_equal @material,f.back_material;assert_equal @material,f.material;assert_equal 1,@model.aborts
  end
  def test_material_size_remove_copy_and_undo
    @material.alpha=0.4
    copied=call('texture_resource',{'action'=>'copy','source_name'=>@material.name,'name'=>'independent'})
    copy=@model.materials['independent'];refute_same copy.texture,@material.texture
    assert_equal @material.texture.image_rep.pixels,copy.texture.image_rep.pixels
    assert_equal @material.texture.width,copy.texture.width
    call('texture_resource',{'action'=>'set_size','name'=>copy.name,'tile_size_mm'=>[300,600],'affect_all_uses'=>true})
    assert_in_delta 300/25.4,copy.texture.width,1e-8;assert_equal 10,@material.texture.width
    call('texture_resource',{'action'=>'remove_image','name'=>copy.name,'affect_all_uses'=>true})
    assert_nil copy.texture;assert_equal 0.4,copy.alpha;assert_equal @material.color,copy.color
    @model.undo;assert_in_delta 300/25.4,copy.texture.width,1e-8
    assert_equal 'new_material',copied['scope']
  end
  def test_material_file_load_and_replace_preserve_physical_size
    Dir.mktmpdir('probe-texture-') do |folder|
      path=File.join(folder,'source.png');File.binwrite(path,'test image bytes')
      result=call('texture_resource',{'action'=>'create_texture','name'=>'new','path'=>path,'tile_size_mm'=>[1200,900]})
      assert_in_delta 1200,result['item']['texture']['width_mm'],1e-8
      call('texture_resource',{'action'=>'replace_image','name'=>'new','path'=>path,'affect_all_uses'=>true})
      assert_in_delta 1200,@model.materials['new'].texture.width*25.4,1e-8
      assert_raises(SUPipeProbe::CommandError) { call('texture_resource',{'action'=>'replace_image','name'=>'new','path'=>path}) }
    end
  end
  def test_material_validation_and_size_failure_restore
    assert_raises(SUPipeProbe::CommandError) { call('texture_resource',{'action'=>'set_size','name'=>@material.name,'tile_size_mm'=>[0,50],'affect_all_uses'=>true}) }
    assert_raises(SUPipeProbe::CommandError) { call('texture_resource',{'action'=>'copy','source_name'=>@material.name,'name'=>@material.name}) }
    assert_equal 0,@model.starts
    @material.texture.fail_size=true
    assert_raises(RuntimeError) { call('texture_resource',{'action'=>'set_size','name'=>@material.name,'tile_size_mm'=>[300,600],'affect_all_uses'=>true}) }
    assert_equal 10,@material.texture.width;assert_equal 1,@model.aborts
  end
  def test_camera_keeps_aspect_and_accepts_focal_length_in_mm
    @model.active_view.camera.aspect_ratio=1.5
    call('configure_camera',camera.merge('focal_length_mm'=>50,'image_width_mm'=>36))
    assert_equal 1.5,@model.active_view.camera.aspect_ratio
    assert_in_delta 2*Math.atan(36.0/100)*180/Math::PI,@model.active_view.camera.fov,1e-8
    assert_in_delta 36,@model.active_view.camera.image_width,1e-8
    assert_raises(SUPipeProbe::CommandError) { call('configure_camera',camera.merge('focal_length_mm'=>50,'fov_degrees'=>60)) }
    assert_raises(SUPipeProbe::CommandError) { call('configure_camera',camera.merge('aspect_ratio'=>0.01)) }
    before=query('view_state')
    assert_raises(SUPipeProbe::CommandError) { call('configure_camera',camera.merge('focal_length_mm'=>1,'image_width_mm'=>1000)) }
    assert_equal before,query('view_state')
  end
  def test_saved_view_roundtrip_and_storage_undo
    before=query('view_state');call('view_preset',{'action'=>'save','name'=>'Exterior'})
    assert_equal ['Exterior'],query('view_presets')['presets'].map { |p| p['name'] }
    assert_equal before,query('view_presets',{'name'=>'Exterior'})['state']
    call('view_preset',{'action'=>'apply','state'=>{'camera'=>camera,'tags'=>[{'name'=>'구조','visible'=>false}],'shadows'=>{'DisplayShadows'=>true}}})
    refute @model.layers['구조'].visible?
    call('view_preset',{'action'=>'apply','name'=>'Exterior'})
    assert_equal before,query('view_state')
    call('view_preset',{'action'=>'delete','name'=>'Exterior'});assert_empty query('view_presets')['presets']
    @model.undo;assert_equal 1,query('view_presets')['presets'].length
  end
  def test_view_failure_after_camera_restores_camera_display_and_layers
    before=query('view_state');@model.layers['구조'].fail_visibility_once=true
    assert_raises(RuntimeError) { call('view_preset',{'action'=>'apply','state'=>{'camera'=>camera,'rendering'=>{'Texture'=>false},'tags'=>[{'name'=>'구조','visible'=>false}]}}) }
    assert_equal before,query('view_state')
  end
  def test_view_preflight_and_axes_postcondition_restoration
    before=query('view_state')
    invalid={'camera'=>camera,'tags'=>[{'name'=>'Missing','visible'=>false}]}
    assert_raises(SUPipeProbe::CommandError) { call('view_preset',{'action'=>'apply','state'=>invalid}) }
    assert_equal before,query('view_state')
    axes={'origin_mm'=>[100,200,300],'xaxis'=>[0,1,0],'yaxis'=>[-1,0,0],'zaxis'=>[0,0,1]}
    call('view_preset',{'action'=>'apply','state'=>{'axes'=>axes},'dry_run'=>true});assert_equal before,query('view_state')
    @model.axes.ignore_once=true
    assert_raises(SUPipeProbe::CommandError) { call('view_preset',{'action'=>'apply','state'=>{'axes'=>axes}}) }
    assert_equal before,query('view_state')
    call('view_preset',{'action'=>'apply','state'=>{'axes'=>axes}})
    assert_in_delta 100,@model.axes.origin.x*25.4,1e-8
  end
  def test_view_rejects_layer0_hide_bad_axes_and_special_camera
    assert_raises(SUPipeProbe::CommandError) { call('view_preset',{'action'=>'apply','state'=>{'tags'=>[{'name'=>'Layer0','visible'=>false}]}}) }
    assert_raises(SUPipeProbe::CommandError) { call('view_preset',{'action'=>'apply','state'=>{'axes'=>{'origin_mm'=>[0,0,0],'xaxis'=>[1,0,0],'yaxis'=>[1,0,0],'zaxis'=>[0,0,1]}}}) }
    @model.active_view.camera.special=true
    assert_raises(SUPipeProbe::CommandError) { call('view_preset',{'action'=>'save','name'=>'special'}) }
  end
end
