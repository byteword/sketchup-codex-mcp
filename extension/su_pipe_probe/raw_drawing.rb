# encoding: UTF-8
module SUPipeProbe
  module RawDrawing
    private
    def drawing_grouping(args,solid=false)
      mode=args.fetch('grouping','group')
      fail_command('invalid_arguments','grouping must be auto, group or none') unless %w[auto group none].include?(mode)
      mode=solid ? 'group' : 'none' if mode=='auto'
      fail_command('unsupported_geometry','Raw solids require a dedicated edit operation; choose group') if solid && mode=='none'
      mode
    end
    def draw_geometry(args,dry)
      kind=args['kind']; options=args['options']
      fail_command('invalid_arguments','options must be an object') unless options.is_a?(Hash)
      fields=args.merge('name'=>args.fetch('name','Drawing'),'grouping'=>args.fetch('grouping','auto'))
      if %w[rectangle circle polyline].include?(kind)
        required=kind=='polyline' ? %w[points_mm] : kind=='rectangle' ? %w[origin_mm plane size_mm] : %w[origin_mm plane radius_mm]
        fail_command('invalid_arguments','Unexpected drawing options') unless (options.keys-required-(kind=='circle' ? ['segments'] : [])).empty? && (required-options.keys).empty?
        drawing(fields.merge(options),dry,kind)
      else
        create_geometry(fields,dry)
      end
    end
    def raw_geometry(kind,points,arc,count,dry)
      editable([]); collection=@model.active_entities
      fail_command('geometry_too_large','Direct drawing context exceeds20000 entities') if collection.length>20000
      edit=invertible(@model.edit_transform); inverse=edit.inverse
      local=lambda { |p| Geom::Point3d.new(p.map { |n| n/25.4 }).transform(inverse) }
      # A native circular ArcCurve cannot represent an ellipse in a scaled edit space.
      if arc
        axes=[[1,0,0],[0,1,0],[0,0,1]].map { |v| Geom::Vector3d.new(v).transform(inverse) }
        scales=axes.map { |v| Math.sqrt(v.dot(v)) }
        fail_command('unsupported_transform','Native raw arcs require a uniformly scaled orthogonal edit context') unless scales.all? { |x| (x-scales[0]).abs<=1e-8*scales[0] } && axes.combination(2).all? { |a,b| a.dot(b).abs<=1e-8*scales[0]**2 }
      end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'kind'=>kind,'grouping'=>'none','parent_path'=>context_ids,
        'planned'=>{'point_count'=>points.length},'topology_may_merge'=>true)
      return data if dry
      operation('Draw raw '+kind) do
        before=collection.to_a; prior=before.map(&:persistent_id);prior_set=prior.each_with_object({}) { |id,h| h[id]=true }
        made=case kind
        when 'points' then points.map { |p| collection.add_cpoint(local.call(p)) }
        when 'polyline' then points.each_cons(2).map { |a,b| collection.add_line(local.call(a),local.call(b)) }
        when 'rectangle','face','polygon','offset' then [collection.add_face(points.map { |p| local.call(p) })]
        when 'circle'
          c,u,n,r,start,sweep=arc
          edges=collection.add_circle(local.call(c),Geom::Vector3d.new(n).transform(inverse),r/25.4*scales[0],count)
          [collection.add_face(edges)]
        else
          if arc
            c,u,n,r,start,sweep=arc
            if sweep<0; n=mul(n,-1);start=-start;sweep=-sweep;end
            local_u=Geom::Vector3d.new(u).transform(inverse);local_v=Geom::Vector3d.new(cross(n,u)).transform(inverse)
            local_n=Geom::Vector3d.new(cross(local_u.to_a,local_v.to_a))
            collection.add_arc(local.call(c),local_u,local_n,r/25.4*scales[0],start,start+sweep,count)
          else collection.add_curve(points.map { |p| local.call(p) }) end
        end
        fail_command('geometry_failed','Direct drawing returned no valid geometry') unless made && made.any? { |e| e && e.valid? }
        fresh=collection.to_a.reject { |e| prior_set[e.persistent_id] }
        fail_command('geometry_too_large','Direct drawing created too many entities') if fresh.length>2048
        fresh.each { |e| e.layer=@model.layers[0] }
        result=made.select { |e| e && e.valid? }.uniq.map { |e| {'persistent_id'=>e.persistent_id.to_s,'type'=>e.typename,'instance_path'=>context_ids+[e.persistent_id.to_s]} }
        data.merge('created'=>result,'new_entity_count'=>fresh.length,'reused_entity_ids'=>result.map { |e| e['persistent_id'] }.select { |id| prior_set[id.to_i] },
          'invalidated_entity_ids'=>before.zip(prior).reject { |e,id| e.valid? }.map { |e,id| id.to_s },'group_count'=>0)
      end
    end
  end
end
