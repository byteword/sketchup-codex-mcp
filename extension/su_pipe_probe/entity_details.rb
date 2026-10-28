# encoding: UTF-8
module SUPipeProbe
  module EntityDetails
    private
    def specific_entity(args)
      path = args['instance_path']
      unless path.is_a?(Array) && path.length.between?(1,32) && path.all? { |id| id.is_a?(String) && id.match(/\A[1-9][0-9]{0,18}\z/) }
        raise ArgumentError,'Provide a nonempty instance_path of at most 32 persistent IDs'
      end
      collection,transform = @model.entities,Geom::Transformation.new
      entity = nil
      path.each_with_index do |id,index|
        entity = @model.find_entity_by_persistent_id(id.to_i)
        raise ArgumentError,'Instance path is stale or has the wrong parent' unless entity && entity.valid? && entity.parent == collection.parent
        if index < path.length-1
          raise ArgumentError,'Intermediate path members must be groups/components' unless %w[Group ComponentInstance].include?(entity.typename)
          transform = transform*entity.transformation
          collection = entity.definition.entities
        end
      end
      item = entity_info(entity,transform).merge('instance_path'=>path,'parent_path'=>path[0...-1])
      if %w[Group ComponentInstance].include?(entity.typename)
        geometry = entity.definition.entities
        world = transform*entity.transformation
        offset,limit = args.fetch('child_offset',0),args.fetch('child_limit',25)
        raise ArgumentError,'Invalid child page' unless offset.is_a?(Integer) && offset.between?(0,1_000_000) && limit.is_a?(Integer) && limit.between?(1,25)
        stop = [offset+limit,geometry.length].min
        item['direct_children'] = (offset...stop).map { |index| e=geometry[index]; identity(e).merge('instance_path'=>path+[persistent_id(e)]) }
        item['child_offset'] = offset
        item['next_child_offset'] = stop < geometry.length ? stop : nil
        item['child_entity_count'] = geometry.length
        item['direct_geometry'] = geometry_metrics(geometry,world)
        item['manifold'] = entity.manifold? if geometry.length <= 5000 && entity.respond_to?(:manifold?)
      elsif entity.typename == 'Face'
        item['area_mm2'] = entity.area(transform).to_f*25.4**2
        item['vertices_mm'] = entity.outer_loop.vertices.first(128).map { |v| point(v.position.transform(transform)) }
        item['hole_count'] = entity.loops.length-1
      elsif entity.typename == 'Edge'
        item['length_mm'] = entity.length(transform).to_f*25.4
        item['endpoints_mm'] = [entity.start.position,entity.end.position].map { |p| point(p.transform(transform)) }
        item['soft'] = entity.soft?
        item['smooth'] = entity.smooth?
        item['curve_type'] = entity.curve && entity.curve.typename
        item['adjacent_face_ids'] = entity.faces.map { |f| f.persistent_id.to_s }
      elsif entity.typename == 'ConstructionPoint'
        item['position_mm'] = point(entity.position.transform(transform))
      end
      base.merge('edit_context'=>edit_context,'item'=>item,
        'notes'=>['Lengths in mm, areas in mm2. Direct geometry excludes nested groups/components; complete describes the aggregation limit.',
          'Bounds enclose transformed bounding-box corners. Raw faces/edges can be addressed through direct_children paths. No selection or edit-path changes.'])
    end

    def geometry_metrics(collection,transform)
      scanned,area,length = 0,0.0,0.0
      counts = Hash.new(0)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC)+0.15
      collection.each do |entity|
        break if scanned >= 5000 || (scanned%64 == 0 && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline)
        counts[entity.typename] += 1
        area += entity.area(transform).to_f*25.4**2 if entity.typename == 'Face'
        length += entity.length(transform).to_f*25.4 if entity.typename == 'Edge'
        scanned += 1
      end
      {'face_area_mm2'=>area,'edge_length_mm'=>length,'by_type'=>counts,'scanned'=>scanned,
       'total'=>collection.length,'complete'=>scanned == collection.length,'scope'=>'direct_children'}
    end
  end
end
