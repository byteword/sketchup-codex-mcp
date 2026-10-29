# encoding: UTF-8
require 'minitest/autorun'
require_relative '../extension/su_pipe_probe/command_executor'
require_relative 'support/workflow_double'
class WorkflowTest < Minitest::Test
  def setup;@model=SketchupDouble::Model.new;@executor=SUPipeProbe::CommandExecutor.new(@model);end
  def call(method,args={});@executor.call(method,{'expected_context'=>[]}.merge(args));end
  def error(code)
    e=assert_raises(SUPipeProbe::CommandError) { yield };assert_equal code,e.code;e
  end
  def scene(action,options={},dry=false);call('scene',{'action'=>action,'name'=>'Full','options'=>{'scope'=>'full'}.merge(options),'dry_run'=>dry});end
  def test_full_scene_all_2019_flags_and_metadata
    r=scene('create',{'transition_seconds'=>2,'delay_seconds'=>3,'include_in_animation'=>false})
    refute r['undoable'];assert_equal %w[axes camera hidden hidden_layers rendering_options section_planes shadow_info style],r['item']['saved_properties'].sort
    refute r['item']['include_in_animation'];assert_equal 2,r['item']['transition_seconds'];assert_equal 'Default',r['item']['style_name']
    scene('update',{'description'=>'A whole scene'});assert_equal 'A whole scene',@model.pages['Full'].description
    scene('delete');assert_nil @model.pages['Full'];assert_equal 0,@model.starts
  end
  def test_full_selection_restores_timing_even_on_failure
    scene('create',{'transition_seconds'=>2});r=scene('apply')
    assert_equal 'Full',r['selected_scene'];assert_equal 0,@model.pages.transition_at_selection;assert_equal 2,@model.pages['Full'].transition_time
    @model.pages.fail_select=true;error('outcome_unknown') { scene('apply') };assert_equal 2,@model.pages['Full'].transition_time
  end
  def test_scene_dry_run_pending_style_and_legacy_protection
    scene('create',{},true);assert_equal 0,@model.pages.length
    @model.styles.active_style_changed=true;error('style_changes_pending') { scene('create') };assert_equal 0,@model.pages.length
    @model.styles.active_style_changed=false;scene('create')
    error('unsupported_scene') { call('scene',{'action'=>'delete','name'=>'Full','options'=>{}}) }
    @model.styles.active_style_changed=true;error('style_changes_pending') { scene('apply') }
    scene('apply',{'discard_style_changes'=>true});assert_equal 'Full',@model.pages.selected_page.name
  end
  def test_full_scene_rejects_action_inapplicable_options
    error('invalid_arguments') { scene('create',{'discard_style_changes'=>true}) }
    scene('create');error('invalid_arguments') { scene('apply',{'description'=>'not valid'}) }
  end
  def test_style_load_2019_boolean_and_metadata
    Dir.mktmpdir do |dir|
      path=File.join(dir,'Sketch.style');File.binwrite(path,'style fixture')
      r=call('style',{'action'=>'load','options'=>{'path'=>path,'select'=>true}})
      assert_equal 'Sketch',r['item']['name'];assert r['item']['selected'];refute r['undoable']
      call('style',{'action'=>'metadata','options'=>{'name'=>'Sketch','new_name'=>'Pen','description'=>'Test','affect_all_uses'=>true}})
      assert_equal 'Pen',@model.styles.selected_style.name
      call('style',{'action'=>'select','options'=>{'name'=>'Default'}});assert_equal 'Default',@model.styles.selected_style.name
      @model.styles.active_style_changed=true
      error('style_changes_pending') { call('style',{'action'=>'select','options'=>{'name'=>'Pen'}}) }
      error('invalid_arguments') { call('style',{'action'=>'update','options'=>{}}) }
      call('style',{'action'=>'update','options'=>{'affect_all_uses'=>true}});refute @model.styles.active_style_changed
    end
  end
  def test_style_dry_read_and_duplicate_names
    r=SUPipeProbe::ResourceReader.new(@model).call('kind'=>'styles');assert_equal 'Default',r['items'][0]['name']
    error('resource_not_found') { call('style',{'action'=>'select','options'=>{'name'=>'missing'}}) }
    @model.styles.active_style_changed=true
    call('style',{'action'=>'update','options'=>{'affect_all_uses'=>true},'dry_run'=>true});assert @model.styles.active_style_changed
  end
  def test_save_copy_no_overwrite_and_default2019
    @model.define_singleton_method(:path) { "C:/saved-model.skp" }
    Dir.mktmpdir do |dir|
      path=File.join(dir,'copy.skp');r=call('model_file',{'action'=>'save_copy','path'=>path,'options'=>{}})
      assert_equal [19],@model.file_call[1];assert_equal Digest::SHA256.file(path).hexdigest,r['sha256'];assert_equal 'C:/saved-model.skp',@model.path
      error('file_exists') { call('model_file',{'action'=>'save_copy','path'=>path,'options'=>{}}) }
      assert_equal ['copy.skp'],Dir.children(dir)
    end
  end
  def test_export_rejects_sidecars_empty_and_publish_race
    Dir.mktmpdir do |dir|
      path=File.join(dir,'drawing.dxf');args={'action'=>'export_cad','path'=>path,'options'=>{'acad_version'=>'acad_2010','edges'=>true}}
      @model.export_sidecar=true
      failure=assert_raises(SUPipeProbe::CommandError) { call('model_file',args) }
      assert_equal 'unsupported_export',failure.code
      assert_equal({'sidecar_count'=>1,'truncated'=>false,'sidecars'=>[{'name'=>'sidecar.bin','name_truncated'=>false,'directory'=>false}]},failure.details)
      assert_empty Dir.children(dir)
      @model.export_sidecar=false;@model.export_empty=true;error('export_failed') { call('model_file',args) };assert_empty Dir.children(dir)
      @model.export_empty=false;@model.output_race=path
      assert_raises(Errno::EEXIST) { call('model_file',args) };assert_equal 'someone else',File.binread(path)
      assert_equal false,@model.file_call[1][:show_summary]
    end
  end
  def test_export_sidecar_diagnostics_are_bounded_and_do_not_publish
    @model.define_singleton_method(:export) do |path,native|
      File.binwrite(path,'CAD')
      10.times { |i| File.binwrite(File.join(File.dirname(path),'sidecar-'+i.to_s+'x'*110),'data') }
      Dir.mkdir(File.join(File.dirname(path),'directory'))
      true
    end
    Dir.mktmpdir do |dir|
      failure=error('unsupported_export') { call('model_file',{'action'=>'export_cad','path'=>File.join(dir,'drawing.dxf'),'options'=>{}}) }
      assert_equal 11,failure.details['sidecar_count']
      assert failure.details['truncated']
      assert_equal 8,failure.details['sidecars'].length
      assert failure.details['sidecars'].any? { |item| item['directory'] }
      assert failure.details['sidecars'].any? { |item| item['name_truncated'] }
      assert failure.details['sidecars'].all? { |item| item['name'].length<=96 }
      assert_operator JSON.generate(failure.details).bytesize,:<=,4096
      assert_empty Dir.children(dir)
    end
  end
  def test_file_dry_run_cross_options_and_cad_import_unknown
    Dir.mktmpdir do |dir|
      path=File.join(dir,'drawing.dwg');File.binwrite(path,'CAD')
      args={'action'=>'import_cad','path'=>path,'options'=>{'preserve_origin'=>true,'import_materials'=>false}}
      call('model_file',args.merge('dry_run'=>true));assert_nil @model.file_call
      r=call('model_file',args);refute r['undoable'];assert_equal true,@model.file_call[1][:preserve_origin];assert_equal 0,@model.starts
      error('invalid_arguments') { call('model_file',args.merge('options'=>{'origin_mm'=>[0,0,0]})) }
      @model.fail_import=true;error('outcome_unknown') { call('model_file',args) }
    end
  end
  def test_skp_load_places_at_mm_origin_and_undo_preserves_existing_model
    component
    Dir.mktmpdir do |dir|
      path=File.join(dir,'source.skp');File.binwrite(path,'SKP fixture')
      args={'action'=>'import_skp','path'=>path,'options'=>{'origin_mm'=>[254,508,762],'name'=>'Imported'}}
      call('model_file',args.merge('dry_run'=>true));assert_equal 1,@model.entities.length
      r=call('model_file',args);assert r['undoable'];assert_equal 2,@model.entities.length
      instance=@model.entities.to_a.last;assert_equal 'Imported',instance.name;assert_equal [10,20,30],instance.transformation.to_a[12,3]
      @model.undo;assert_equal 1,@model.entities.length
      File.binwrite(path,'BAD');assert_raises(RuntimeError) { call('model_file',args) };assert_equal 1,@model.entities.length;assert_equal 1,@model.aborts
    end
  end
  def surface(mode='none')
    {'kind'=>'surface_mesh','grouping'=>mode,'options'=>{'points_mm'=>[[0,0,0],[100,0,0],[100,100,50],[0,100,0]],'triangles'=>[[0,1,2],[0,2,3]],'smooth'=>true}}
  end
  def test_open_surface_raw_and_single_undo
    r=call('draw_geometry',surface);assert_equal 0,r['group_count'];assert_equal 2,r['face_count'];assert r['open_surface']
    assert_equal 1,@model.starts
    diagonal=@model.entities.find { |e| e.typename=='Edge' && e.faces.length==2 };assert diagonal.soft?;assert diagonal.smooth?
    @model.undo;assert_empty @model.entities.to_a
  end
  def test_grouped_surface_dry_and_batch
    call('draw_geometry',surface('group').merge('dry_run'=>true));assert_equal 0,@model.starts
    r=call('run_batch',{'steps'=>[{'method'=>'draw_geometry','arguments'=>surface('group')}]});assert_equal 1,r['step_count'];assert_equal 1,@model.starts
    assert_equal 1,@model.entities.length;@model.undo;assert_empty @model.entities.to_a
  end
  def test_surface_rejects_bad_winding_duplicates_unused_and_tiny
    [[[0,1,2],[0,3,2]],[[0,1,2],[2,1,0]],[[0,1,2]]].each do |triangles|
      args=surface;args['options']['triangles']=triangles;error('invalid_geometry') { call('draw_geometry',args) }
    end
    args=surface;args['options']['points_mm'][2]=[50,0,0];error('invalid_geometry') { call('draw_geometry',args) };assert_equal 0,@model.starts
  end
  def test_surface_native_failure_aborts_all_created_topology
    @model.fail_face_after=2
    assert_raises(RuntimeError) { call('draw_geometry',surface) }
    assert_empty @model.entities.to_a;assert_equal 1,@model.aborts
  end
  def component
    e=@model.add(1,'ComponentInstance');[e,{'definition_id'=>'definition:'+e.definition.entityID.to_s,'schema_name'=>'IFC 2x3','type_name'=>'IfcWall','affect_all_instances'=>true}]
  end
  def test_classification_schema_query_and_definition_write_undo
    entity,args=component
    q=SUPipeProbe::NativeQueries.new(@model)
    r=q.call('query'=>'classification','options'=>{});assert_equal 'IFC 2x3',r['items'][0]['name'];refute r['type_catalog_available']
    call('classification',{'action'=>'add','options'=>args});path=['IFC 2x3','IfcWall','Name']
    set={'definition_id'=>args['definition_id'],'classification_path'=>path,'value'=>'Wall A','affect_all_instances'=>true}
    r=call('classification',{'action'=>'set_value','options'=>set});assert_equal 'Wall A',r['value']
    read={'definition_id'=>args['definition_id'],'classification_path'=>path};assert_equal 'Wall A',q.call('query'=>'classification','options'=>read)['value']
    @model.undo;assert_equal '',entity.definition.get_classification_value(path)
    call('classification',{'action'=>'remove','options'=>args});assert_nil entity.definition.get_classification_value(path)
  end
  def test_classification_locks_and_acknowledgement
    entity,args=component
    error('invalid_arguments') { call('classification',{'action'=>'add','options'=>args.merge('affect_all_instances'=>false)}) }
    entity.locked=true;error('locked_entity') { call('classification',{'action'=>'add','options'=>args}) };assert_equal 0,@model.starts
    entity.locked=false;parent=@model.add(2);parent.locked=true
    nested=@model.add_child(parent,3,'ComponentInstance');nested.instance_variable_set(:@definition,entity.definition)
    error('locked_entity') { call('classification',{'action'=>'add','options'=>args}) }
  end
  def test_classification_choice_failure_aborts_and_dry_stays_read_only
    entity,args=component;path=['IFC 2x3','IfcWall','Choice'];entity.definition.classifications_data[path]='x'
    set={'definition_id'=>args['definition_id'],'classification_path'=>path,'value'=>'y','affect_all_instances'=>true}
    call('classification',{'action'=>'set_value','options'=>set,'dry_run'=>true});assert_equal 0,@model.starts
    error('unsupported_value') { call('classification',{'action'=>'set_value','options'=>set}) };assert_equal 1,@model.aborts;assert_equal 'x',entity.definition.get_classification_value(path)
  end
  def test_classification_scalar_types_and_schema_loading
    entity,args=component;path=['IFC 2x3','IfcWall','Integer'];entity.definition.classifications_data[path]=0
    [12,2.5,true,false].each do |v|
      r=call('classification',{'action'=>'set_value','options'=>{'definition_id'=>args['definition_id'],'classification_path'=>path,'value'=>v,'affect_all_instances'=>true}})
      assert_equal v,r['value'];assert_equal v.class,r['value'].class
    end
    Dir.mktmpdir do |dir|
      file=File.join(dir,'Custom.skc');File.binwrite(file,'schema fixture')
      call('classification',{'action'=>'load_schema','options'=>{'path'=>file},'dry_run'=>true});assert_nil @model.classifications['Custom']
      r=call('classification',{'action'=>'load_schema','options'=>{'path'=>file}});refute r['undoable'];assert @model.classifications['Custom']
    end
  end
end
