# encoding: UTF-8
require_relative 'creation_double'
module Geom
  class Transformation
    def self.rotation(point,axis,angle)
      x,y,z = axis.to_a
      d = Math.sqrt(x*x+y*y+z*z); x,y,z = [x/d,y/d,z/d]
      c,s,t = Math.cos(angle),Math.sin(angle),1-Math.cos(angle)
      r = new(Matrix[[t*x*x+c,t*x*y-s*z,t*x*z+s*y,0],[t*x*y+s*z,t*y*y+c,t*y*z-s*x,0],[t*x*z-s*y,t*y*z+s*x,t*z*z+c,0],[0,0,0,1]])
      translation(point.to_a)*r*translation(point.to_a.map { |v| -v })
    end
    def self.scaling(point,x,y,z)
      translation(point.to_a)*new(Matrix.diagonal(x,y,z,1))*translation(point.to_a.map { |v| -v })
    end
  end
end
module SketchupDouble
  Vertex = Struct.new(:position)
  module Primitive
    attr_accessor :parent,:pid,:valid,:material,:hidden
    def persistent_id; @pid; end
    def entityID; @pid+100; end
    def valid?; @valid != false; end
    def hidden?; !!@hidden; end
    def bounds
      box = Geom::BoundingBox.new
      @points.each { |p| box.add(Geom::Point3d.new(p)) }
      box
    end
  end
  class Edge
    include Primitive
    attr_accessor :layer
    attr_reader :points
    attr_accessor :soft,:smooth
    def soft?; !!@soft; end
    def smooth?; !!@smooth; end
    def curve; nil; end
    def faces; @parent.entities.select { |e| e.typename=='Face' && e.edges.include?(self) }; end
    def initialize(a,b); @points = [a.to_a.dup,b.to_a.dup]; end
    def typename; 'Edge'; end
    def start; Vertex.new(Geom::Point3d.new(@points[0])); end
    def end; Vertex.new(Geom::Point3d.new(@points[1])); end
    def length(transform=Geom::Transformation.new)
      start.position.transform(transform).distance(self.end.position.transform(transform))
    end
  end
  class Face
    include Primitive
    def valid?; @valid != false; end
    attr_accessor :back_material
    def outer_loop; Struct.new(:vertices).new(vertices); end
    def loops; [outer_loop]; end
    def get_glued_instances; []; end
    def area(transform=Geom::Transformation.new)
      points = @points.map { |p| Geom::Point3d.new(p).transform(transform).to_a }
      a = points.first
      points.drop(1).each_cons(2).inject(0.0) do |sum,(b,c)|
        u,v = b.zip(a).map { |x,y| x-y },c.zip(a).map { |x,y| x-y }
        cross = [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        sum+Math.sqrt(cross.inject(0.0) { |s,n| s+n*n })*0.5
      end
    end
    def vertices; @points.map { |p| Vertex.new(Geom::Point3d.new(p)) }; end
    def edges
      pairs = @points.each_with_index.map { |p,i| [p,@points[(i+1)%@points.length]].sort }
      @parent.entities.select { |e| e.typename == 'Edge' && pairs.include?(e.points.sort) }
    end
    def pushpull(distance,_copy)
      collection = @parent.entities
      base = @points.map(&:dup)
      n = normal.to_a; length = Math.sqrt(n.inject(0.0) { |s,v| s+v*v })
      delta = n.map { |v| v/length*distance }
      top = base.map { |p| p.zip(delta).map { |v,d| v+d } }
      collection.erase_entities(collection.to_a)
      @parent.bounds = Geom::BoundingBox.new
      polygons = [base.reverse,top]+base.each_index.map { |i| j=(i+1)%base.length; [base[i],base[j],top[j],top[i]] }
      polygons.each { |p| collection.add_face(distance < 0 ? p.reverse : p) }
    end
  end
  class Collection
    alias_method :empty_group,:add_group
    def add_group(children=[])
      group=empty_group
      children.each do |e|
        @items.delete(e)
        e.parent=group.definition
        group.entities << e
        box=e.respond_to?(:definition) ? e.definition.bounds : e.bounds
        transform=e.respond_to?(:transformation) ? e.transformation : Geom::Transformation.new
        8.times { |i| group.definition.bounds.add(box.corner(i).transform(transform)) } unless box.empty?
      end
      group
    end
    alias_method :add_face_without_edges,:add_face
    def add_face(values)
      points = values.first.is_a?(Edge) ? values.map { |e| e.start.position.to_a } : values
      face = add_face_without_edges(points)
      owner_model.register_primitive(face,self)
      points.each_with_index { |p,i| add_line(p,points[(i+1)%points.length]) }
      face
    end
    def add_line(a,b)
      key = [a.to_a,b.to_a].sort
      old = @items.find { |e| e.is_a?(Edge) && e.points.sort == key }
      return old if old
      edge = Edge.new(a,b)
      owner_model.register_primitive(edge,self)
      edge.layer = owner_model.layers[0]
      @items << edge
      [a,b].each { |p| @parent.bounds.add(Geom::Point3d.new(p)) }
      edge
    end
    def add_circle(center,normal,radius,segments)
      n = normal.to_a; length = Math.sqrt(n.inject(0.0) { |s,v| s+v*v }); n=n.map { |v| v/length }
      u = n[0].abs < 0.9 ? [1,0,0] : [0,1,0]
      dot = u.zip(n).inject(0.0) { |s,(a,b)| s+a*b }; u=u.zip(n).map { |a,b| a-dot*b }
      length = Math.sqrt(u.inject(0.0) { |s,v| s+v*v }); u=u.map { |v| v/length }
      v=[n[1]*u[2]-n[2]*u[1],n[2]*u[0]-n[0]*u[2],n[0]*u[1]-n[1]*u[0]]
      points=segments.times.map { |i| angle=2*Math::PI*i/segments; 3.times.map { |j| center[j]+radius*(Math.cos(angle)*u[j]+Math.sin(angle)*v[j]) } }
      points.each_index.map { |i| add_line(points[i],points[(i+1)%segments]) }
    end
    def erase_entities(values)
      values.each do |e|
        e.valid=false
        e.definition.instances.delete(e) if e.respond_to?(:definition)
        @items.delete(e)
      end
      nil
    end
  end
  class Entity
    alias_method :state_without_validity,:state
    def state; state_without_validity.merge(:valid=>@valid,:parent=>@parent); end
    def manifold?
      faces=entities.select { |e| e.typename == 'Face' }
      pairs=Hash.new(0)
      faces.each { |f| f.points.each_with_index { |p,i| pairs[[p,f.points[(i+1)%f.points.length]].sort]+=1 } }
      faces.length >= 4 && !pairs.empty? && pairs.values.all? { |n| n==2 }
    end
  end
  class Definition
    def deep_copy(model)
      copy=Definition.new
      copy.model,copy.name,copy.bounds=model,name,Geom::BoundingBox.new
      entities.select { |e| e.typename == 'Face' }.each do |face|
        result=copy.entities.add_face(face.points)
        result.layer=face.layer
      end
      entities.select { |e| e.typename == 'Edge' }.each { |e| copy.entities.add_line(*e.points) }
      entities.select { |e| %w[Group ComponentInstance].include?(e.typename) }.each { |e| model.copy_entity(e,copy.entities) }
      copy
    end
  end
  class Model
    attr_accessor :active_layer
    def register_primitive(entity,collection)
      @primitives ||= {}
      @next_primitive ||= 2_000_000
      @next_primitive+=1
      entity.pid,entity.parent,entity.valid=@next_primitive,collection.parent,true
      @primitives[entity.pid]=entity
    end
    alias_method :find_without_primitives,:find_entity_by_persistent_id
    def find_entity_by_persistent_id(id); find_without_primitives(id) || (@primitives || {})[id]; end
    alias_method :start_without_drawing,:start_operation
    def start_operation(label,disable)
      result=start_without_drawing(label,disable)
      @operation[:primitive_states]=(@primitives || {}).map { |_,e| [e,e.valid?] }
      @operation[:drawing_bounds]=@all.map(&:definition).uniq.map { |d| [d,Marshal.load(Marshal.dump(d.bounds))] }
      result
    end
    alias_method :restore_without_drawing,:restore
    def restore(snapshot)
      restore_without_drawing(snapshot)
      keep=snapshot[:primitive_states].map(&:first)
      (@primitives || {}).values.each { |e| e.valid=false unless keep.include?(e) }
      snapshot[:primitive_states].each { |e,v| e.valid=v }
      snapshot[:drawing_bounds].each { |d,b| d.bounds=b }
    end
  end
end
