# encoding: UTF-8
require 'json'
require_relative 'creation_commands'
require_relative 'basic_commands'
require_relative 'extended_geometry'
require_relative 'resources'
require_relative 'view_commands'
require_relative 'ui_update_scope'
require_relative 'batch_commands'
require_relative 'sliding_window_commands'

module SUPipeProbe
  class CommandError < StandardError
    attr_reader :code
    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  # Every call runs synchronously on Panel's UI timer, never on a worker thread.
  class CommandExecutor
    include CreationCommands
    include BasicCommands
    include ExtendedGeometry
    include ResourceCommands
    include ViewCommands
    include BatchCommands
    include SlidingWindowCommands
    METHODS = %w[set_selection set_view zoom update_entity_properties move_entities create_box duplicate_entities create_rectangle create_circle create_polyline rotate_entities scale_entities erase_entities group_entities make_unique push_pull run_self_test manage_resource component create_geometry edit_geometry mirror_entities configure_camera scene run_batch create_sliding_window].freeze
    RESULT_LIMIT = 44_000
    MAX_SELECTION = 1000

    def initialize(model)
      @model = model
    end

    def call(method, args)
      fail_command('unknown_command', 'Unsupported command') unless METHODS.include?(method)
      validate_context(args['expected_context'])
      dry = args.fetch('dry_run', false)
      fail_command('invalid_arguments', 'dry_run must be boolean') unless dry == true || dry == false
      @ui_updates=UiUpdateScope.validate(args.fetch('ui_updates','defer'))
      case method
      when 'set_selection' then selection(args, dry)
      when 'set_view' then camera_command(args, dry, true)
      when 'zoom' then camera_command(args, dry, false)
      when 'update_entity_properties' then update_properties(args, dry)
      when 'move_entities' then move(args, dry)
      when 'create_box' then create_box(args, dry)
      when 'duplicate_entities' then duplicate_entities(args, dry)
      when 'create_rectangle' then drawing(args,dry,'rectangle')
      when 'create_circle' then drawing(args,dry,'circle')
      when 'create_polyline' then drawing(args,dry,'polyline')
      when 'rotate_entities' then transform_instances(args,dry,'rotate')
      when 'scale_entities' then transform_instances(args,dry,'scale')
      when 'erase_entities' then erase_instances(args,dry)
      when 'group_entities' then group_instances(args,dry)
      when 'make_unique' then unique_instances(args,dry)
      when 'push_pull' then push_pull_profile(args,dry)
      when 'run_self_test' then NativeSelfTest.new(@model).call(args,dry)
      when 'run_batch' then run_batch(args,dry)
      when 'create_sliding_window' then create_sliding_window(args,dry)
      when 'manage_resource','component','create_geometry','edit_geometry','mirror_entities','configure_camera','scene' then send(method,args,dry)
      end
    end

    private

    def fail_command(code, message)
      raise CommandError.new(code, message)
    end

    def validate_context(expected)
      ids(expected, 32, true)
      path = @model.active_path || []
      current = path.map { |entity| entity.persistent_id.to_s }
      fail_command('context_mismatch', 'Refresh selection information and use the current edit path') unless expected == current
      fail_command('locked_context', 'An edit ancestor is locked') if path.any?(&:locked?)
    end

    def ids(values, maximum = 25, empty = false)
      unless values.is_a?(Array) && values.length <= maximum && (empty || !values.empty?) &&
          values.all? { |v| v.is_a?(String) && v.match(/\A[1-9][0-9]{0,18}\z/) }
        fail_command('invalid_arguments', 'Expected an array of positive persistent ID strings within the item limit')
      end
      fail_command('invalid_arguments', 'Duplicate entity IDs are not allowed') unless values.uniq.length == values.length
      values
    end

    def targets(values, empty = false)
      ids(values, 25, empty)
      parent = @model.active_entities.parent
      values.map do |id|
        entity = @model.find_entity_by_persistent_id(id.to_i)
        fail_command('entity_not_found', 'An entity is missing or no longer valid') unless entity && entity.valid?
        fail_command('entity_context_mismatch', 'Entity is not directly in the expected edit context') unless entity.parent == parent
        fail_command('unsupported_entity', 'Only groups and component instances are supported') unless %w[Group ComponentInstance].include?(entity.typename)
        entity
      end
    end

    def editable(entities, unlocking = false)
      fail_command('entity_locked', 'Unlock the object in a separate command first') if !unlocking && entities.any? { |e| e.respond_to?(:locked?) && e.locked? }
      # Editing a child in a shared definition affects every occurrence of its parent.
      if (@model.active_path || []).any? { |e| e.definition.instances.length > 1 }
        fail_command('shared_edit_context', 'Make the edit ancestors unique in SketchUp before changing their children')
      end
    end

    def checked(data)
      fail_command('result_too_large', 'Use fewer targets; result would exceed the pipe budget') if JSON.generate(data).bytesize > RESULT_LIMIT
      data
    end

    def operation(label)
      scope=UiUpdateScope.new(@model,@ui_updates || 'defer')
      data=scope.run(label) { checked(yield) }
      data.merge('ui_update'=>scope.report)
    end

    def selection(args, dry)
      mode = args['mode']
      fail_command('invalid_arguments', 'Invalid selection mode') unless %w[replace add remove clear].include?(mode)
      entities = targets(args['entity_ids'], mode == 'clear')
      fail_command('invalid_arguments', 'clear requires empty entity_ids') if mode == 'clear' && !entities.empty?
      fail_command('selection_too_large', 'Reduce the current selection to 1000 items first') if @model.selection.length > MAX_SELECTION
      previous = @model.selection.to_a
      desired = case mode
                when 'replace' then entities
                when 'add' then (previous + entities).uniq
                when 'remove' then previous - entities
                else []
                end
      fail_command('selection_too_large', 'Resulting selection exceeds 1000 items') if desired.length > MAX_SELECTION
      data = checked('dry_run' => dry, 'undoable' => false,
        'before' => previous.map { |e| e.persistent_id.to_s }, 'after' => desired.map { |e| e.persistent_id.to_s })
      return data if dry || previous == desired
      begin
        @model.selection.clear
        @model.selection.add(desired) unless desired.empty?
        actual = @model.selection.to_a.map { |e| e.persistent_id.to_s }
        fail_command('postcondition_failed', 'Selection did not match the requested objects') unless actual.sort == data['after'].sort
      rescue StandardError => error
        begin
          @model.selection.clear
          @model.selection.add(previous) unless previous.empty?
          raise 'Selection restore mismatch' unless @model.selection.to_a.map { |e| e.persistent_id.to_s }.sort == data['before'].sort
        rescue StandardError
          fail_command('outcome_unknown', 'Could not restore the previous selection')
        end
        raise error
      end
      data
    end

    def short(value)
      text = value.to_s
      {'value' => text[0, 256], 'truncated' => text.length > 256}
    end

    def properties_of(entity, keys)
      keys.each_with_object({}) do |key, result|
        result[key] = case key
                      when 'name' then short(entity.name)
                      when 'hidden' then entity.hidden?
                      when 'locked' then entity.locked?
                      when 'tag' then short(entity.layer.name)
                      when 'material' then entity.material ? short(entity.material.name) : nil
                      end
      end
    end

    def update_properties(args, dry)
      entities = targets(args['entity_ids'])
      properties = args['properties']
      allowed = %w[name hidden locked tag material]
      unless properties.is_a?(Hash) && !properties.empty? && (properties.keys - allowed).empty?
        fail_command('invalid_arguments', 'Provide only name, hidden, locked, tag or material properties')
      end
      properties.each do |key, value|
        valid = case key
                when 'hidden', 'locked' then value == true || value == false
                when 'material' then value.nil? || (value.is_a?(String) && value.length.between?(1, 256))
                when 'name' then value.is_a?(String) && value.length <= 256
                when 'tag' then value.is_a?(String) && value.length.between?(1, 256)
                end
        fail_command('invalid_arguments', 'Invalid property: ' + key) unless valid
        fail_command('invalid_arguments', 'NUL characters are not allowed') if value.is_a?(String) && value.include?("\0")
      end
      editable(entities, properties == {'locked' => false})
      tag = @model.layers[properties['tag']] if properties.key?('tag')
      material = @model.materials[properties['material']] if properties['material']
      fail_command('tag_not_found', 'Tag must already exist by its exact internal name') if properties.key?('tag') && !tag
      fail_command('material_not_found', 'Material must already exist by its exact internal name') if properties['material'] && !material
      keys = properties.keys.sort
      before = entities.map { |e| {'persistent_id' => e.persistent_id.to_s, 'properties' => properties_of(e, keys)} }
      planned = properties.each_with_object({}) { |(key, value), h| h[key] = value.is_a?(String) ? short(value) : value }
      data = checked('dry_run' => dry, 'undoable' => !dry, 'before' => before, 'planned' => planned)
      return data if dry
      operation('Update properties') do
        entities.each do |e|
          e.name = properties['name'] if properties.key?('name')
          e.layer = tag if properties.key?('tag')
          e.material = material if properties.key?('material')
          e.hidden = properties['hidden'] if properties.key?('hidden')
          e.locked = properties['locked'] if properties.key?('locked')
        end
        after = entities.map { |e| {'persistent_id' => e.persistent_id.to_s, 'properties' => properties_of(e, keys)} }
        fail_command('postcondition_failed', 'An object did not retain its requested properties') unless after.all? { |item| item['properties'] == planned }
        data.merge('after' => after)
      end
    end

    def invertible(transform)
      a = transform.to_a
      fail_command('invalid_transform', 'Non-finite edit transform') unless a.length == 16 && a.all? { |v| v.to_f.finite? }
      x, y, z = a[0, 3], a[4, 3], a[8, 3]
      determinant = x[0] * (y[1] * z[2] - y[2] * z[1]) - y[0] * (x[1] * z[2] - x[2] * z[1]) + z[0] * (x[1] * y[2] - x[2] * y[1])
      scale = [x, y, z].map { |v| Math.sqrt(v.inject(0.0) { |sum, n| sum + n * n }) }.inject(:*)
      fail_command('invalid_transform', 'Edit transform is singular or nearly singular') unless scale > 0 && determinant.abs > scale * 1.0e-12 && a[15] != 0
      transform
    end

    def position(entity, edit)
      world = edit * entity.transformation
      {'persistent_id' => entity.persistent_id.to_s,
       'model_origin_mm' => world.origin.to_a.map { |v| (v.to_f * 25.4).round(6) }}
    end

    def move(args, dry)
      entities = targets(args['entity_ids'])
      editable(entities)
      delta = args['delta_mm']
      unless delta.is_a?(Array) && delta.length == 3 && delta.all? { |v| v.is_a?(Numeric) && v.to_f.finite? && v.abs <= 1_000_000_000 }
        fail_command('invalid_arguments', 'delta_mm needs three finite numbers within +/- 1000000000 mm')
      end
      edit = invertible(@model.edit_transform)
      vector = Geom::Vector3d.new(delta.map { |v| v.to_f / 25.4 }).transform(edit.inverse)
      translation = Geom::Transformation.translation(vector)
      before = entities.map { |e| position(e, edit) }
      planned = before.map { |item| {'persistent_id'=>item['persistent_id'], 'model_origin_mm'=>item['model_origin_mm'].zip(delta).map { |v,d| (v+d).round(6) }} }
      data = checked('dry_run' => dry, 'undoable' => !dry, 'delta_mm' => delta, 'before' => before, 'planned_after'=>planned)
      return data if dry
      return data.merge('after' => before, 'undoable' => false, 'no_change' => true) if delta.all? { |v| v == 0 }
      operation('Move instances') do
        entities.each { |e| e.transformation = translation * e.transformation }
        after = entities.map { |e| position(e, edit) }
        matches = after.zip(planned).all? { |a,b| a['model_origin_mm'].zip(b['model_origin_mm']).all? { |x,y| (x-y).abs <= 0.0001 + y.abs * 1.0e-12 } }
        fail_command('postcondition_failed', 'Object positions did not match the model-axis movement') unless matches
        data.merge('after' => after)
      end
    end

    def camera_state(camera)
      {'eye_mm' => camera.eye.to_a.map { |v| (v.to_f * 25.4).round(6) },
       'target_mm' => camera.target.to_a.map { |v| (v.to_f * 25.4).round(6) },
       'up' => camera.up.to_a, 'perspective' => camera.perspective?,
       'fov_degrees' => camera.perspective? ? camera.fov : nil,
       'height_mm' => camera.perspective? ? nil : camera.height.to_f * 25.4,
       'aspect_ratio' => camera.aspect_ratio}
    end

    def camera_copy(camera)
      fail_command('unsupported_camera', 'Two-point perspective and matched-photo cameras are not supported') if camera.is_2d?
      copy = Sketchup::Camera.new(camera.eye, camera.target, camera.up, camera.perspective?, camera.fov)
      copy.aspect_ratio = camera.aspect_ratio
      copy.height = camera.height unless camera.perspective?
      copy.description = camera.description
      copy
    end

    def camera_command(args, dry, preset)
      view = @model.active_view
      previous = camera_copy(view.camera)
      before = camera_state(previous)
      if preset
        direction, up = case args['preset']
                        when 'top' then [[0, 0, 1], [0, 1, 0]]
                        when 'front' then [[0, -1, 0], [0, 0, 1]]
                        when 'right' then [[1, 0, 0], [0, 0, 1]]
                        when 'isometric' then [[1, -1, 1], [0, 0, 1]]
                        else fail_command('invalid_arguments', 'Invalid view preset')
                        end
        box = @model.bounds
        target = box.empty? ? Geom::Point3d.new(0, 0, 0) : box.center
        distance = box.empty? ? 100.0 : [box.diagonal.to_f * 2, 1.0].max
        eye = Geom::Point3d.new(target.to_a.zip(direction).map { |v, d| v + d * distance })
        camera = Sketchup::Camera.new(eye, target, Geom::Vector3d.new(up), false)
        data = checked('dry_run' => dry, 'undoable' => false, 'before' => before, 'preset' => args['preset'])
      else
        scope = args['scope']
        fail_command('invalid_arguments', 'Invalid zoom scope') unless %w[model entities].include?(scope)
        entities = targets(args['entity_ids'], scope == 'model')
        fail_command('invalid_arguments', 'Model zoom requires empty entity_ids') if scope == 'model' && !entities.empty?
        data = checked('dry_run' => dry, 'undoable' => false, 'before' => before, 'scope' => scope, 'entity_ids' => args['entity_ids'])
      end
      return data if dry
      begin
        if preset
          view.camera = camera
          view.zoom_extents
        elsif scope == 'model'
          view.zoom_extents
        else
          view.zoom(entities)
        end
        checked(data.merge('after' => camera_state(view.camera)))
      rescue StandardError => error
        begin
          view.camera = previous
        rescue StandardError
          fail_command('outcome_unknown', 'Could not restore the previous camera')
        end
        raise error
      end
    end
  end
  class InlineCommandExecutor < CommandExecutor
    private
    def operation(_label); checked(yield); end
  end
end
require_relative 'native_self_test'
