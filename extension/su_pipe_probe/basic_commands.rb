# encoding: UTF-8
module SUPipeProbe
  module BasicCommands
    private
    def finite_number(value, minimum, maximum)
      fail_command('invalid_arguments','Number outside supported range') unless value.is_a?(Numeric) && value.to_f.finite? && value >= minimum && value <= maximum
      value.to_f
    end

    def profile_plane(value)
      case value
      when 'XY' then [[1,0,0],[0,1,0],[0,0,1]]
      when 'XZ' then [[1,0,0],[0,0,1],[0,-1,0]]
      when 'YZ' then [[0,1,0],[0,0,1],[1,0,0]]
      else fail_command('invalid_arguments','plane must be XY, XZ or YZ')
      end
    end

    def wire_transform(transform)
      transform.to_a.each_with_index.map { |value,index| index.between?(12,14) ? value*25.4 : value }
    end

    def drawing(args,dry,kind)
      editable([])
      name = args['name']
      fail_command('invalid_arguments','Provide a name of 1..256 characters without NUL') unless name.is_a?(String) && name.length.between?(1,256) && !name.include?("\0")
      edit = invertible(@model.edit_transform)
      if kind == 'polyline'
        points = args['points_mm']
        fail_command('invalid_arguments','Provide 2..64 points') unless points.is_a?(Array) && points.length.between?(2,64)
        points = points.map { |p| numeric_triple({'point'=>p},'point',-1_000_000_000,1_000_000_000) }
        fail_command('invalid_arguments','Only open polylines with distinct points are supported') unless points.uniq.length == points.length
        lengths = points.each_cons(2).map { |a,b| Math.sqrt(a.zip(b).inject(0.0) { |s,(x,y)| s+(x-y)**2 }) }
        fail_command('invalid_arguments','Segments must be at least 1 mm') if lengths.any? { |v| v < 1 }
        origin = points.first
        local = points.map { |p| p.zip(origin).map { |x,o| (x-o)/25.4 } }
        planned = {'points_mm'=>points,'length_mm'=>lengths.inject(:+)}
      else
        origin = numeric_triple(args,'origin_mm',-1_000_000_000,1_000_000_000)
        u,v,normal = profile_plane(args['plane'])
        if kind == 'rectangle'
          size = args['size_mm']
          fail_command('invalid_arguments','Rectangle size needs width and height') unless size.is_a?(Array) && size.length == 2
          w,h = size.map { |n| finite_number(n,1,1_000_000) }
          local = [[0,0],[w,0],[w,h],[0,h]].map { |a,b| u.zip(v).map { |x,y| (a*x+b*y)/25.4 } }
          expected_area,count = w*h,4
          planned = {'plane'=>args['plane'],'size_mm'=>[w,h]}
        else
          radius = finite_number(args['radius_mm'],1,1_000_000)
          count = args.fetch('segments',24)
          fail_command('invalid_arguments','segments must be integer 8..128') unless count.is_a?(Integer) && count.between?(8,128)
          expected_area = count*0.5*radius**2*Math.sin(2*Math::PI/count)
          planned = {'plane'=>args['plane'],'radius_mm'=>radius,'segments'=>count}
        end
      end
      if drawing_grouping(args)=='none'
        if kind=='circle'
          arc=[origin,u,normal,radius,0,2*Math::PI]; raw_points=curve_points(arc,count)
        else
          arc=nil; raw_points=kind=='polyline' ? points : local.map { |p| p.zip(origin).map { |a,b| a*25.4+b } }
        end
        return raw_geometry(kind,raw_points,arc,count,dry)
      end
      data = checked('dry_run'=>dry,'undoable'=>!dry,'kind'=>kind,'planned'=>planned.merge('name'=>name,'origin_mm'=>origin,'parent_path'=>context_ids))
      return data if dry
      operation('Draw '+kind) do
        group = @model.active_entities.add_group
        validate_created(group,'Group',[])
        if kind == 'polyline'
          local.each_cons(2) { |a,b| group.entities.add_line(a,b) }
          fail_command('geometry_failed','Polyline intersected itself or generated unexpected topology') unless group.entities.count { |e| e.typename == 'Edge' } == points.length-1 && group.entities.none? { |e| e.typename == 'Face' }
        else
          face = if kind == 'circle'
                   edges = group.entities.add_circle([0,0,0],Geom::Vector3d.new(normal),radius/25.4,count)
                   group.entities.add_face(edges)
                 else
                   group.entities.add_face(local)
                 end
          fail_command('geometry_failed','Could not create a profile face') unless face && face.valid?
          face.reverse! if face.normal.dot(Geom::Vector3d.new(normal)) < 0
          unless group.entities.count { |e| e.typename == 'Face' } == 1 && group.entities.count { |e| e.typename == 'Edge' } == count && (face.area.to_f*25.4**2-expected_area).abs <= [0.001,expected_area*1.0e-8].max
            fail_command('postcondition_failed','Profile topology or area did not match request')
          end
        end
        group.name,group.layer,group.material = name,@model.layers[0],nil
        group.entities.each { |e| e.layer = @model.layers[0] }
        group.transformation = edit.inverse*Geom::Transformation.translation(origin.map { |n| n/25.4 })
        fail_command('postcondition_failed','Drawing lost its name or default tag') unless group.name == name && group.layer == @model.layers[0] && group.entities.all? { |e| e.layer == @model.layers[0] }
        data.merge('created'=>[instance_snapshot(group,edit)])
      end
    end

    def transform_instances(args,dry,kind)
      entities = targets(args['entity_ids'])
      editable(entities)
      edit = invertible(@model.edit_transform)
      pivot = numeric_triple(args,'pivot_mm',-1_000_000_000,1_000_000_000)
      point = Geom::Point3d.new(pivot.map { |n| n/25.4 })
      if kind == 'rotate'
        axis = numeric_triple(args,'axis',-1_000_000,1_000_000)
        magnitude = Math.sqrt(axis.inject(0.0) { |s,n| s+n*n })
        fail_command('invalid_arguments','axis must be nonzero') if magnitude < 1.0e-12
        angle = finite_number(args['angle_degrees'],-360,360)
        world = Geom::Transformation.rotation(point,Geom::Vector3d.new(axis.map { |n| n/magnitude }),angle*Math::PI/180)
        no_change = angle == 0
      else
        factors = numeric_triple(args,'factors',0.001,1000)
        world = Geom::Transformation.scaling(point,*factors)
        no_change = factors.all? { |n| n == 1 }
      end
      local = edit.inverse*world*edit
      desired = entities.map { |e| invertible(local*e.transformation) }
      before = entities.map { |e| instance_snapshot(e,edit).merge('local_transform'=>wire_transform(e.transformation)) }
      data = checked('dry_run'=>dry,'undoable'=>!dry && !no_change,'before'=>before,'planned_local_transforms'=>desired.map { |t| wire_transform(t) },'pivot_mm'=>pivot,'matrix_layout'=>'column_major','matrix_translation_unit'=>'mm')
      return data if dry
      return data.merge('no_change'=>true,'after'=>before) if no_change
      operation(kind.capitalize+' instances') do
        entities.zip(desired).each { |e,t| e.transformation = t }
        fail_command('postcondition_failed','Transform was not retained') unless entities.zip(desired).all? { |e,t| same_numbers(e.transformation.to_a,t.to_a) }
        data.merge('after'=>entities.map { |e| instance_snapshot(e,edit).merge('local_transform'=>wire_transform(e.transformation)) })
      end
    end

    def erase_instances(args,dry)
      entities = targets(args['entity_ids'])
      editable(entities)
      data = checked('dry_run'=>dry,'undoable'=>!dry,'before'=>entities.map { |e| instance_snapshot(e,@model.edit_transform) })
      return data if dry
      operation('Erase instances') do
        @model.active_entities.erase_entities(entities)
        fail_command('postcondition_failed','Some objects were not erased') if entities.any?(&:valid?)
        data.merge('erased_ids'=>args['entity_ids'])
      end
    end

    def group_instances(args,dry)
      ids(args['entity_ids'],25)
      entities=raw_targets(@model.active_entities,args['entity_ids'],%w[Group ComponentInstance Face Edge ConstructionPoint])
      editable(entities)
      # Refuse a partial connected surface: grouping must not tear unspecified
      # faces/edges away from user geometry or silently add extra targets.
      fail_command('connected_geometry','Include every boundary edge and adjacent face when grouping raw surfaces') if entities.any? do |e|
        e.typename=='Face' && (e.edges-entities).any? || e.typename=='Edge' && (e.faces-entities).any?
      end
      fail_command('geometry_too_large','Raw grouping supports faces with at most128 vertices') if entities.any? { |e| e.typename=='Face' && e.vertices.length>128 }
      edit=invertible(@model.edit_transform)
      sample=lambda do |e,t|
        points=case e.typename
          when 'Face' then e.vertices.map(&:position)
          when 'Edge' then [e.start.position,e.end.position]
          else [e.position]
        end
        points.flat_map { |p| p.transform(t).to_a }
      end
      before=entities.map do |e|
        {'persistent_id'=>e.persistent_id.to_s}.merge(e.respond_to?(:transformation) ? {'model_transform'=>wire_transform(edit*e.transformation)} : {'sample_mm'=>sample.call(e,edit).map { |n| n*25.4 }})
      end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'before'=>before,'matrix_layout'=>'column_major','matrix_translation_unit'=>'mm')
      return data if dry
      operation('Group instances') do
        group=@model.active_entities.add_group(entities)
        validate_created(group,'Group',args['entity_ids'].dup)
        group.name,group.layer='MCP Group',@model.layers[0]
        unless entities.zip(before).all? { |e,b| e.valid? && e.parent == group.definition && (b['model_transform'] ? same_numbers(wire_transform(edit*group.transformation*e.transformation),b['model_transform']) : same_numbers(sample.call(e,edit*group.transformation).map { |n| n*25.4 },b['sample_mm'])) }
          fail_command('postcondition_failed','Grouping changed a child world transform')
        end
        data.merge('created'=>[instance_snapshot(group,edit)],'child_paths'=>entities.map { |e| context_ids+[group.persistent_id.to_s,e.persistent_id.to_s] })
      end
    end

    def unique_instances(args,dry)
      entities=targets(args['entity_ids'])
      editable(entities)
      before=entities.map { |e| instance_snapshot(e,@model.edit_transform) }
      transforms=entities.map { |e| e.transformation.to_a }
      data=checked('dry_run'=>dry,'undoable'=>!dry,'before'=>before)
      return data if dry
      operation('Make instances unique') do
        entities.each { |e| e.make_unique if e.definition.instances.length > 1 }
        unless entities.zip(transforms).all? { |e,t| e.definition.instances.length == 1 && same_numbers(e.transformation.to_a,t) }
          fail_command('postcondition_failed','Definitions were not separated or transforms changed')
        end
        data.merge('after'=>entities.map { |e| instance_snapshot(e,@model.edit_transform) })
      end
    end

    def push_pull_profile(args,dry)
      entities = targets(args['entity_ids'])
      fail_command('invalid_arguments','Push/pull accepts one isolated group') unless entities.length == 1 && entities.first.typename == 'Group'
      editable(entities)
      group = entities.first
      fail_command('shared_definition','Make the profile group unique first') if group.definition.instances.length > 1
      fail_command('geometry_too_large','Profile has too many entities') if group.entities.length > 256
      faces = group.entities.select { |e| e.typename == 'Face' }
      unless faces.length == 1 && group.entities.all? { |e| %w[Face Edge].include?(e.typename) } && faces.first.edges.length == group.entities.count { |e| e.typename == 'Edge' }
        fail_command('unsupported_profile','Use one face and only its boundary edges in a group')
      end
      face = faces.first
      world = invertible(@model.edit_transform*group.transformation)
      axes = [[1,0,0],[0,1,0],[0,0,1]].map { |v| Geom::Vector3d.new(v).transform(world) }
      lengths = axes.map { |v| Math.sqrt(v.dot(v)) }
      uniform = lengths.all? { |n| (n-lengths[0]).abs <= lengths[0]*1.0e-8 } && axes.combination(2).all? { |a,b| a.dot(b).abs <= lengths[0]**2*1.0e-8 }
      fail_command('unsupported_profile_transform','Push/pull requires orthogonal uniform-scale geometry') unless uniform
      distance = finite_number(args['distance_mm'],-1_000_000,1_000_000)
      fail_command('invalid_arguments','Absolute distance must be at least 1 mm') if distance.abs < 1
      data = checked('dry_run'=>dry,'undoable'=>!dry,'distance_mm'=>distance,'before'=>instance_snapshot(group,@model.edit_transform))
      return data if dry
      direction = face.normal.transform(world).to_a
      direction_length = Math.sqrt(direction.inject(0.0) { |s,n| s+n*n })
      direction = direction.map { |n| n/direction_length }
      reference = face.vertices.first.position.transform(world).to_a
      operation('Push/pull profile') do
        face.pushpull(distance/25.4/lengths[0],false)
        group.entities.each { |e| e.layer = @model.layers[0] }
        fail_command('geometry_failed','Extrusion did not create a closed solid') unless group.manifold?
        projections = group.entities.select { |e| e.typename == 'Edge' }.flat_map { |e| [e.start.position,e.end.position] }.map do |point|
          point.transform(world).to_a.zip(reference,direction).inject(0.0) { |s,(v,o,n)| s+(v-o)*n*25.4 }
        end
        unless !projections.empty? && same_numbers([projections.min,projections.max],[[0,distance].min,[0,distance].max])
          fail_command('postcondition_failed','Extrusion distance did not match requested model-space millimeters')
        end
        data.merge('after'=>instance_snapshot(group,@model.edit_transform))
      end
    end
  end
end
