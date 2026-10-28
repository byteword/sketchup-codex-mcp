# encoding: UTF-8
require 'json'
require 'time'
require_relative 'entity_browser'
require_relative 'entity_details'
require_relative 'resources'

module SUPipeProbe
  # Called only by Panel's UI timer. No observers, operations, or setters.
  class ModelReader
    include EntityDetails
    STRING_LIMIT = 256
    COUNT_LIMIT = 20_000
    PAGE_BUDGET = 40_000

    def initialize(model)
      @model = model
    end

    def call(method, arguments)
      case method
      when 'get_model_summary' then summary
      when 'get_selection_info' then selection(arguments)
      when 'get_entity_info' then specific_entity(arguments)
      when 'get_resources' then ResourceReader.new(@model).call(arguments)
      when 'find_entities', 'get_children' then EntityBrowser.new(@model).call(method, arguments)
      else raise ArgumentError, 'Unknown read method'
      end
    end

    private

    def base
      {'queried_at' => Time.now.utc.iso8601(3), 'measurement_unit' => 'mm',
       'model_units' => units}
    end

    def units
      options = @model.options['UnitsOptions']
      unit = options['LengthUnit']
      {'length_unit_code' => unit,
       'length_unit' => {0 => 'in', 1 => 'ft', 2 => 'mm', 3 => 'cm', 4 => 'm', 5 => 'yd'}[unit],
       'length_format_code' => options['LengthFormat'],
       'length_precision' => options['LengthPrecision']}
    end

    def summary
      base.merge('title' => @model.title.to_s, 'path' => @model.path.to_s,
        'saved' => !@model.path.to_s.empty?, 'modified' => @model.modified?,
        'bounds' => bounds(@model.bounds, Geom::Transformation.new, 'model_axes'),
        'top_level_entities' => entity_counts(@model.entities),
        'collection_counts' => {'tags' => @model.layers.length,
          'materials' => @model.materials.length, 'definitions' => @model.definitions.length,
          'scenes' => @model.pages.length},
        'selection_count' => @model.selection.length, 'edit_context' => edit_context,
        'notes' => ['Entity counts cover the model root only, including hidden objects. They do not recurse into definitions.',
          'Collection counts include unused entries. All numeric lengths and coordinates are millimeters.',
          'Bounds are bounding-box extents, not measured edges or usable floor dimensions.'])
    end

    def entity_counts(entities)
      counts = Hash.new(0)
      scanned = 0
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5
      entities.each do |entity|
        break if scanned >= COUNT_LIMIT
        break if scanned % 128 == 0 && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        counts[entity.typename] += 1
        scanned += 1
      end
      {'total' => entities.length, 'by_type' => counts, 'scanned' => scanned,
       'complete' => scanned == entities.length, 'scope' => 'direct_children'}
    end

    def selection(arguments)
      offset = arguments.fetch('offset', 0)
      limit = arguments.fetch('limit', 10)
      raise ArgumentError, 'offset must be an integer from 0 to 1000000' unless offset.is_a?(Integer) && offset.between?(0, 1_000_000)
      raise ArgumentError, 'limit must be an integer from 1 to 25' unless limit.is_a?(Integer) && limit.between?(1, 25)
      transform = @model.edit_transform
      items = []
      bytes = 0
      total = @model.selection.length
      @model.selection.each_with_index do |entity, index|
        next if index < offset
        break if items.length >= limit
        item = entity_info(entity, transform)
        size = JSON.generate(item).bytesize
        break if bytes + size > PAGE_BUDGET
        items << item
        bytes += size
      end
      next_offset = offset + items.length
      base.merge('total' => total, 'offset' => offset, 'returned' => items.length,
        'next_offset' => next_offset < total ? next_offset : nil,
        'truncated' => next_offset < total, 'edit_context' => edit_context,
        'items' => items,
        'notes' => ['Each call reads the current selection; pages are not a frozen snapshot.',
          'Material and visibility flags describe direct assignments, not inherited or effective appearance.',
          'model_bounds encloses transformed bounding-box corners; it can exceed the actual geometry extents.',
          'definition_bounds is unscaled; instance_axis_lengths_mm includes this instance and its edit ancestors.'])
    end

    def identity(entity)
      {'entity_id' => entity.entityID.to_s,
       'persistent_id' => persistent_id(entity),
       'type' => entity.typename}
    end

    def persistent_id(entity)
      return nil unless entity.respond_to?(:persistent_id)
      value = entity.persistent_id
      value && value > 0 ? value.to_s : nil
    rescue StandardError, NotImplementedError
      # E.g. ComponentDefinition inherits this method but has no PID before 2020.1.
      nil
    end

    def edit_context
      path = @model.active_path || []
      {'depth' => path.length, 'path' => path.first(32).map { |e| identity(e).merge('name' => clip(e.name, 64)) },
       'path_truncated' => path.length > 32, 'name_character_limit' => 64}
    end

    def entity_info(entity, edit_transform)
      @text_truncated = false
      result = identity(entity)
      result['name'] = clip(entity.name) if entity.respond_to?(:name)
      if entity.respond_to?(:layer)
        result['tag'] = {'name' => clip(entity.layer.name), 'visible' => entity.layer.visible?}
      end
      result['hidden'] = entity.hidden? if entity.respond_to?(:hidden?)
      result['locked'] = entity.locked? if entity.respond_to?(:locked?)
      result['material'] = material(entity.material) if entity.respond_to?(:material)
      result['back_material'] = material(entity.back_material) if entity.respond_to?(:back_material)
      if %w[Group ComponentInstance].include?(entity.typename)
        definition = entity.definition
        transform = edit_transform * entity.transformation
        result['definition'] = identity(definition).merge('name' => clip(definition.name), 'definition_id'=>'definition:'+definition.entityID.to_s)
        result['definition_bounds'] = bounds(definition.bounds, Geom::Transformation.new, 'definition_axes')
        result['model_bounds'] = bounds(definition.bounds, transform, 'model_axes')
        unless definition.bounds.empty?
          corners = [0, 1, 2, 4].map { |i| definition.bounds.corner(i).transform(transform) }
          result['instance_axis_lengths_mm'] = corners.drop(1).map { |p| mm(p.distance(corners[0])) }
        end
      elsif entity.respond_to?(:bounds)
        result['model_bounds'] = bounds(entity.bounds, edit_transform, 'model_axes')
      end
      result['text_truncated'] = @text_truncated
      result
    end

    def material(value)
      return nil unless value
      {'name' => clip(value.name), 'display_name' => clip(value.display_name),
       'color_rgb' => [value.color.red, value.color.green, value.color.blue], 'alpha' => value.alpha}
    end

    def clip(value, limit = STRING_LIMIT)
      text = value.to_s
      @text_truncated = true if text.length > limit
      text[0, limit]
    end

    def mm(length)
      value = length.to_f * 25.4
      value.finite? ? value.round(6) : nil
    end

    def point(value)
      value.to_a.map { |coordinate| mm(coordinate) }
    end

    def bounds(box, transform, axes)
      return {'empty' => true, 'axes' => axes} if box.empty?
      transformed = Geom::BoundingBox.new
      8.times { |i| transformed.add(box.corner(i).transform(transform)) }
      # SketchUp calls Y extent height and Z extent depth. Use coordinates to
      # keep the wire contract explicitly X/Y/Z regardless of accessor names.
      size = transformed.min.to_a.zip(transformed.max.to_a).map { |a, b| mm(b - a) }
      {'empty' => false, 'axes' => axes, 'min' => point(transformed.min),
       'max' => point(transformed.max),
       'size' => size}
    end
  end
end
