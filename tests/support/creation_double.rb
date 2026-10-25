# encoding: UTF-8
# Additional API doubles for creation topology, instance copies and Undo.
require_relative 'sketchup_double'

module Geom
  class Vector3d
    def dot(other); to_a.zip(other.to_a).inject(0.0) { |sum, (a,b)| sum + a*b }; end
  end
end

module SketchupDouble
  class Face
    attr_accessor :layer
    attr_reader :points
    def initialize(points)
      @points = points.map { |p| p.respond_to?(:to_a) ? p.to_a.dup : p.dup }
    end
    def typename; 'Face'; end
    def valid?; true; end
    def normal
      a,b,c = @points.first(3)
      u,v = b.zip(a).map { |x,y| x-y }, c.zip(a).map { |x,y| x-y }
      Geom::Vector3d.new(u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
    end
    def reverse!; @points.reverse!; self; end
    def deep_copy
      face = Face.new(@points)
      face.layer = @layer
      face
    end
  end

  class Collection
    def replace(items); @items.replace(items); end
    def owner_model; @parent.is_a?(Model) ? @parent : @parent.model; end
    def add_group
      entity = owner_model.spawn(self, 'Group')
      entity.definition.bounds = Geom::BoundingBox.new
      entity
    end
    def add_instance(definition, transform)
      entity = owner_model.spawn(self, 'ComponentInstance')
      entity.definition = definition
      entity.transformation = transform
      entity
    end
    def add_face(points)
      face = Face.new(points)
      @items << face
      points.each { |p| @parent.bounds.add(Geom::Point3d.new(p)) }
      owner_model.face_added
      face
    end
  end

  class Definition
    attr_accessor :model
    def deep_copy(model)
      copy = Definition.new
      copy.model = model
      copy.name = name
      copy.bounds = Geom::BoundingBox.new
      8.times { |i| copy.bounds.add(bounds.corner(i)) } unless bounds.empty?
      entities.each do |item|
        if item.is_a?(Face)
          copy.entities << item.deep_copy
        else
          model.copy_entity(item, copy.entities)
        end
      end
      copy
    end
  end

  Dictionary = Struct.new(:name, :values) do
    def each_pair(&block); values.each_pair(&block); end
  end

  class Entity
    alias_method :initialize_without_creation, :initialize
    def initialize(model, pid, type = 'Group')
      initialize_without_creation(model, pid, type)
      @model = model
      @definition.model = model
      @attributes = {}
      @casts_shadows = @receives_shadows = true
    end
    def definition=(definition)
      @definition.instances.delete(self) if @definition
      @definition = definition
      @definition.model = @model
      @definition.instances << self unless @definition.instances.include?(self)
    end
    def entities; @definition.entities; end
    def copy
      @model.copy_entity(self, @parent.entities)
    end
    def make_unique
      self.definition = @definition.deep_copy(@model)
      self
    end
    def manifold?
      faces = entities.to_a.select { |e| e.is_a?(Face) }
      edges = Hash.new(0)
      faces.each do |face|
        face.points.each_with_index do |point, i|
          edges[[point, face.points[(i+1) % face.points.length]].sort] += 1
        end
      end
      faces.length == 6 && edges.length == 12 && edges.values.all? { |count| count == 2 }
    end
    def casts_shadows?; @casts_shadows; end
    def receives_shadows?; @receives_shadows; end
    def casts_shadows=(value); write(:casts_shadows, value); end
    def receives_shadows=(value); write(:receives_shadows, value); end
    attr_accessor :glued_to
    def attribute_dictionaries
      @attributes.empty? ? nil : @attributes.map { |name, values| Dictionary.new(name, values) }
    end
    def set_attribute(dictionary, key, value)
      @attributes[dictionary] ||= {}
      @attributes[dictionary][key] = Marshal.load(Marshal.dump(value))
    end
    def get_attribute(dictionary, key); (@attributes[dictionary] || {})[key]; end
    alias_method :state_without_creation, :state
    def state
      state_without_creation.merge(:definition=>@definition, :attributes=>Marshal.load(Marshal.dump(@attributes)),
        :casts_shadows=>@casts_shadows, :receives_shadows=>@receives_shadows)
    end
  end

  class Model
    attr_accessor :fail_face_after, :fail_spawn_after
    def face_added
      return unless @fail_face_after
      @fail_face_after -= 1
      raise 'Injected face creation failure after mutation' if @fail_face_after <= 0
    end
    def spawn(collection, type)
      @next_pid ||= 1_000_000
      @next_pid += 1
      entity = Entity.new(self, @next_pid, type)
      entity.parent = collection.parent
      @all << entity
      collection << entity
      if @fail_spawn_after
        @fail_spawn_after -= 1
        raise 'Injected instance creation failure after mutation' if @fail_spawn_after <= 0
      end
      entity
    end
    def copy_entity(source, collection)
      entity = spawn(collection, source.typename)
      entity.definition = source.definition
      entity.restore(source.state.reject { |key, _| key == :definition })
      entity
    end
    def start_operation(_label, _disable_ui)
      raise 'Another operation is already active' if @operation
      definitions = @all.map(&:definition).uniq
      @operation = {:entities=>@all.map { |e| [e, e.state] }, :modified=>@modified,
        :root=>@entities.to_a, :definitions=>definitions.map { |d| [d, d.entities.to_a, d.instances.dup] }}
      @starts += 1
      true
    end
    def restore(snapshot)
      kept = snapshot[:entities].map(&:first)
      (@all-kept).each { |entity| entity.valid = false }
      @all = kept
      snapshot[:entities].each { |entity, values| entity.restore(values) }
      @entities.replace(snapshot[:root])
      snapshot[:definitions].each do |definition, entities, instances|
        definition.entities.replace(entities)
        definition.instances.replace(instances)
      end
      @modified = snapshot[:modified]
    end
  end
end
