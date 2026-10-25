# encoding: UTF-8
require 'minitest/autorun'
require 'matrix'
require_relative '../extension/su_pipe_probe/model_reader'

# Minimal geometry doubles: exercise coordinate composition without editing a model.
module Geom
  class Transformation
    attr_reader :matrix
    def initialize(matrix = Matrix.identity(4)); @matrix = matrix; end
    def *(other); Transformation.new(@matrix * other.matrix); end
  end
  class Point3d
    def initialize(x, y, z); @values = [x, y, z]; end
    def to_a; @values; end
    def transform(t)
      values = (t.matrix * Vector[*@values, 1]).to_a
      Point3d.new(*values.first(3))
    end
    def distance(other); Math.sqrt(@values.zip(other.to_a).map { |a, b| (a - b)**2 }.inject(:+)); end
  end
  class BoundingBox
    def initialize; @points = []; end
    def add(point); @points << point.to_a; self; end
    def empty?; @points.empty?; end
    def min; Point3d.new(*@points.transpose.map(&:min)); end
    def max; Point3d.new(*@points.transpose.map(&:max)); end
    def width; max.to_a[0] - min.to_a[0]; end
    def height; max.to_a[1] - min.to_a[1]; end
    def depth; max.to_a[2] - min.to_a[2]; end
    def corner(index)
      a, b = min.to_a, max.to_a
      Point3d.new(*3.times.map { |i| index & (1 << i) == 0 ? a[i] : b[i] })
    end
  end
end

class ReaderEntity
  attr_accessor :name, :typename, :definition, :transformation, :bounds, :material, :back_material
  def initialize(type = 'Group', name = '대지 그룹')
    @typename, @name = type, name
    @transformation = Geom::Transformation.new
  end
  def entityID; 42; end
  def persistent_id; 9_007_199_254_740_993; end
  def layer; Struct.new(:name, :visible?).new('구조', false); end
  def hidden?; false; end
  def locked?; true; end
end

class ReaderModel
  attr_accessor :title, :path, :bounds, :entities, :selection, :edit_transform, :active_path
  attr_accessor :layers, :materials, :definitions, :pages
  def options; {'UnitsOptions' => {'LengthUnit' => 2, 'LengthFormat' => 0, 'LengthPrecision' => 1}}; end
  def modified?; false; end
end

class ModelReaderTest < Minitest::Test
  def setup
    @box = Geom::BoundingBox.new.add(Geom::Point3d.new(0, 0, 0)).add(Geom::Point3d.new(2, 3, 4))
    @definition = ReaderEntity.new('ComponentDefinition', '창호 정의')
    @definition.bounds = @box
    @group = ReaderEntity.new
    @group.definition = @definition
    @group.bounds = @box
    @model = ReaderModel.new
    @model.title, @model.path = '대지', 'C:/프로젝트/대지.skp'
    @model.bounds = @box
    @model.entities = [@group]
    @model.selection = [@group]
    @model.edit_transform = Geom::Transformation.new
    @model.layers, @model.materials, @model.definitions, @model.pages = [1, 2], [], [@definition], []
    @reader = SUPipeProbe::ModelReader.new(@model)
  end

  def query(arguments = {})
    @reader.call('get_selection_info', arguments)
  end

  def test_summary_units_bounds_and_root_counts
    data = @reader.call('get_model_summary', {})
    assert_equal 'mm', data['measurement_unit']
    assert_equal '대지', data['title']
    assert_equal [50.8, 76.2, 101.6], data['bounds']['size']
    assert_equal({'Group' => 1}, data['top_level_entities']['by_type'])
    assert data['top_level_entities']['complete']
    assert_equal 2, data['collection_counts']['tags']
    assert data['saved']
    refute data['modified']
  end

  def test_empty_unsaved_model_and_empty_selection
    @model.path, @model.entities, @model.selection = '', [], []
    @model.bounds = Geom::BoundingBox.new
    data = @reader.call('get_model_summary', {})
    refute data['saved']
    assert data['bounds']['empty']
    assert_equal 0, data['top_level_entities']['total']
    assert_empty query['items']
    assert_nil query['next_offset']
    refute query['truncated']
  end

  def test_rotated_scaled_instance_in_scaled_edit_context
    @group.transformation = Geom::Transformation.new(Matrix[[0, -3, 0, 10], [2, 0, 0, 20], [0, 0, -4, 0], [0, 0, 0, 1]])
    @model.edit_transform = Geom::Transformation.new(Matrix[[2, 0, 0, 100], [0, 2, 0, 0], [0, 0, 2, 0], [0, 0, 0, 1]])
    @model.active_path = [ReaderEntity.new('Group', '부모')]
    data = query
    item = data['items'][0]
    assert_equal [50.8, 76.2, 101.6], item['definition_bounds']['size']
    assert_equal [203.2, 457.2, 812.8], item['instance_axis_lengths_mm']
    assert_equal [457.2, 203.2, 812.8], item['model_bounds']['size']
    assert_equal [2590.8, 1016.0, -812.8], item['model_bounds']['min']
    assert_equal 1, data['edit_context']['depth']
    assert_equal '9007199254740993', item['persistent_id']
    assert_equal '구조', item['tag']['name']
    refute item['tag']['visible']
    assert item['locked']
    assert_nil item['material']
  end

  def test_pagination_and_offset_past_end
    @model.selection = Array.new(30) { @group }
    data = query('offset' => 10, 'limit' => 5)
    assert_equal 30, data['total']
    assert_equal 5, data['returned']
    assert_equal 15, data['next_offset']
    assert data['truncated']
    data = query('offset' => 30)
    assert_empty data['items']
    assert_nil data['next_offset']
  end

  def test_invalid_pagination_is_rejected_in_ruby_too
    [{'limit' => 0}, {'limit' => 26}, {'limit' => '2'}, {'offset' => -1}, {'offset' => 1.5}].each do |args|
      assert_raises(ArgumentError) { query(args) }
    end
  end

  def test_text_and_page_byte_budget
    @group.name = '가🙂' * 2000
    @model.selection = Array.new(25) { @group }
    data = query('limit' => 25)
    assert_equal 256, data['items'][0]['name'].length
    assert data['items'][0]['text_truncated']
    assert_operator JSON.generate(data).bytesize, :<, 60_000
  end

  def test_primitive_bounds_and_empty_definition
    edge = ReaderEntity.new('Edge')
    edge.bounds = @box
    @model.selection = [edge]
    assert_equal [50.8, 76.2, 101.6], query['items'][0]['model_bounds']['size']
    refute query['items'][0].key?('definition_bounds')
    @definition.bounds = Geom::BoundingBox.new
    @model.selection = [@group]
    assert query['items'][0]['model_bounds']['empty']
    refute query['items'][0].key?('instance_axis_lengths_mm')
  end

  def test_large_root_counts_are_marked_incomplete
    @model.entities = Array.new(20_001) { @group }
    data = @reader.call('get_model_summary', {})['top_level_entities']
    assert_equal 20_001, data['total']
    assert_equal 20_000, data['scanned']
    refute data['complete']
  end

  def test_definition_without_persistent_id_on_sketchup_2019
    def @definition.persistent_id; raise NotImplementedError, 'Unsupported entity'; end
    assert_nil query['items'][0]['definition']['persistent_id']
    assert_equal '9007199254740993', query['items'][0]['persistent_id']
  end

  def test_planar_selection_keeps_y_extent_and_zero_z
    plane = Geom::BoundingBox.new.add(Geom::Point3d.new(-1, -2, 0)).add(Geom::Point3d.new(2, 3, 0))
    @definition.bounds = @model.bounds = plane
    item = query['items'].first
    assert_equal [76.2, 127.0, 0.0], item['definition_bounds']['size']
    assert_equal [76.2, 127.0, 0.0], item['model_bounds']['size']
    assert_equal [76.2, 127.0, 0.0], @reader.call('get_model_summary', {})['bounds']['size']
  end
end
