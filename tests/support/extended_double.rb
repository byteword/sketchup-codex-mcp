# encoding: UTF-8
require_relative 'drawing_double'
PAGE_USE_CAMERA=1 unless defined?(PAGE_USE_CAMERA)
module Sketchup
  Color=SketchupDouble::Color
  module Drawingelement; end
end
[SketchupDouble::Entity,SketchupDouble::Face,SketchupDouble::Edge].each { |type| type.include(Sketchup::Drawingelement) }
module Geom
  class Point3d
    def [](index); to_a[index]; end
    def initialize(*values); @values=values.length==1 ? values[0].to_a.dup : values; end
    def -(other); Vector3d.new(to_a.zip(other.to_a).map { |a,b| a-b }); end
    def offset(vector); Point3d.new(to_a.zip(vector.to_a).map { |a,b| a+b }); end
  end
  class Vector3d
    def angle_between(other)
      Math.acos([[dot(other)/Math.sqrt(dot(self)*other.dot(other)),-1.0].max,1.0].min)
    end
  end
end
module SketchupDouble
  class Material
    def texture; nil; end
  end
  class TestResource
    attr_accessor :name,:description,:color,:alpha,:texture,:camera,:visible
    @@next_id=7_000_000
    def initialize(name)
      @@next_id+=1; @id=@@next_id; @name=name; @description=''; @visible=true; @color=Color.new(0,0,0); @alpha=1.0
    end
    def persistent_id; raise NotImplementedError,'No resource PIDs in SketchUp2019'; end
    def entityID; @id; end
    def visible?; @visible; end
    def display_name; name; end
    def valid?; true; end
    def use_camera?; true; end
    def update(_flags); @camera=Sketchup::Camera.new(@model.active_view.camera.eye,@model.active_view.camera.target,@model.active_view.camera.up,@model.active_view.camera.perspective?,@model.active_view.camera.fov); @camera.height=@model.active_view.camera.height; true; end
    def model=(model); @model=model; end
  end
  class Resources < Collection
    attr_accessor :fail_remove
    def initialize(model,kind,items=[]); super(model,items); @kind=kind; end
    def add(name,_flags=nil)
      r=TestResource.new(name); r.model=@parent; @items<<r; r.update(1) if @kind=='scenes'; r
    end
    def remove(resource,_delete_geometry=false)
      raise 'Injected resource delete error' if @fail_remove
      if @kind=='tags'
        (@parent.entities.to_a+@parent.definitions.flat_map { |d| d.entities.to_a }).each { |e| e.layer=@parent.layers[0] if e.respond_to?(:layer) && e.layer==resource }
      end
      !!@items.delete(resource)
    end
    def erase(page); remove(page); end
    def purge_unused; @items.delete_if { |r| r.name.start_with?('unused') }; self; end
    def snapshot; @items.map { |r| [r,r.instance_variables.map { |v| [v,r.instance_variable_get(v)] }.to_h] }; end
    def restore(snapshot); @items=snapshot.map(&:first); snapshot.each { |r,state| state.each { |k,v| r.instance_variable_set(k,v) } }; end
  end
  class Definitions < Array
    def [](key); key.is_a?(String) ? find { |d| d.name==key } : super; end
    def length; uniq.size; end
  end
  class Definition
    attr_accessor :description
    @@pid=8_000_000
    alias_method :old_initialize_ext,:initialize
    def initialize; old_initialize_ext; @@pid+=1; @pid=@@pid; @description=''; end
    def entityID; @pid; end
    def persistent_id; raise NotImplementedError,'No definition PID in SketchUp2019'; end
    def valid?; true; end
    def group?; instances.first && instances.first.typename=='Group'; end
    def image?; false; end
    def count_instances; instances.length; end
  end
  class ConstructionPoint
    include Sketchup::Drawingelement
    include Primitive
    attr_accessor :layer
    def initialize(p); @points=[p.to_a.dup]; end
    def typename; 'ConstructionPoint'; end
    def position; Geom::Point3d.new(@points.first); end
    def position=(p); @points[0]=p.to_a.dup; end
  end
  class LiveVertex
    def initialize(edge,index); @edge,@index=edge,index; end
    def position; Geom::Point3d.new(@edge.points[@index]); end
    def valid?; @edge.valid?; end
    def position=(p)
      old=position.to_a
      @edge.parent.entities.each { |e| e.points.each { |q| q.replace(p.to_a) if q==old } if e.respond_to?(:points) }
    end
  end
  class Edge
    def start; @start ||= LiveVertex.new(self,0); end
    def end; @end ||= LiveVertex.new(self,1); end
    def find_faces
      collection=@parent.entities
      return 0 if collection.any? { |e| e.typename=='Face' }
      remaining=collection.select { |e| e.typename=='Edge' }; points=[remaining.first.points.first]; last=points.first
      until remaining.empty?
        edge=remaining.find { |e| e.points.include?(last) }; break unless edge
        remaining.delete(edge); last=edge.points.find { |p| p!=last }; points<<last unless last==points.first
      end
      collection.add_face(points) if points.length>=3; 1
    end
  end
  class Face
    alias_method :normal_without_normalization,:normal
    def normal
      n=normal_without_normalization.to_a; length=Math.sqrt(n.inject(0.0) { |s,x| s+x*x }); Geom::Vector3d.new(n.map { |x| x/length })
    end
    def followme(edges)
      a,b=edges.first.points; size=Math.sqrt(b.zip(a).inject(0.0) { |s,(x,y)| s+(x-y)**2 })
      # Native Follow Me can leave its guide edges inside the resulting solid.
      paths=edges.map { |edge| edge.points.map(&:dup) }
      pushpull(size,false)
      paths.each { |points| @parent.entities.add_line(*points) }
      !@parent.model.fail_followme
    end
  end
  class Collection
    alias_method :erase_without_surface_merge,:erase_entities
    def erase_entities(items)
      items.each do |e|
        next unless e.typename=='Edge' && e.faces.length==2 && e.faces[0].normal.dot(e.faces[1].normal)>1-1e-8
        fs=e.faces; normal=fs.first.normal
        border=fs.flat_map(&:edges).group_by { |edge| edge.points.sort }.values.select { |edges| edges.length==1 }.map(&:first)
        first=border.first; points=[first.points.first]; last=points.first
        until border.empty?
          edge=border.find { |candidate| candidate.points.include?(last) }; break unless edge
          border.delete(edge); last=edge.points.find { |p| p!=last }; points<<last unless last==points.first
        end
        erase_without_surface_merge(fs); face=add_face(points); face.reverse! if face.normal.dot(normal)<0
      end
      erase_without_surface_merge(items)
    end
    def add_cpoint(point)
      e=ConstructionPoint.new(point); owner_model.register_primitive(e,self); e.layer=owner_model.layers[0]; @items<<e; e
    end
    def add_curve(points); points.each_cons(2).map { |a,b| add_line(a,b) }; end
    def add_arc(center,u,n,r,start,stop,count)
      u,n=u.to_a,n.to_a; v=[n[1]*u[2]-n[2]*u[1],n[2]*u[0]-n[0]*u[2],n[0]*u[1]-n[1]*u[0]]
      points=(0..count).map { |i| a=start+(stop-start)*i/count; 3.times.map { |j| center[j]+r*(u[j]*Math.cos(a)+v[j]*Math.sin(a)) } }
      add_curve(points)
    end
    def transform_by_vectors(items,vectors)
      return self if owner_model.ignore_vector_moves
      items.zip(vectors).each { |e,v| e.position=e.position.offset(v) }; self
    end
  end
  class Entity
    def to_component; @type='ComponentInstance'; self; end
    def explode
      collection=@parent.entities; children=entities.to_a
      children.each do |e|
        if e.respond_to?(:transformation); e.transformation=@transformation*e.transformation
        elsif e.respond_to?(:points); e.points.each { |p| p.replace(Geom::Point3d.new(p).transform(@transformation).to_a) } end
        e.parent=collection.parent; collection<<e
      end
      collection.erase_entities([self])
      # Native explode also returns topology helpers and may repeat entities.
      internals=Array.new(@model.explode_internal_count || 2) { |i| ExplodeInternal.new(i.even? ? 0 : 90_000_000+i,collection.parent) }
      children+internals+children.first(1)
    end
  end
  class Model
    alias_method :initialize_before_extended,:initialize
    def initialize
      initialize_before_extended
      @layers=Resources.new(self,'tags',[TestResource.new('Layer0')]); @active_layer=@layers[0]
      @layers.add('구조')
      @materials=Resources.new(self,'materials'); @materials.add('콘크리트'); @pages=Resources.new(self,'scenes')
    end
    def definitions; Definitions.new(@all.map(&:definition).uniq); end
    def pages; @pages; end
    alias_method :start_before_extended,:start_operation
    def start_operation(label,disable)
      result=start_before_extended(label,disable)
      @operation[:resources]=[@layers.snapshot,@materials.snapshot]
      @operation[:raw_points]=(@primitives || {}).values.map { |e| [e,e.respond_to?(:points) ? Marshal.load(Marshal.dump(e.points)) : nil,e.material,e.hidden?] }
      result
    end
    alias_method :restore_before_extended,:restore
    def restore(snapshot)
      restore_before_extended(snapshot); @layers.restore(snapshot[:resources][0]); @materials.restore(snapshot[:resources][1])
      snapshot[:raw_points].each { |e,points,material,hidden| e.points.replace(points) if points; e.material=material; e.hidden=hidden }
    end
  end
end

module SketchupDouble
  ExplodeInternal=Struct.new(:persistent_id,:parent) do
    def valid?; true; end
    def typename; 'Vertex'; end
  end
  class Model
    attr_accessor :fail_followme,:explode_internal_count,:ignore_vector_moves
  end
  class Entity
    alias_method :manifold_without_loose_edges?, :manifold?
    def manifold?
      return false unless manifold_without_loose_edges?
      supported={}
      entities.select { |e| e.typename=='Face' }.each do |face|
        face.points.each_index { |i| supported[[face.points[i],face.points[(i+1)%face.points.length]].sort]=true }
      end
      entities.select { |e| e.typename=='Edge' }.all? { |edge| supported[edge.points.sort] }
    end
  end
end
