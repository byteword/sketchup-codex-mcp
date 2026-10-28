# encoding: UTF-8
require_relative 'geometry_plan'
module SUPipeProbe
  module ExtendedGeometry
    include GeometryPlan
    private
    def create_geometry(args,dry)
      editable([]); name=label(args['name']); kind=args['kind']; arc=nil; faces=nil; path=nil
      case kind
      when 'points','face','freehand','bezier'
        o=options(args,['points_mm'],kind=='bezier' ? ['segments'] : [])
        points=point_list(o['points_mm'],kind=='points' ? 1 : kind=='face' ? 3 : 2,kind=='bezier' ? 16 : 64)
        planar_polygon(points) if kind=='face'
        points=bezier_points(points,segments(o.fetch('segments',24))) if kind=='bezier'
      when 'polygon','arc_center'
        required=%w[origin_mm plane radius_mm]+(kind=='polygon' ? ['sides'] : %w[start_degrees sweep_degrees])
        o=options(args,required,kind=='polygon' ? [] : ['segments'])
        center=vector(o['origin_mm']); u,_v,n=profile_plane(o['plane']); radius=finite_number(o['radius_mm'],1,1_000_000)
        count=segments(o.fetch(kind=='polygon' ? 'sides' : 'segments',24))
        start=kind=='polygon' ? 0 : finite_number(o['start_degrees'],-360,360)*Math::PI/180
        sweep=kind=='polygon' ? 2*Math::PI : finite_number(o['sweep_degrees'],-360,360)*Math::PI/180
        fail_command('invalid_geometry','Arc sweep must be nonzero and less than360 degrees') if kind!='polygon' && (sweep.abs<0.001 || sweep.abs>=2*Math::PI)
        arc=[center,u,n,radius,start,sweep]; points=curve_points(arc,count)
        points.pop if kind=='polygon'
      when 'arc_three_point','arc_two_point'
        o=options(args,['points_mm']+(kind=='arc_two_point' ? %w[plane bulge_mm] : []),['segments'])
        points=point_list(o['points_mm'],kind=='arc_two_point' ? 2 : 3,kind=='arc_two_point' ? 2 : 3)
        if kind=='arc_two_point'
          _u,_v,n=profile_plane(o['plane']); a,b=points; chord=sub(b,a)
          fail_command('invalid_geometry','Arc endpoints must lie in the requested plane') if dot(chord,n).abs>0.001
          bulge=finite_number(o['bulge_mm'],-1_000_000,1_000_000)
          fail_command('invalid_geometry','Arc bulge too small') if bulge.abs<0.01
          points=[a,add(mul(add(a,b),0.5),mul(unit(cross(n,chord)),bulge)),b]
        end
        arc=arc_three(points); count=segments(o.fetch('segments',24)); points=curve_points(arc,count)
      when 'offset'
        o=options(args,%w[points_mm distance_mm]); distance=finite_number(o['distance_mm'],-1_000_000,1_000_000)
        points=offset_polygon(point_list(o['points_mm'],3,64),distance)
      when 'polyhedron'
        o=options(args,%w[points_mm faces]); points=point_list(o['points_mm'],4,256); faces=mesh_validate(points,o['faces'])
      when 'revolve'
        o=options(args,%w[points_mm pivot_mm axis sweep_degrees],['segments'])
        sweep=finite_number(o['sweep_degrees'],-360,360); fail_command('invalid_geometry','Revolution angle too small') if sweep.abs<0.1
        points,faces=revolution(point_list(o['points_mm'],3,32),vector(o['pivot_mm']),vector(o['axis']),sweep,segments(o.fetch('segments',24)))
      when 'sweep'
        o=options(args,%w[points_mm path_mm]); points=point_list(o['points_mm'],3,64); path=point_list(o['path_mm'],2,64)
        origin,_u,_v,n=planar_polygon(points)
        fail_command('invalid_geometry','Path must start on profile plane and perpendicular to it') unless dot(sub(path.first,origin),n).abs<=0.001 && dot(unit(sub(path[1],path.first)),n).abs>1-1e-8
      else fail_command('invalid_arguments','Unsupported geometry kind')
      end
      if %w[freehand bezier arc_center arc_two_point arc_three_point].include?(kind)
        fail_command('invalid_geometry','Curve has short or duplicate segments') if points.each_cons(2).any? { |a,b| norm(sub(a,b))<0.01 }
      end
      if path && path.each_cons(2).any? { |a,b| norm(sub(a,b))<0.01 }; fail_command('invalid_geometry','Path segment too short'); end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'kind'=>kind,'planned'=>{'point_count'=>points.length,'face_count'=>faces && faces.length,'sampled_points_mm'=>points.length<=128 ? points : nil})
      return data if dry
      edit=invertible(@model.edit_transform); origin=points.first
      local=lambda { |p| sub(p,origin).map { |x| x/25.4 } }
      operation('Create '+kind) do
        group=@model.active_entities.add_group; validate_created(group,'Group',[])
        collection=group.entities
        if faces
          faces.each { |indices| fail_command('geometry_failed','Could not create mesh face') unless collection.add_face(indices.map { |i| local.call(points[i]) }) }
          fail_command('geometry_failed','Result is not a closed solid') unless group.manifold?
        elsif kind=='points'
          points.each { |p| fail_command('geometry_failed','Point creation failed') unless collection.add_cpoint(local.call(p)) }
        elsif kind=='sweep'
          face=collection.add_face(points.map { |p| local.call(p) }); fail_command('geometry_failed','Profile creation failed') unless face
          edges=path.each_cons(2).map { |a,b| collection.add_line(local.call(a),local.call(b)) }
          fail_command('geometry_failed','Follow Me failed or did not create a closed solid') unless face.followme(edges) && group.manifold?
        elsif %w[face polygon offset].include?(kind)
          face=collection.add_face(points.map { |p| local.call(p) })
          fail_command('geometry_failed','Planar face creation failed') unless face && face.valid? && collection.count { |e| e.typename=='Face' }==1
        else
          # add_arc preserves ArcCurve identity; freehand/Bezier use a bounded sampled Curve.
          edges=if arc
            c,u,n,r,start,sweep=arc
            if sweep<0; n=mul(n,-1); start=-start; sweep=-sweep; end
            collection.add_arc(local.call(c),Geom::Vector3d.new(u),Geom::Vector3d.new(n),r/25.4,start,start+sweep,count)
          else collection.add_curve(points.map { |p| local.call(p) }) end
          fail_command('geometry_failed','Curve topology did not match requested precision') unless edges && edges.length==points.length-1 && collection.count { |e| e.typename=='Edge' }==points.length-1 && collection.none? { |e| e.typename=='Face' }
        end
        group.name,group.layer,group.material=name,@model.layers[0],nil
        collection.each { |e| e.layer=@model.layers[0] }
        group.transformation=edit.inverse*Geom::Transformation.translation(origin.map { |x| x/25.4 })
        data.merge('created'=>[instance_snapshot(group,edit)])
      end
    end

    def geometry_container(id,affect_all=false)
      group=targets([id]).first; editable([group])
      fail_command('invalid_arguments','affect_all_instances must be boolean') unless affect_all==true || affect_all==false
      shared=group.definition.instances.length>1
      fail_command('shared_definition','Make the container unique or explicitly confirm shared component editing') if shared && !(affect_all && group.typename=='ComponentInstance')
      fail_command('entity_locked','A shared component occurrence is locked') if shared && group.definition.instances.any?(&:locked?)
      fail_command('geometry_too_large','Container exceeds2048 direct entities') if group.definition.entities.length>2048
      [group,group.definition.entities,invertible(@model.edit_transform*group.transformation)]
    end
    def raw_targets(collection,values,types)
      ids(values,128)
      values.map do |id|
        e=@model.find_entity_by_persistent_id(id.to_i)
        fail_command('entity_context_mismatch','Raw child is stale or belongs to another definition') unless e && e.valid? && e.parent==collection.parent
        fail_command('unsupported_entity','Raw child type not supported by this action') unless types.include?(e.typename)
        e
      end
    end
    def edit_geometry(args,dry)
      group,collection,world=geometry_container(args['container_id'],args.fetch('affect_all_instances',false)); action=args['action']; items=[]; desired=nil; vertices=nil
      case action
      when 'add_points','add_lines','add_face'
        o=options(args,['points_mm']); points=point_list(o['points_mm'],action=='add_points' ? 1 : action=='add_lines' ? 2 : 3,64)
        planar_polygon(points) if action=='add_face'
        fail_command('invalid_geometry','Line segment too short') if action=='add_lines' && points.each_cons(2).any? { |a,b| norm(sub(a,b))<0.01 }
      when 'move_vertices'
        o=options(args,['vertex_moves']); moves=o['vertex_moves']
        fail_command('invalid_arguments','Provide1..64 vertex moves') unless moves.is_a?(Array) && moves.length.between?(1,64)
        vertices=[]; desired=[]
        moves.each do |m|
          fail_command('invalid_arguments','Invalid vertex move') unless m.is_a?(Hash) && m.keys.sort==%w[edge_id endpoint position_mm] && %w[start end].include?(m['endpoint'])
          edge=raw_targets(collection,[m['edge_id']],['Edge']).first; vertex=edge.send(m['endpoint'])
          fail_command('invalid_arguments','Same vertex specified twice') if vertices.include?(vertex)
          vertices<<vertex; desired<<Geom::Point3d.new(vector(m['position_mm']).map { |x| x/25.4 }).transform(world.inverse)
        end
      when 'simplify'
        o=options(args,['entity_ids']); items=raw_targets(collection,o['entity_ids'],['Edge'])
        fail_command('unsupported_profile','Simplify only coplanar two-face internal edges with identical face properties and no glued objects') unless items.all? do |e|
          fs=e.faces
          fs.length==2 && fs[0].normal.dot(fs[1].normal)>1-1e-10 && fs[0].vertices.all? { |v| (v.position-fs[1].vertices.first.position).dot(fs[1].normal).abs<1e-7 } &&
            %w[material back_material layer hidden?].all? { |p| fs[0].send(p)==fs[1].send(p) } && fs.all? { |f| f.get_glued_instances.empty? && [f.material,f.back_material].compact.none? { |m| m.texture } }
        end
        area_before=collection.select { |e| e.typename=='Face' }.inject(0.0) { |sum,f| sum+f.area(world).to_f }
      when 'erase','move_points','rebuild_faces','reverse_faces','properties','soften','unsoften'
        optional=case action; when 'move_points' then ['delta_mm']; when 'properties' then %w[material back_material hidden]; when 'soften' then ['angle_degrees']; else [] end
        o=options(args,['entity_ids']+(action=='move_points' ? ['delta_mm'] : []),optional-(action=='move_points' ? ['delta_mm'] : []))
        types=case action; when 'move_points' then ['ConstructionPoint']; when 'reverse_faces' then ['Face']; when 'rebuild_faces','soften','unsoften' then ['Edge']; else %w[Face Edge ConstructionPoint] end
        items=raw_targets(collection,o['entity_ids'],types)
        delta=vector(o['delta_mm']) if action=='move_points'
        angle=finite_number(o.fetch('angle_degrees',30),0,180) if action=='soften'
        if action=='properties'
          fail_command('invalid_arguments','No properties provided') if o.keys==['entity_ids']
          %w[material back_material].each { |p| material_value(o[p]) if o.key?(p) }
          fail_command('unsupported_entity','Back material applies only to faces') if o.key?('back_material') && items.any? { |e| e.typename!='Face' }
          fail_command('invalid_arguments','hidden must be boolean') if o.key?('hidden') && o['hidden']!=true && o['hidden']!=false
        end
      else fail_command('invalid_arguments','Unsupported raw geometry edit')
      end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'container_id'=>args['container_id'],'action'=>action,'target_ids'=>items.map { |e| e.persistent_id.to_s },'affected_direct_instances'=>group.definition.instances.length)
      return data if dry
      operation('Edit '+action) do
        case action
        when 'add_points','add_lines','add_face'
          local=points.map { |p| Geom::Point3d.new(p.map { |x| x/25.4 }).transform(world.inverse) }
          made=case action; when 'add_points' then local.map { |p| collection.add_cpoint(p) }; when 'add_lines' then local.each_cons(2).map { |a,b| collection.add_line(a,b) }; else [collection.add_face(local)] end
          fail_command('geometry_failed','Could not add raw geometry') unless made.all? { |e| e && e.valid? }
          made.each { |e| e.layer=@model.layers[0] }
          data['created_paths']=made.map { |e| context_ids+[group.persistent_id.to_s,e.persistent_id.to_s] }
        when 'erase','simplify'
          collection.erase_entities(items); fail_command('postcondition_failed','Raw entities were not erased') if items.any?(&:valid?)
          if action=='simplify'
            area_after=collection.select { |e| e.typename=='Face' }.inject(0.0) { |sum,f| sum+f.area(world).to_f }
            fail_command('postcondition_failed','Simplification changed surface area') if (area_after-area_before).abs>[1e-7,area_before*1e-8].max
          end
        when 'move_points'
          desired=items.map { |p| p.position.transform(world).offset(Geom::Vector3d.new(delta.map { |x| x/25.4 })).transform(world.inverse) }
          collection.transform_by_vectors(items,items.zip(desired).map { |p,q| q-p.position })
          fail_command('postcondition_failed','Point position did not match') unless items.zip(desired).all? { |p,q| p.position.distance(q)<1e-7 }
        when 'move_vertices'
          vectors=vertices.zip(desired).map { |v,p| p-v.position }
          collection.transform_by_vectors(vertices,vectors)
          fail_command('postcondition_failed','Vertex move did not match') unless vertices.zip(desired).all? { |v,p| v.valid? && v.position.distance(p)<1e-7 }
        when 'rebuild_faces'
          before=collection.select { |e| e.typename=='Face' }; items.each(&:find_faces)
          after=collection.select { |e| e.typename=='Face' }
          (after-before).each { |e| e.layer=@model.layers[0] }
          data['faces_added']=after.length-before.length
        when 'reverse_faces'
          previous=items.map { |e| e.normal.to_a }; items.each(&:reverse!)
          fail_command('postcondition_failed','Face normal was not reversed') unless items.zip(previous).all? { |e,n| e.normal.dot(Geom::Vector3d.new(n))<0 }
        when 'soften','unsoften'
          changed=items.select { |e| action=='unsoften' || (e.faces.length==2 && e.faces[0].normal.angle_between(e.faces[1].normal)<=angle*Math::PI/180+1e-10) }
          changed.each { |e| e.soft=(action=='soften'); e.smooth=(action=='soften') }
          fail_command('postcondition_failed','Edge smoothing flags did not match') unless changed.all? { |e| e.soft? == (action=='soften') && e.smooth? == (action=='soften') }
          data['changed_edge_ids']=changed.map { |e| e.persistent_id.to_s }
        when 'properties'
          items.each do |e|
            %w[material back_material].each { |p| e.send(p+'=',material_value(o[p])) if o.key?(p) }
            e.hidden=o['hidden'] if o.key?('hidden')
          end
          fail_command('postcondition_failed','Raw properties did not match') unless items.all? do |e|
            %w[material back_material].all? { |p| !o.key?(p) || e.send(p)==material_value(o[p]) } && (!o.key?('hidden') || e.hidden? == o['hidden'])
          end
        end
        checked(data.merge('child_entity_count'=>collection.length,'paths_may_be_stale'=>true))
      end
    end
  end
end
