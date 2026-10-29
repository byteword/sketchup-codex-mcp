# encoding: UTF-8
require 'minitest/autorun'
require_relative '../extension/su_pipe_probe/command_executor'
require_relative 'support/file_style_double'
class FileStyleTest < Minitest::Test
  def setup
    @model=SketchupDouble::Model.new;@executor=SUPipeProbe::CommandExecutor.new(@model)
    Sketchup.file_style_version='19.3.0';Sketchup.file_style_pro=true
    @dir=Dir.mktmpdir('probe-file-tests-')
  end
  def teardown;FileUtils.remove_entry(@dir);end
  def call(method,args);@executor.call(method,{'expected_context'=>[]}.merge(args));end
  def file(action,name,options={},dry=false);call('model_file',{'action'=>action,'path'=>File.join(@dir,name),'options'=>options,'dry_run'=>dry});end
  def style(action,options={},dry=false);call('style',{'action'=>action,'options'=>options,'dry_run'=>dry});end
  def error(code)
    e=assert_raises(SUPipeProbe::CommandError) { yield };assert_equal code,e.code
  end
  def add_style(name)
    p=File.join(@dir,name+'.style');File.binwrite(p,'style fixture');style('load',{'path'=>p});@model.styles[name]
  end
  def test_unsaved_copy_rejected_before_file_io_including_preview
    [true,false].each { |dry| error('model_unsaved') { file('save_copy','unsaved.skp',{},dry) } }
    assert_nil @model.file_call
    assert_empty Dir.children(@dir)
    assert_equal 0,@model.starts
  end
  def test_2019_missing_style_path_and_gated_lifecycle
    r=SUPipeProbe::ResourceReader.new(@model).call('kind'=>'styles');assert_nil r['items'][0]['path']
    support=SUPipeProbe::NativeQueries.new(@model).call('query'=>'file_style_support','options'=>{})
    refute support['native_style_duplicate'];refute support['native_style_delete'];refute support['native_style_path'];assert support['style_purge_unused']
    error('unsupported_version') { style('duplicate',{'name'=>'Default','new_name'=>'Copy'}) }
    add_style('Unused');error('unsupported_version') { style('delete',{'name'=>'Unused'}) }
    assert_equal 2,@model.styles.length
  end
  def test_purge_keeps_selected_and_scene_references
    used=add_style('Scene style');add_style('Unused');page=@model.pages.add('A');page.use_style=used
    style('purge_unused',{'confirm_model_wide'=>true},true);assert_equal 3,@model.styles.length
    r=style('purge_unused',{'confirm_model_wide'=>true});assert_equal 1,r['removed_count'];assert_equal 'Unused',r['removed'][0]['name']
    assert_equal used,page.style;assert_equal 'Default',@model.styles.selected_style.name;assert_equal 0,@model.starts
  end
  def test_purge_requires_confirmation_and_committed_style
    error('invalid_arguments') { style('purge_unused',{'confirm_model_wide'=>false}) }
    @model.styles.active_style_changed=true;error('style_changes_pending') { style('purge_unused',{'confirm_model_wide'=>true}) }
    @model.styles.active_style_changed=false;@model.styles.fail_purge=true
    error('outcome_unknown') { style('purge_unused',{'confirm_model_wide'=>true}) }
  end
  def enable_modern
    styles=@model.styles
    styles.define_singleton_method(:remove_style) { |s| remove(s);nil }
    styles.each do |source|
      source.define_singleton_method(:duplicate) { copy=SketchupDouble::WorkflowStyle.new(name+' copy');styles.instance_variable_get(:@items)<<copy;copy }
    end
  end
  def test_modern_duplicate_and_safe_delete
    enable_modern;r=style('duplicate',{'name'=>'Default','new_name'=>'Copy','select'=>true})
    assert_equal 'Copy',r['item']['name'];assert_equal 'Copy',@model.styles.selected_style.name
    error('style_in_use') { style('delete',{'name'=>'Copy'}) }
    page=@model.pages.add('A');page.use_style=@model.styles['Default']
    error('style_in_use') { style('delete',{'name'=>'Default'}) }
    page.use_style=@model.styles['Copy'];r=style('delete',{'name'=>'Default'});assert_equal 1,r['removed_count'];assert_equal 1,@model.styles.length
  end
  def test_settings_file_roundtrip_and_current_style_identity
    path=File.join(@dir,'display.json');selected=@model.styles.selected_style
    style('export_settings',{'path'=>path,'name'=>'외관','include_shadows'=>true})
    @model.rendering_options['RenderMode']=0;@model.shadow_info['Light']=10
    r=style('import_settings',{'path'=>path},true);assert_equal 0,@model.rendering_options['RenderMode'];assert r['dry_run']
    r=style('import_settings',{'path'=>path});assert_equal '외관',r['name'];assert_equal 3,@model.rendering_options['RenderMode'];assert_equal 80,@model.shadow_info['Light'];assert_equal selected,@model.styles.selected_style
    error('file_exists') { style('export_settings',{'path'=>path}) }
  end
  def test_settings_file_rejects_foreign_fields_invalid_types_and_large_input
    path=File.join(@dir,'bad.json')
    ["{bad",JSON.generate('format_version'=>'probe-display/1','name'=>'X','rendering'=>{},'ruby'=>'evil'),JSON.generate('format_version'=>'probe-display/1','name'=>'X','rendering'=>{'Texture'=>'yes'})].each do |text|
      File.binwrite(path,text);assert_raises(SUPipeProbe::CommandError) { style('import_settings',{'path'=>path}) }
      assert_equal true,@model.rendering_options['Texture']
    end
    File.binwrite(path,' '*16_385);error('resource_too_large') { style('import_settings',{'path'=>path}) }
  end
  def test_settings_import_restores_after_partial_failure
    path=File.join(@dir,'settings.json');File.binwrite(path,JSON.generate('format_version'=>'probe-display/1','name'=>'X','rendering'=>{'RenderMode'=>1,'Texture'=>false}))
    values=@model.rendering_options
    values.define_singleton_method(:[]=) { |key,v| if key=='Texture' && v==false;raise 'Injected setting failure';end;super(key,v) }
    assert_raises(RuntimeError) { style('import_settings',{'path'=>path}) };assert_equal 3,values['RenderMode'];assert_equal true,values['Texture']
  end
  def source
    e=@model.add(1,'ComponentInstance');e.transformation=Geom::Transformation.translation([10,20,30]);e.name='Source';e.material=@model.materials[0];e.set_attribute('export','note','preserved');e
  end
  def test_selection_skp_uses_temp_definition_and_restores_originals
    e=source;@model.selection.add([e]);r=file('export_selection_skp','selection.skp',{'entity_ids'=>['1']})
    assert r['model_unchanged'];refute r['undoable'];assert_equal 1,@model.entities.length;assert_equal 1,@model.definitions.length
    assert_equal [e],@model.selection.to_a;assert_equal '',e.definition.path;assert_equal 1,@model.aborts;assert_equal 0,@model.commits
    content=JSON.parse(File.binread(File.join(@dir,'selection.skp'))).first
    assert_equal 'Source',content['name'];assert_equal 'preserved',content['attributes'];assert_equal [10,20,30],content['transform'][12,3]
  end
  def test_selection_local_coordinates_and_dry
    source;r=file('export_selection_skp','selection.skp',{'entity_ids'=>['1'],'coordinates'=>'first_local'},true)
    assert r['dry_run'];assert_equal 0,@model.starts;refute File.exist?(File.join(@dir,'selection.skp'))
    file('export_selection_skp','selection.skp',{'entity_ids'=>['1'],'coordinates'=>'first_local'})
    content=JSON.parse(File.binread(File.join(@dir,'selection.skp'))).first;assert_equal [0,0,0],content['transform'][12,3]
    error('invalid_arguments') { file('export_selection_skp','version.skp',{'entity_ids'=>['1'],'version'=>'2019'}) }
  end
  def test_selection_failed_save_cleans_temp_and_does_not_publish
    source;@model.fail_selection_export=true
    assert_raises(RuntimeError) { file('export_selection_skp','selection.skp',{'entity_ids'=>['1']}) }
    assert_equal 1,@model.entities.length;assert_empty Dir.children(@dir);assert_equal 1,@model.aborts
  end
  def test_selection_cleanup_mismatch_prevents_publish
    @model.corrupt_export_source=source
    error('outcome_unknown') { file('export_selection_skp','selection.skp',{'entity_ids'=>['1']}) }
    assert_empty Dir.children(@dir)
  end
  def test_ifc_legacy_full_type_filter_and_modern_option_gate
    file('export_ifc','all.ifc');assert_equal 26,@model.file_call[1][:ifc_types].length;assert_equal false,@model.file_call[1][:show_summary]
    error('invalid_arguments') { file('export_ifc','empty.ifc',{'ifc_types'=>[]}) }
    error('invalid_arguments') { file('export_ifc','new.ifc',{'ifc_version'=>'IFC 4'}) }
    Sketchup.file_style_version='26.0';file('export_ifc','modern.ifc',{'ifc_version'=>'IFC 4','tessellated_geometry'=>true})
    assert_equal false,@model.file_call[1][:selectionset_only];assert_equal 'IFC 4',@model.file_call[1][:ifc_version]
    error('invalid_arguments') { file('export_ifc','old.ifc',{'ifc_types'=>['IfcWall']}) }
  end
  def test_ifc_import_dry_pro_guard_and_partial_failure
    File.binwrite(File.join(@dir,'in.ifc'),'IFC');r=file('import_ifc','in.ifc',{},true);assert r['dry_run'];assert_nil @model.file_call
    Sketchup.file_style_pro=false;error('pro_required') { file('import_ifc','in.ifc') }
    Sketchup.file_style_pro=true;file('import_ifc','in.ifc');assert_equal({:show_summary=>false},@model.file_call[1])
    @model.fail_import=true;error('outcome_unknown') { file('import_ifc','in.ifc') }
  end
  def line(a,b,entities=@model.entities);entities.add_line(a,b);end
  def dxf_lines(name)
    pairs=File.binread(File.join(@dir,name)).split(/\r?\n/).each_slice(2).map { |k,v| [k.to_i,v] };lines=[];active=nil
    pairs.each do |k,v|
      if k==0;active=v=='LINE' ? {} : nil;lines<<active if active
      elsif active;active[k]=v;end
    end
    lines
  end
  def test_dxf_projection_units_nested_transform_and_duplicate_collapse
    g=@model.add(1);g.transformation=Geom::Transformation.translation([10,20,30]);line([0,0,0],[1,2,3],g.entities)
    line([10,20,0],[11,22,0]);line([10,20,0],[10,20,5])
    r=file('export_dxf2d','plan.dxf',{'plane'=>'XY','origin_mm'=>[254,508,0]});assert_equal 1,r['line_count'];refute r['hidden_line_removal'];assert_equal 0,@model.starts
    record=dxf_lines('plan.dxf').first;assert_equal [0,0,25.4,50.8],[10,20,11,21].map { |k| record[k].to_f }
    assert_includes File.binread(File.join(@dir,'plan.dxf')),"$INSUNITS\r\n70\r\n4"
  end
  def test_dxf_hidden_soft_filters_explicit_face_and_non_pro
    Sketchup.file_style_pro=false;g=@model.add(1);g.hidden=true;line([0,0,0],[1,0,0],g.entities)
    e=line([0,1,0],[1,1,0]);e.soft=true
    error('empty_export') { file('export_dxf2d','empty.dxf',{'plane'=>'XY'}) }
    r=file('export_dxf2d','all.dxf',{'plane'=>'XY','include_hidden'=>true,'include_soft'=>true});assert_equal 2,r['line_count']
    f=@model.entities.add_face([[0,0,0],[1,0,0],[0,0,1]]);f.layer=@model.layers[0]
    r=file('export_dxf2d','face.dxf',{'plane'=>'XZ','entity_ids'=>[f.persistent_id.to_s]},true);assert_equal 3,r['line_count'];refute File.exist?(File.join(@dir,'face.dxf'))
  end
  def test_dxf_line_budget_and_broken_path_leave_no_files
    edges=5001.times.map { |i| SketchupDouble::Edge.new([0,i,0],[1,i,0]).tap { |e| e.layer=@model.layers[0] } }
    @model.entities.replace(edges)
    error('query_budget_exceeded') { file('export_dxf2d','too-many.dxf',{'plane'=>'XY'}) };assert_empty Dir.children(@dir)
    error('invalid_arguments') { file('export_dxf2d','bad.dxf',{'plane'=>'camera'}) }
  end
end
