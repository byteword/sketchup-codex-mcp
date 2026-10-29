# encoding: UTF-8
module SUPipeProbe
  # Bounded native input for Probe-side texture math. No technique runs in Ruby.
  module TextureSnapshot
    def texture_snapshot(path)
      root_context!
      face,parent=resolve(path)
      fail_command('unsupported_entity','Choose a face') unless face.typename=='Face'
      fail_command('query_budget_exceeded','Texture snapshot is limited to1000 vertices') if face.vertices.length>1000
      local=face.outer_loop.vertices.map { |v| v.position.to_a.map(&:to_f) }
      points=local.map { |p| Geom::Point3d.new(p).transform(parent).to_a.map { |n| n.to_f*25.4 } }
      origin=points.first;u=unit(sub(points[1],origin))
      normal=points.drop(2).map { |p| cross(u,sub(p,origin)) }.find { |n| norm(n)>1e-6 }
      fail_command('invalid_geometry','Degenerate face frame') unless normal
      normal=unit(normal);v=cross(normal,u)
      xy=points.map { |p| d=sub(p,origin);[dot(d,u),dot(d,v)] }
      xmin,xmax=xy.map(&:first).minmax;ymin,ymax=xy.map(&:last).minmax
      fail_command('invalid_geometry','Face frame is too small') if xmax-xmin<0.01 || ymax-ymin<0.01
      origin=add(origin,add(mul(u,xmin),mul(v,ymin)))
      width,height=xmax-xmin,ymax-ymin
      samples=[[0,0],[width,0],[width,height],[0,height]].map { |x,y| add(origin,add(mul(u,x),mul(v,y))) }
      ancestors=path[0...-1].map do |id|
        e=@model.find_entity_by_persistent_id(id.to_i)
        {'id'=>id,'locked'=>e.locked?,'instances'=>e.definition.instances.length,'transform'=>e.transformation.to_a}
      end
      sides={}
      [true,false].each do |front|
        material=front ? face.material : face.back_material
        data={'material'=>material && material.name,'texture'=>nil,'uv'=>nil}
        if material && material.texture
          t=material.texture
          data['texture']={'width_mm'=>t.width.to_f*25.4,'height_mm'=>t.height.to_f*25.4,
            'image_width'=>t.image_width,'image_height'=>t.image_height,'filename'=>t.filename.to_s}
          helper=face.get_UVHelper(front,!front)
          data['uv']=samples.map do |p|
            q=front ? helper.get_front_UVQ(Geom::Point3d.new(p.map { |n| n/25.4 }).transform(parent.inverse)) : helper.get_back_UVQ(Geom::Point3d.new(p.map { |n| n/25.4 }).transform(parent.inverse))
            fail_command('invalid_uv','Texture mapping crosses infinity at a sample point') unless q.to_a.all? { |n| n.to_f.finite? } && q.z.abs>1e-12
            [q.x/q.z,q.y/q.z]
          end
        end
        sides[front ? 'front' : 'back']=data
      end
      result={'instance_path'=>path,'type'=>'Face','frame'=>{'origin_mm'=>origin,'u'=>u,'v'=>v,'normal'=>normal,'width_mm'=>width,'height_mm'=>height},
        'points_mm'=>samples,'sides'=>sides,'ancestors'=>ancestors,
        'loops_mm'=>face.loops.map { |loop| loop.vertices.map { |vertex| vertex.position.transform(parent).to_a.map { |n| n.to_f*25.4 } } }}
      fail_command('query_budget_exceeded','Texture snapshot exceeds24KB') if JSON.generate(result).bytesize>24_000
      result
    end
  end
end
