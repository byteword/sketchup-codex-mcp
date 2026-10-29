# encoding: UTF-8
require 'minitest/autorun'
require 'tmpdir'
require_relative '../extension/su_pipe_probe/command_executor'
require_relative 'support/extended_double'
module Sketchup
  def self.version; '19.3.253';end
  def self.is_pro?;true;end
  Face=SketchupDouble::Face
  class ArcCurve;end
end
Sketchup::Face::PointInside=1
TextAlignLeft=0
module SketchupDouble
  class Entity
    def attribute_dictionary(name,_create=false);@attributes[name];end
    def delete_attribute(name,key);(@attributes[name] || {}).delete(key);end
  end
  class Annotation
    include Sketchup::Drawingelement
    include Primitive
    attr_accessor :layer,:text,:name,:symbol
    attr_reader :points,:arguments
    def initialize(type,arguments)
      @type,@arguments=type,arguments;@points=[[0,0,0]]
    end
    def typename;@type;end
    def activate;@parent.entities.active_section_plane=self;end
    def active?;@parent.entities.active_section_plane==self;end
    def set_plane(value);@arguments=value;end
  end
  class Collection
    attr_accessor :active_section_plane,:fail_annotation
    def make_annotation(type,args)
      made=Annotation.new(type,args);owner_model.register_primitive(made,self);@items<<made
      raise 'Injected annotation failure' if fail_annotation
      made
    end
    def add_cline(*args);make_annotation('ConstructionLine',args);end
    def add_dimension_linear(*args);make_annotation('DimensionLinear',args);end
    def add_dimension_radial(*args);make_annotation('DimensionRadial',args);end
    def add_text(*args);made=make_annotation('Text',args);made.text=args.first;made;end
    def add_section_plane(*args);make_annotation('SectionPlane',args);end
    def add_3d_text(*args);add_face([[0,0,0],[1,0,0],[0,1,0]]);true;end
  end
  class TestResource;attr_accessor :line_style;end
  class Model
    def line_styles;[Struct.new(:name).new('Dash')];end
  end
end
module SketchupDouble
  class Entity
    def volume;100.0;end
    def test_boolean(kind,other)
      @model.boolean_calls<<[kind,transformation.to_a,other.transformation.to_a]
      return nil if @model.fail_boolean
      made=@model.entities.add_instance(definition,transformation);made.make_unique
      @model.entities.erase_entities([self,other]);made
    end
    %w[union intersect subtract trim outer_shell].each { |kind| define_method(kind) { |other| test_boolean(kind,other) } }
  end
  class Behavior
    attr_accessor :is2d,:cuts_opening,:always_face_camera,:shadows_face_sun,:snapto,:no_scale_mask
    def initialize;@is2d=@cuts_opening=@always_face_camera=@shadows_face_sun=false;@snapto=@no_scale_mask=0;end
    %w[is2d cuts_opening always_face_camera shadows_face_sun no_scale_mask].each { |k| define_method(k+'?') { send(k) } }
  end
  class Definition;def behavior;@behavior ||= Behavior.new;end;end
  class Model
    attr_accessor :fail_boolean
    def boolean_calls;@boolean_calls ||= [];end
    def rendering_options;@rendering_options ||= {'RenderMode'=>3,'ModelTransparency'=>false,'BackgroundColor'=>Sketchup::Color.new(255,255,255)};end
    def shadow_info;@shadow_info ||= {'DisplayShadows'=>false,'ShadowTime'=>Time.utc(2026,1,1),'Latitude'=>0.0,'Longitude'=>0.0,'TZOffset'=>0.0};end
  end
  class View
    attr_accessor :fail_image
    def invalidate;nil;end
    def write_image(options)
      File.binwrite(options[:filename],"PNG test double bytes")
      !fail_image
    end
  end
end
class NativeFeaturesTest < Minitest::Test
  def setup;@model=SketchupDouble::Model.new;@executor=SUPipeProbe::CommandExecutor.new(@model);@query=SUPipeProbe::NativeQueries.new(@model);end
  def call(method,args);@executor.call(method,{'expected_context'=>[]}.merge(args));end
  def query(mode,options);@query.call('query'=>mode,'options'=>options);end
  def test_capabilities_and_invalid_query
    assert_includes query('capabilities',{})['batch_methods'],'annotation'
    assert_equal ['Dash'],query('capabilities',{})['line_styles']
    assert_raises(ArgumentError) { query('raycast',{'origin_mm'=>[0,0,0],'direction'=>[0,0,0]}) }
    assert_equal 0,@model.starts
  end
  def test_ray_units_path_and_hidden_flag
    group=@model.add(1)
    @model.define_singleton_method(:raytest) do |ray,visible|
      raise 'wrong units' unless (ray[0].to_a[0]-1).abs<1e-8 && ray[1].to_a==[0.0,0.0,1.0] && visible==false
      [Geom::Point3d.new(1,2,3),[group]]
    end
    hit=query('raycast',{'origin_mm'=>[25.4,0,0],'direction'=>[0,0,5],'include_hidden'=>true})
    assert_equal ['1'],hit['instance_path'];assert_in_delta 76.2,hit['point_mm'][2],1e-8
  end
  def test_metrics_parent_scale_no_double_scaling_and_budget
    parent=@model.add(1);child=@model.add_child(parent,2)
    parent.transformation=Geom::Transformation.scaling(Geom::Point3d.new(0,0,0),2,3,-4)
    child.transformation=Geom::Transformation.scaling(Geom::Point3d.new(0,0,0),5,5,5)
    child.define_singleton_method(:manifold?) { true };child.define_singleton_method(:volume) { 125.0 }
    data=query('metrics',{'instance_path'=>['1','2']})
    assert_in_delta 125*24*25.4**3,data['solid_volume_mm3'],0.001
    assert_equal 1,data['solid_count']
    child.entities.add_face([[0,0,0],[1,0,0],[0,1,0]])
    assert_raises(ArgumentError) { query('metrics',{'instance_path'=>['1','2'],'max_entities'=>1}) }
    assert_raises(ArgumentError) { query('metrics',{'instance_path'=>['2']}) }
    @model.active_path=[parent]
    assert_raises(ArgumentError) { query('metrics',{'instance_path'=>['1','2']}) }
  end
  def test_classify_transforms_from_model_coordinates
    parent=@model.add(1);parent.transformation=Geom::Transformation.translation([10,0,0])
    face=parent.entities.add_face([[0,0,0],[1,0,0],[0,1,0]])
    face.define_singleton_method(:classify_point) { |p| raise 'wrong point' unless (p.to_a[0]-0.25).abs<1e-8;1 }
    result=query('classify_point',{'instance_path'=>['1',face.persistent_id.to_s],'point_mm'=>[10.25*25.4,0.25*25.4,0]})
    assert_equal 'PointInside',result['classification']
  end
  def test_attributes_roundtrip_delete_undo_and_rejection
    e=@model.add(1);o={'entity_id'=>'1','dictionary'=>'probe.technique','key'=>'size','value_json'=>'[1200,900,100]'}
    call('entity_attributes',{'action'=>'set','options'=>o})
    assert_equal [1200,900,100],query('attributes',{'instance_path'=>['1'],'dictionary'=>'probe.technique'})['items'][0]['value']
    call('entity_attributes',{'action'=>'delete','options'=>o.reject { |k,v| k=='value_json' }})
    assert_nil e.get_attribute('probe.technique','size');@model.undo;assert_equal [1200,900,100],e.get_attribute('probe.technique','size')
    assert_raises(SUPipeProbe::CommandError) { call('entity_attributes',{'action'=>'set','options'=>o.merge('value_json'=>'{}')}) }
    e.locked=true
    assert_raises(SUPipeProbe::CommandError) { call('entity_attributes',{'action'=>'set','options'=>o}) }
  end
  def test_raw_annotations_and_dimension_inputs
    guide=call('annotation',{'kind'=>'guide','options'=>{'point_mm'=>[25.4,0,0],'direction'=>[0,1,0]}})
    id=guide['created'][0]['persistent_id'];assert_equal [1.0,0.0,0.0],@model.find_entity_by_persistent_id(id.to_i).arguments[0].to_a
    dim=call('annotation',{'kind'=>'linear_dimension','options'=>{'start_mm'=>[0,0,0],'end_mm'=>[1200,0,0],'offset_mm'=>[0,100,0]}})
    assert_equal 'none',dim['grouping'];assert @model.entities.none? { |e| e.typename=='Group' }
    count=@model.entities.length
    assert_raises(SUPipeProbe::CommandError) { call('annotation',{'kind'=>'linear_dimension','options'=>{'start_mm'=>[0,0,0],'end_mm'=>[1200,0,0],'offset_mm'=>[100,0,0]}}) }
    assert_equal count,@model.entities.length
    call('edit_annotation',{'action'=>'erase','options'=>{'entity_ids'=>[id]}});assert_equal count-1,@model.entities.length
    @model.undo;assert_equal count,@model.entities.length
  end
  def test_text_section_update_and_3d_text
    text=call('annotation',{'kind'=>'text','options'=>{'text'=>'창 1200','point_mm'=>[0,0,0]}})['created'][0]['persistent_id']
    call('edit_annotation',{'action'=>'text','options'=>{'entity_id'=>text,'text'=>'창 900'}})
    assert_equal '창 900',@model.find_entity_by_persistent_id(text.to_i).text
    section=call('annotation',{'kind'=>'section','options'=>{'point_mm'=>[0,0,0],'normal'=>[1,0,0],'active'=>true}})['created'][0]['persistent_id']
    assert @model.find_entity_by_persistent_id(section.to_i).active?
    call('edit_annotation',{'action'=>'section','options'=>{'entity_id'=>section,'active'=>false}})
    refute @model.find_entity_by_persistent_id(section.to_i).active?
    created=call('annotation',{'kind'=>'text3d','options'=>{'text'=>'ABC','origin_mm'=>[254,0,0],'height_mm'=>100}})['created'][0]
    assert_equal 'Group',created['type'];assert_equal 10,@model.find_entity_by_persistent_id(created['persistent_id'].to_i).transformation.origin.to_a[0]
  end
  def test_annotation_failure_aborts_and_preview_does_not_mutate
    assert call('annotation',{'kind'=>'text','options'=>{'text'=>'hello','point_mm'=>[0,0,0]},'dry_run'=>true})['dry_run'];assert_equal 0,@model.starts
    @model.entities.fail_annotation=true
    assert_raises(RuntimeError) { call('annotation',{'kind'=>'text','options'=>{'text'=>'hello','point_mm'=>[0,0,0]}}) }
    assert_empty @model.entities.to_a;assert_equal 1,@model.aborts
  end
  def box(x=0)
    result=call('create_box',{'name'=>'box','origin_mm'=>[x,0,0],'size_mm'=>[100,100,100]})
    @model.find_entity_by_persistent_id(result['created'][0]['persistent_id'].to_i)
  end
  def test_boolean_isolates_inputs_and_failure_rolls_back
    a=box;b=box(50);before=@model.entities.to_a
    value=call('solid_operation',{'operation'=>'subtract','target_id'=>a.persistent_id.to_s,'tool_id'=>b.persistent_id.to_s})
    assert value['inputs_preserved'];assert a.valid?;assert b.valid?;assert_equal 3,@model.entities.length
    assert_equal ['subtract',b.transformation.to_a,a.transformation.to_a],@model.boolean_calls.last
    @model.undo;assert_equal before,@model.entities.to_a
    @model.fail_boolean=true
    assert_raises(SUPipeProbe::CommandError) { call('solid_operation',{'operation'=>'union','target_id'=>a.persistent_id.to_s,'tool_id'=>b.persistent_id.to_s}) }
    assert_equal before,@model.entities.to_a
  end
  def test_intersection_transforms_and_requires_unique_target
    a=box(100);b=box(50);entities=a.entities;expected=b.transformation.inverse*a.transformation
    entities.define_singleton_method(:intersect_with) do |recursive,t1,dest,t2,hidden,cutters|
      raise 'wrong intersection context' unless recursive==false && t1.to_a==expected.to_a && t2.to_a==expected.to_a && dest==self && cutters==b.entities.to_a
      [add_line([1,1,1],[2,2,2])]
    end
    before=entities.length
    out=call('intersect_faces',{'target_id'=>a.persistent_id.to_s,'cutter_id'=>b.persistent_id.to_s})
    assert_equal 'none',out['grouping'];assert_equal before+1,entities.length
    @model.undo;assert_equal before,entities.length
    @model.entities.add_instance(a.definition,a.transformation)
    assert_raises(SUPipeProbe::CommandError) { call('intersect_faces',{'target_id'=>a.persistent_id.to_s,'cutter_id'=>b.persistent_id.to_s}) }
  end
  def test_uv_mapping_uses_face_local_points_and_rejects_shared_ancestors
    a=box(254);face=a.entities.find { |e| e.typename=='Face' };material=@model.materials[0];material.texture='test.png'
    face.define_singleton_method(:position_material) do |mat,mapping,front|
      raise 'wrong UV mapping' unless (mapping[0].to_a[0]-1).abs<1e-8 && mapping[1].to_a==[0.5,0.25,0] && front
      self.material=mat;self
    end
    args={'instance_path'=>[a.persistent_id.to_s,face.persistent_id.to_s],'material'=>material.name,'mapping'=>[{'point_mm'=>[279.4,0,0],'uv'=>[0.5,0.25]}]}
    call('face_texture',args);assert_equal material,face.material
    @model.entities.add_instance(a.definition,a.transformation)
    assert_raises(SUPipeProbe::CommandError) { call('face_texture',args) }
  end
  def test_component_opening_requires_definition_acknowledgement
    e=box;e.to_component;definition_id='definition:'+e.definition.entityID.to_s
    options={'definition_id'=>definition_id,'affect_all_instances'=>true,'is2d'=>true,'cuts_opening'=>true,'no_scale_mask'=>3}
    call('component_behavior',{'action'=>'configure','options'=>options})
    assert e.definition.behavior.cuts_opening?;assert_equal 3,e.definition.behavior.no_scale_mask?
    assert_raises(SUPipeProbe::CommandError) { call('component_behavior',{'action'=>'configure','options'=>options.merge('affect_all_instances'=>false)}) }
    assert_raises(SUPipeProbe::CommandError) { call('component_behavior',{'action'=>'configure','options'=>options.merge('is2d'=>false)}) }
  end
  def test_display_settings_and_batch_exclusion
    result=call('configure_display',{'rendering'=>{'ModelTransparency'=>true},'shadows'=>{'DisplayShadows'=>true,'ShadowTime'=>'2026-10-29T12:00:00+09:00'}})
    refute result['undoable'];assert_equal 0,@model.starts
    assert_equal true,query('display',{})['rendering']['ModelTransparency']
    assert_equal '2026-10-29T03:00:00Z',query('display',{})['shadows']['ShadowTime']
    assert_raises(SUPipeProbe::CommandError) { call('configure_display',{'shadows'=>{'ShadowTime'=>'2026-10-29T12:00:00'}}) }
    assert_raises(SUPipeProbe::CommandError) { call('run_batch',{'steps'=>[{'method'=>'configure_display','arguments'=>{'rendering'=>{'ModelTransparency'=>false}}}]}) }
  end
  def test_view_export_exclusive_write_and_failure_cleanup
    Dir.mktmpdir('probe-view-test-') do |folder|
      path=File.join(folder,'view.png')
      assert call('export_view',{'path'=>path,'dry_run'=>true})['dry_run'];refute File.exist?(path)
      result=call('export_view',{'path'=>path,'width'=>800,'height'=>600})
      assert_equal Digest::SHA256.file(path).hexdigest,result['sha256'];refute result['undoable'];assert_equal 0,@model.starts
      assert_raises(SUPipeProbe::CommandError) { call('export_view',{'path'=>path}) }
      @model.active_view.fail_image=true
      assert_raises(SUPipeProbe::CommandError) { call('export_view',{'path'=>File.join(folder,'fail.png')}) }
      assert_equal ['view.png'],Dir.children(folder)
      assert_raises(SUPipeProbe::CommandError) { call('export_view',{'path'=>File.join(folder,'..','escape.png')}) }
    end
  end

  def test_new_native_acceptance_suite_is_discoverable_without_mutation
    result=call('run_self_test',{'suite'=>'features2019','confirm_test_model'=>true,'dry_run'=>true})
    assert_includes result['planned_checks'],'raw_reuse';assert_includes result['planned_checks'],'solid_subtract'
    refute_includes result['planned_checks'],'export_view';assert_equal 0,@model.starts
  end

end
