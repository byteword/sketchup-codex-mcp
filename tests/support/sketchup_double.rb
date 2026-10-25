# encoding: UTF-8
# SketchUp API doubles for deterministic command/Undo tests; no native model edits.
require 'matrix'
module Geom
  class Transformation
    attr_reader :matrix
    def initialize(matrix = Matrix.identity(4)); @matrix = matrix; end
    def *(other); Transformation.new(@matrix * other.matrix); end
    def inverse; Transformation.new(@matrix.inverse); end
    def to_a; @matrix.transpose.to_a.flatten; end
    def origin; Point3d.new(@matrix[0, 3], @matrix[1, 3], @matrix[2, 3]); end
    def self.translation(vector)
      x, y, z = vector.to_a
      new(Matrix[[1,0,0,x], [0,1,0,y], [0,0,1,z], [0,0,0,1]])
    end
  end
  class Point3d
    def initialize(*values); @values = values.length == 1 ? values[0].dup : values; end
    def to_a; @values.dup; end
    def transform(t); Point3d.new((t.matrix * Vector[*@values, 1]).to_a.first(3)); end
    def distance(other); Math.sqrt(@values.zip(other.to_a).map { |a,b| (a-b)**2 }.inject(:+)); end
  end
  class Vector3d < Point3d
    def transform(t); Vector3d.new((t.matrix * Vector[*to_a, 0]).to_a.first(3)); end
  end
  class BoundingBox
    def initialize; @points = []; end
    def add(point); @points << point.to_a; self; end
    def empty?; @points.empty?; end
    def min; Point3d.new(@points.transpose.map(&:min)); end
    def max; Point3d.new(@points.transpose.map(&:max)); end
    def center; Point3d.new(min.to_a.zip(max.to_a).map { |a,b| (a+b)/2.0 }); end
    def diagonal; max.distance(min); end
    def width; max.to_a[0] - min.to_a[0]; end
    def height; max.to_a[1] - min.to_a[1]; end
    def depth; max.to_a[2] - min.to_a[2]; end
    def corner(index)
      a, b = min.to_a, max.to_a
      Point3d.new(3.times.map { |i| index & (1 << i) == 0 ? a[i] : b[i] })
    end
  end
end
module Sketchup
  class Camera
    attr_accessor :aspect_ratio, :height, :fov, :description, :special
    attr_reader :eye, :target, :up
    def initialize(eye = Geom::Point3d.new(0,-100,100), target = Geom::Point3d.new(0,0,0), up = Geom::Vector3d.new(0,0,1), perspective = true, fov = 30)
      @eye, @target, @up = Geom::Point3d.new(eye.to_a), Geom::Point3d.new(target.to_a), Geom::Vector3d.new(up.to_a)
      @perspective, @fov, @height, @aspect_ratio, @description = perspective, fov, 200.0, 0.0, ''
    end
    def perspective?; @perspective; end
    def is_2d?; !!@special; end
  end
end
module SketchupDouble
  Named = Struct.new(:name, :visible?)
  Color = Struct.new(:red, :green, :blue)
  Material = Struct.new(:name, :display_name, :color, :alpha)
  class Collection
    include Enumerable
    attr_accessor :parent
    def initialize(parent, items = []); @parent, @items = parent, items; end
    def each(&block); @items.each(&block); end
    def length; @items.length; end
    def [](key); key.is_a?(String) ? @items.find { |v| v.name == key } : @items[key]; end
    def <<(item); @items << item; end
  end
  class Selection < Array
    attr_accessor :fail_next_add
    def add(entities)
      concat(entities).uniq!
      if @fail_next_add
        @fail_next_add = false
        raise 'Selection API failed after mutation'
      end
      self
    end
  end
  class Definition
    attr_accessor :bounds, :instances, :name
    def initialize
      @bounds = Geom::BoundingBox.new.add(Geom::Point3d.new(0,0,0)).add(Geom::Point3d.new(2,3,4))
      @instances, @name = [], '定義'
    end
    def entityID; 900; end
    def persistent_id; raise NotImplementedError; end
    def typename; 'ComponentDefinition'; end
  end
  class Entity
    attr_accessor :parent, :definition, :type, :fail_write, :valid
    attr_reader :name, :layer, :material, :transformation
    def initialize(model, pid, type = 'Group')
      @pid, @parent, @type, @valid = pid, model, type, true
      @name, @layer, @material = 'block', model.layers[0], nil
      @hidden, @locked, @transformation = false, false, Geom::Transformation.new
      @definition = Definition.new
      @definition.instances << self
    end
    def entityID; @pid + 100; end
    def persistent_id; @pid; end
    def typename; @type; end
    def valid?; @valid; end
    def hidden?; @hidden; end
    def locked?; @locked; end
    def write(name, value)
      instance_variable_set('@' + name.to_s, value)
      if @fail_write == name
        @fail_write = nil
        raise 'Entity API failed after mutation'
      end
    end
    [:name, :layer, :material, :hidden, :locked, :transformation].each do |property|
      define_method(property.to_s + '=') { |value| write(property, value) }
    end
    def state; [:name,:layer,:material,:hidden,:locked,:transformation].map { |p| [p, instance_variable_get('@' + p.to_s)] }.to_h; end
    def restore(values); values.each { |p,v| instance_variable_set('@' + p.to_s, v) }; end
  end
  class View
    attr_accessor :camera, :fail_zoom, :last_zoom
    def initialize; @camera = Sketchup::Camera.new; end
    def zoom_extents; zoom(:model); end
    def zoom(entities)
      @last_zoom = entities
      @camera.height = 50.0
      if @fail_zoom
        @fail_zoom = false
        raise 'View API failed after camera mutation'
      end
      self
    end
  end
  class Model
    attr_accessor :active_path, :edit_transform, :active_entities, :bounds
    attr_reader :entities, :selection, :layers, :materials, :active_view, :starts, :commits, :aborts
    def initialize
      @layers = Collection.new(self, [Named.new('Layer0', true), Named.new('구조', true)])
      @materials = Collection.new(self, [Material.new('콘크리트', '콘크리트', Color.new(120,120,120), 1.0)])
      @entities = @active_entities = Collection.new(self)
      @all, @selection, @active_path = [], Selection.new, nil
      @active_view, @edit_transform = View.new, Geom::Transformation.new
      @bounds = Geom::BoundingBox.new.add(Geom::Point3d.new(0,0,0)).add(Geom::Point3d.new(100,200,30))
      @starts = @commits = @aborts = 0
      @undo, @modified = [], false
    end
    def add(pid, type = 'Group')
      entity = Entity.new(self, pid, type)
      @all << entity
      @entities << entity
      entity
    end
    def find_entity_by_persistent_id(pid); @all.find { |e| e.persistent_id == pid }; end
    def title; 'fixture'; end
    def path; ''; end
    def modified?; @modified; end
    def options; {'UnitsOptions' => {'LengthUnit'=>2, 'LengthFormat'=>0, 'LengthPrecision'=>0}}; end
    def definitions; @all.map(&:definition); end
    def pages; []; end
    def start_operation(_label, _disable_ui)
      raise 'Another operation is already active' if @operation
      @operation = [@all.map { |e| [e, e.state] }, @modified]
      @starts += 1
      true
    end
    def commit_operation
      @undo << @operation
      @operation = nil
      @modified = true
      @commits += 1
      true
    end
    def restore(snapshot)
      snapshot[0].each { |entity, values| entity.restore(values) }
      @modified = snapshot[1]
    end
    def abort_operation; restore(@operation); @operation = nil; @aborts += 1; true; end
    def undo; restore(@undo.pop); end
  end
end
