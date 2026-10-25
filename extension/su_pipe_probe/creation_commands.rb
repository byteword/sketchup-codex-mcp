# encoding: UTF-8
module SUPipeProbe
  # Included by CommandExecutor; all edits use its single-operation boundary.
  module CreationCommands
    private

    def numeric_triple(args, key, minimum, maximum)
      value = args[key]
      unless value.is_a?(Array) && value.length == 3 && value.all? { |n| n.is_a?(Numeric) && n.to_f.finite? && n >= minimum && n <= maximum }
        fail_command('invalid_arguments', key + ' requires three finite numbers within the supported range')
      end
      value.map(&:to_f)
    end

    def context_ids
      (@model.active_path || []).map { |entity| entity.persistent_id.to_s }
    end

    def same_numbers(actual, expected)
      actual.length == expected.length && actual.zip(expected).all? { |a,b| a.to_f.finite? && (a-b).abs <= 0.0001 + b.abs * 1.0e-12 }
    end

    def instance_snapshot(entity, edit)
      box = entity.definition.bounds
      bounds = nil
      unless box.empty?
        transform = edit * entity.transformation
        corners = 8.times.map { |i| box.corner(i).transform(transform).to_a.map { |n| (n.to_f * 25.4).round(6) } }
        bounds = {'min'=>corners.transpose.map(&:min), 'max'=>corners.transpose.map(&:max)}
      end
      position(entity, edit).merge('type'=>entity.typename, 'name'=>short(entity.name),
        'parent_path'=>context_ids, 'instance_path'=>context_ids + [entity.persistent_id.to_s],
        'model_bounds'=>bounds)
    end

    def validate_created(entity, type, used)
      valid = entity && entity.valid? && entity.typename == type && entity.parent == @model.active_entities.parent &&
        entity.persistent_id.to_i > 0 && !used.include?(entity.persistent_id.to_s)
      fail_command('postcondition_failed', 'The API did not return a distinct valid object in the current context') unless valid
      used << entity.persistent_id.to_s
    end

    def create_box(args, dry)
      editable([])
      origin = numeric_triple(args, 'origin_mm', -1_000_000_000, 1_000_000_000)
      size = numeric_triple(args, 'size_mm', 1, 1_000_000)
      name = args['name']
      unless name.is_a?(String) && name.length.between?(1, 256) && !name.include?("\0")
        fail_command('invalid_arguments', 'name requires 1 to 256 characters without NUL')
      end
      edit = invertible(@model.edit_transform)
      transform = edit.inverse * Geom::Transformation.translation(origin.map { |n| n / 25.4 })
      data = checked('dry_run'=>dry, 'undoable'=>!dry, 'kind'=>'box',
        'planned'=>{'name'=>name, 'origin_mm'=>origin, 'size_mm'=>size, 'parent_path'=>context_ids})
      return data if dry
      operation('Create box') do
        group = @model.active_entities.add_group
        validate_created(group, 'Group', [])
        x,y,z = size.map { |n| n / 25.4 }
        points = [[0,0,0],[x,0,0],[x,y,0],[0,y,0],[0,0,z],[x,0,z],[x,y,z],[0,y,z]]
        faces = [[0,3,2,1],[4,5,6,7],[0,1,5,4],[3,7,6,2],[0,4,7,3],[1,2,6,5]]
        normals = [[0,0,-1],[0,0,1],[0,-1,0],[0,1,0],[-1,0,0],[1,0,0]]
        faces.zip(normals).each do |indices, normal|
          face = group.entities.add_face(indices.map { |i| points[i] })
          fail_command('geometry_failed', 'Could not build a box face') unless face && face.valid?
          face.reverse! if face.normal.dot(Geom::Vector3d.new(normal)) < 0
          fail_command('geometry_failed', 'Box face orientation is invalid') unless face.normal.dot(Geom::Vector3d.new(normal)) > 0
        end
        group.entities.each { |entity| entity.layer = @model.layers[0] }
        group.name = name
        group.layer = @model.layers[0]
        group.material = nil
        group.transformation = transform
        unless group.name == name && group.layer == @model.layers[0] && group.material.nil? && group.entities.all? { |entity| entity.layer == @model.layers[0] }
          fail_command('postcondition_failed', 'Created box did not retain its name or Untagged assignments')
        end
        fail_command('geometry_failed', 'The box is not a closed six-face solid') unless group.manifold? && group.entities.count { |e| e.typename == 'Face' } == 6
        snapshot = instance_snapshot(group, edit)
        expected_max = origin.zip(size).map { |a,b| a+b }
        unless same_numbers(snapshot['model_bounds']['min'], origin) && same_numbers(snapshot['model_bounds']['max'], expected_max)
          fail_command('postcondition_failed', 'Created box bounds do not match the requested model-axis dimensions')
        end
        data.merge('created'=>[snapshot])
      end
    end

    def component_attributes(entity, budget)
      dictionaries = entity.attribute_dictionaries
      return [] unless dictionaries
      attributes = []
      dictionary_count = 0
      dictionaries.each do |dictionary|
        dictionary_count += 1
        fail_command('attributes_too_large', 'Use fewer sources or simpler instance attributes') if dictionary_count > 32
        dictionary.each_pair do |key, value|
          budget[:entries] += 1
          budget[:bytes] += JSON.generate([dictionary.name, key, value]).bytesize
          if budget[:entries] > 256 || budget[:bytes] > 64_000
            fail_command('attributes_too_large', 'Component instance attributes exceed the copy budget')
          end
          attributes << [dictionary.name, key, value]
        end
      end
      attributes
    end

    def duplicate_entities(args, dry)
      entities = targets(args['entity_ids'])
      editable(entities)
      delta = numeric_triple(args, 'delta_mm', -1_000_000_000, 1_000_000_000)
      edit = invertible(@model.edit_transform)
      vector = Geom::Vector3d.new(delta.map { |n| n / 25.4 }).transform(edit.inverse)
      translation = Geom::Transformation.translation(vector)
      budget = {:entries=>0, :bytes=>0}
      attributes = entities.map do |entity|
        if entity.respond_to?(:glued_to) && entity.glued_to
          fail_command('unsupported_glued_entity', 'Detach the source from its face in SketchUp before duplicating it')
        end
        entity.typename == 'ComponentInstance' ? component_attributes(entity, budget) : []
      end
      before = entities.map { |entity| position(entity, edit) }
      planned = before.map { |item| {'source_id'=>item['persistent_id'],
        'model_origin_mm'=>item['model_origin_mm'].zip(delta).map { |a,b| (a+b).round(6) }} }
      data = checked('dry_run'=>dry, 'undoable'=>!dry, 'delta_mm'=>delta, 'before'=>before, 'planned_after'=>planned)
      return data if dry
      operation('Duplicate instances') do
        used = entities.map { |e| e.persistent_id.to_s }
        created = entities.each_with_index.map do |source, i|
          desired = translation * source.transformation
          if source.typename == 'Group'
            copy = source.copy
            validate_created(copy, 'Group', used)
            copy.make_unique
            fail_command('postcondition_failed', 'Copied group definition was not made independent') if copy.definition == source.definition
            copy.transformation = desired
          else
            copy = @model.active_entities.add_instance(source.definition, desired)
            validate_created(copy, 'ComponentInstance', used)
            fail_command('postcondition_failed', 'Copied component does not share the source definition') unless copy.definition == source.definition
            attributes[i].each do |dictionary, key, value|
              copy.set_attribute(dictionary, key, value)
              unless copy.get_attribute(dictionary, key) == value
                fail_command('postcondition_failed', 'Copied component did not retain its instance attributes')
              end
            end
          end
          copy.name, copy.layer, copy.material = source.name, source.layer, source.material
          copy.hidden = source.hidden?
          copy.casts_shadows = source.casts_shadows?
          copy.receives_shadows = source.receives_shadows?
          unless same_numbers(copy.transformation.to_a, desired.to_a) &&
              properties_of(copy, %w[name hidden locked tag material]) == properties_of(source, %w[name hidden locked tag material]) &&
              copy.casts_shadows? == source.casts_shadows? && copy.receives_shadows? == source.receives_shadows?
            fail_command('postcondition_failed', 'Copied instance did not retain its transform or properties')
          end
          snapshot = instance_snapshot(copy, edit).merge('source_id'=>source.persistent_id.to_s)
          unless same_numbers(snapshot['model_origin_mm'], planned[i]['model_origin_mm'])
            fail_command('postcondition_failed', 'Copied position does not match the model-axis displacement')
          end
          snapshot
        end
        data.merge('created'=>created)
      end
    end
  end
end
