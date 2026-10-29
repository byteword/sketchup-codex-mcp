# encoding: UTF-8
require_relative 'workflow_double'
module Sketchup
  class << self;attr_accessor :file_style_version,:file_style_pro;end
  def self.version;@file_style_version || '19.3.0';end
  def self.is_pro?;@file_style_pro!=false;end
end
module SketchupDouble
  class Definition
    attr_writer :path,:guid
    def path;@path || '';end
    def guid;@guid || 'definition-guid-'+entityID.to_s;end
    def save_as(path)
      owner=instances.first.parent
      records=entities.map { |e| {'name'=>e.name,'definition_id'=>e.definition.entityID,'transform'=>e.transformation.to_a.map(&:to_f),'material'=>e.material && e.material.name,'hidden'=>e.hidden?,'locked'=>e.locked?,'attributes'=>e.get_attribute('export','note')} }
      File.binwrite(path,JSON.generate(records));@path=path;@guid='exported-temporary-guid'
      if owner.corrupt_export_source;owner.corrupt_export_source.definition.path='unexpected-path';end
      raise 'Injected SKP write failure' if owner.fail_selection_export
      true
    end
  end
  class Model
    attr_accessor :fail_selection_export,:corrupt_export_source
  end
  class WorkflowStyles
    attr_accessor :fail_purge
    def purge_unused
      protected=[selected_style]+@parent.pages.map(&:style)
      @items.delete_if { |s| !protected.include?(s) }
      raise 'Injected purge failure' if @fail_purge
      nil
    end
  end
end
