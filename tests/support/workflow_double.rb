# encoding: UTF-8
require_relative 'texture_view_double'
%w[RENDERING_OPTIONS SHADOWINFO SKETCHCS HIDDEN LAYER_VISIBILITY SECTION_PLANES].each_with_index { |key,i| Object.const_set('PAGE_USE_'+key,2**(i+1)) }
module Sketchup
  class Page;end
  class Model;VERSION_2019=19;end
  def self.is_pro?;true;end
end
module SketchupDouble
  class WorkflowPage < TestResource
    attr_accessor :transition_time,:delay_time,:include_in_animation,:style,:flags
    def initialize(name);super;@transition_time=-1;@delay_time=-1;@include_in_animation=true;@flags={};end
    %w[camera axes hidden hidden_layers rendering_options section_planes shadow_info style].each do |key|
      define_method('use_'+key+'=') { |v| @flags[key]=v }
      define_method('use_'+key+'?') { @flags[key]==true }
    end
    def include_in_animation?;@include_in_animation;end
    def use_style=(style)
      raise TypeError,'Style object required, not boolean' unless style.is_a?(WorkflowStyle)
      @style=style;@flags['style']=true;@flags['rendering_options']=true
    end
    def update(mask)
      super
      %w[camera rendering_options shadow_info axes hidden hidden_layers section_planes].each_with_index { |key,i| @flags[key]=(mask & 2**i)!=0 }
      @flags['style']=@flags['rendering_options'];@style=@model.styles.selected_style;true
    end
  end
  class WorkflowPages < Resources
    attr_accessor :selected_page,:fail_select
    attr_reader :transition_at_selection
    def add(name,flags=PAGE_USE_CAMERA)
      r=WorkflowPage.new(name);r.model=@parent;@items<<r;r.update(flags);r
    end
    def selected_page=(page)
      @transition_at_selection=page.transition_time
      raise 'Injected selection failure' if @fail_select
      @selected_page=page;@parent.active_view.camera=page.camera;true
    end
  end
  class WorkflowStyle < TestResource
    def initialize(name);super;@path='';end
  end
  class WorkflowStyles < Resources
    attr_accessor :selected_style,:active_style_changed,:fail_load
    def initialize(model);super(model,'styles');@items=[WorkflowStyle.new('Default')];@selected_style=@items[0];@active_style_changed=false;end
    def add_style(path,select)
      return false if @fail_load
      s=WorkflowStyle.new(File.basename(path,'.style'));@items<<s;@selected_style=s if select;true
    end
    def update_selected_style;@active_style_changed=false;nil;end
  end
  class Classifications < Array
    Schema=Struct.new(:name,:namespace)
    def [](key);key.is_a?(String) ? find { |s| s.name==key } : super;end
    def load_schema(path);self << Schema.new(File.basename(path,'.skc'),'urn:test');true;end
  end
  class Definition
    def classifications_data;@classifications_data ||= {};end
    def add_classification(schema,type);classifications_data[[schema,type,'Name']]='';true;end
    def remove_classification(schema,type);classifications_data.delete_if { |k,v| k[0,2]==[schema,type] };true;end
    def get_classification_value(path);classifications_data[path];end
    def set_classification_value(path,value)
      raise NotImplementedError,'Choice' if path.last=='Choice'
      return false if path.last=='Reject'
      classifications_data[path]=value;true
    end
  end
  class Definitions
    def load(path);raise 'Injected invalid SKP' if File.binread(path)=='BAD';first;end
  end
  class Model
    attr_accessor :fail_import,:export_sidecar,:export_empty,:output_race
    attr_reader :file_call
    def styles;@styles ||= WorkflowStyles.new(self);end
    def pages;@workflow_pages ||= WorkflowPages.new(self,'scenes');end
    def classifications;@classifications ||= Classifications.new([Classifications::Schema.new('IFC 2x3','urn:ifc')]);end
    def import(path,options);@file_call=[path,options];raise 'Injected import failure' if @fail_import;true;end
    def export(path,options);@file_call=[path,options];write_model_file(path);end
    def save_copy(path,*version);@file_call=[path,version];write_model_file(path);end
    def write_model_file(path)
      File.binwrite(path,@export_empty ? '' : 'test model file')
      File.binwrite(File.join(File.dirname(path),'sidecar.bin'),'sidecar') if @export_sidecar
      File.binwrite(@output_race,'someone else') if @output_race
      true
    end
    alias_method :start_before_workflow,:start_operation
    def start_operation(label,disable)
      result=start_before_workflow(label,disable)
      @operation[:classification]=definitions.map { |d| [d,Marshal.load(Marshal.dump(d.classifications_data))] };result
    end
    alias_method :restore_before_workflow,:restore
    def restore(snapshot)
      restore_before_workflow(snapshot)
      snapshot[:classification].each { |d,data| d.classifications_data.replace(data) }
    end
  end
end
