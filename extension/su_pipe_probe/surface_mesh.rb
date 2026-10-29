# encoding: UTF-8
module SUPipeProbe
  module SurfaceMesh
    private
    # Generic bounded triangle surface. Terrain calculations belong in Probe JS.
    def surface_mesh(args,dry)
      editable([]);o=options(args,%w[points_mm triangles],%w[smooth material]);points=point_list(o['points_mm'],3,256);triangles=o['triangles']
      fail_command('invalid_arguments','Provide1..256 zero-based triangles') unless triangles.is_a?(Array) && triangles.length.between?(1,256)
      fail_command('invalid_geometry','Duplicate mesh points') unless points.uniq.length==points.length
      edges={};seen={};used={}
      triangles.each do |t|
        fail_command('invalid_geometry','Each triangle needs three distinct valid indices') unless t.is_a?(Array) && t.length==3 && t.uniq.length==3 && t.all? { |i| i.is_a?(Integer) && i.between?(0,points.length-1) }
        key=t.sort;fail_command('invalid_geometry','Duplicate triangle') if seen[key];seen[key]=true
        a,b,c=t.map { |i| points[i] };fail_command('invalid_geometry','Degenerate or tiny triangle') if norm(cross(sub(b,a),sub(c,a)))<0.01
        t.each { |i| used[i]=true }
        t.each_with_index do |a,i|
          b=t[(i+1)%3];k=[a,b].sort;pair=edges[k] ||= []
          fail_command('invalid_geometry','Non-manifold or inconsistently oriented mesh edge') if pair.length>=2 || pair.include?([a,b])
          pair<<[a,b]
        end
      end
      fail_command('invalid_geometry','Unused mesh points') unless used.length==points.length
      mode=drawing_grouping(args);smooth=bool_option(o,'smooth');material=material_value(o['material']) if o.key?('material')
      name=label(args.fetch('name','Surface'));inverse=invertible(@model.edit_transform).inverse
      local=points.map { |p| Geom::Point3d.new(p.map { |v| v/25.4 }).transform(inverse) }
      fail_command('geometry_too_large','Raw drawing context exceeds20000 entities') if mode=='none' && @model.active_entities.length>20000
      data=checked('dry_run'=>dry,'undoable'=>!dry,'grouping'=>mode,'point_count'=>points.length,'triangle_count'=>triangles.length,
        'open_surface'=>edges.values.any? { |v| v.length==1 },'topology_may_merge'=>mode=='none')
      return data if dry
      operation('Draw triangle surface') do
        group=@model.active_entities.add_group if mode=='group'
        collection=group ? group.entities : @model.active_entities
        group.name=name if group;group.layer=@model.layers[0] if group
        before=collection.to_a;faces=[]
        triangles.each do |t|
          f=collection.add_face(t.map { |i| local[i] })
          fail_command('geometry_failed','Native mesh face creation failed') unless f && f.valid? && !before.include?(f) && !faces.include?(f)
          desired=cross(sub(local[t[1]].to_a,local[t[0]].to_a),sub(local[t[2]].to_a,local[t[0]].to_a))
          f.reverse! if dot(f.normal.to_a,desired)<0
          f.material=material if material;f.layer=@model.layers[0];faces<<f
        end
        fresh=collection.to_a-before
        fail_command('postcondition_failed','Surface intersected existing topology; choose an empty context or grouping=group') unless faces.all?(&:valid?) && fresh.count { |e| e.typename=='Face' }==triangles.length
        fresh.each do |e|
          e.layer=@model.layers[0]
          next unless e.typename=='Edge' && e.faces.length==2 && e.faces.all? { |f| faces.include?(f) }
          e.soft=smooth;e.smooth=smooth
        end
        made=group ? [group] : faces
        # A bounded summary avoids256 face IDs overflowing nested batch responses.
        data.merge('created'=>made.first(25).map { |e| {'persistent_id'=>e.persistent_id.to_s,'type'=>e.typename,'instance_path'=>context_ids+[e.persistent_id.to_s]} },
          'created_ids_truncated'=>made.length>25,'face_count'=>faces.length,'group_count'=>group ? 1 : 0)
      end
    end
  end
end
