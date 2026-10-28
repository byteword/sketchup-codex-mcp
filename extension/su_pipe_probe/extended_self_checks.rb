# encoding: UTF-8
module SUPipeProbe
  module ExtendedSelfChecks
    CHECKS=%w[polygon planar_face construction_points freehand bezier arc_center arc_two_point arc_three_point offset polyhedron revolution sweep component_convert component_instantiate component_replace shared_component_edit component_metadata component_explode raw_group raw_point_move raw_vertex_move raw_face_rebuild raw_reverse raw_properties smoothing surface_simplify material_lifecycle tag_lifecycle resource_query mirror camera_configure].freeze
    private
    def geometry(kind,options)
      created('create_geometry','kind'=>kind,'name'=>'MCP temporary '+kind,'options'=>options)
    end
    def raw(id,action,options,extra={})
      command('edit_geometry',{'container_id'=>id,'action'=>action,'options'=>options}.merge(extra))
    end
    def resource(kind,action,options)
      command('manage_resource','kind'=>kind,'action'=>action,'options'=>options)
    end
    def run_extended_checks(camera)
      square=[[0,0,0],[1000,0,0],[1000,1000,0],[0,1000,0]]
      polygon=step('polygon') { geometry('polygon','origin_mm'=>[0,0,0],'plane'=>'XY','radius_mm'=>100,'sides'=>6) }
      face=step('planar_face') { id=geometry('face','points_mm'=>square); near(query(id)['direct_geometry']['face_area_mm2'],1_000_000); id }
      pts=step('construction_points') { geometry('points','points_mm'=>[[0,0,0],[100,200,300]]) }
      line=step('freehand') { geometry('freehand','points_mm'=>[[0,0,0],[100,0,0],[100,100,0]]) }
      step('bezier') { id=geometry('bezier','points_mm'=>[[0,0,0],[100,100,0],[200,0,0]],'segments'=>12); require_true(query(id)['direct_geometry']['by_type']['Edge']==12,'Bezier precision mismatch') }
      step('arc_center') { geometry('arc_center','origin_mm'=>[0,0,0],'plane'=>'XY','radius_mm'=>100,'start_degrees'=>0,'sweep_degrees'=>90,'segments'=>12) }
      step('arc_two_point') { geometry('arc_two_point','points_mm'=>[[0,0,0],[200,0,0]],'plane'=>'XY','bulge_mm'=>50,'segments'=>12) }
      step('arc_three_point') { geometry('arc_three_point','points_mm'=>[[100,0,0],[0,100,0],[-100,0,0]],'segments'=>12) }
      step('offset') { id=geometry('offset','points_mm'=>square,'distance_mm'=>100); near(query(id)['direct_geometry']['face_area_mm2'],1_440_000) }
      step('polyhedron') { id=geometry('polyhedron','points_mm'=>[[0,0,0],[100,0,0],[0,100,0],[0,0,100]],'faces'=>[[0,2,1],[0,1,3],[1,2,3],[2,0,3]]); require_true(query(id)['manifold'],'Polyhedron is not solid') }
      step('revolution') { geometry('revolve','points_mm'=>[[0,0,0],[100,0,0],[100,0,100],[0,0,100]],'pivot_mm'=>[0,0,0],'axis'=>[0,0,1],'sweep_degrees'=>360,'segments'=>12) }
      step('sweep') { geometry('sweep','points_mm'=>square,'path_mm'=>[[500,500,0],[500,500,1000]]) }
      component=step('component_convert') { command('component','action'=>'convert','options'=>{'entity_ids'=>[polygon]})['created'].first['persistent_id'] }
      defid='definition:'+@model.find_entity_by_persistent_id(component.to_i).definition.entityID.to_s
      instance=step('component_instantiate') { command('component','action'=>'instantiate','options'=>{'definition_id'=>defid,'origin_mm'=>[2000,0,0]})['created'].first['persistent_id'] }
      step('component_replace') { command('component','action'=>'replace','options'=>{'definition_id'=>defid,'entity_ids'=>[instance]}) }
      step('shared_component_edit') do
        begin
          raw(component,'add_points','points_mm'=>[[0,0,0]])
          raise 'Shared edit executed without explicit confirmation'
        rescue CommandError => error
          raise unless error.code=='shared_definition'
        end
        raw(component,'add_points',{'points_mm'=>[[0,0,0]]},'affect_all_instances'=>true)
        require_true(query(instance)['direct_geometry']['by_type']['ConstructionPoint']==1,'Shared component did not update')
      end
      step('component_metadata') { command('component','action'=>'metadata','options'=>{'definition_id'=>defid,'description'=>'MCP temporary acceptance','affect_all_instances'=>true}) }
      exploded=step('component_explode') { command('component','action'=>'explode','options'=>{'entity_ids'=>[instance]}) }
      step('raw_group') { command('group_entities','entity_ids'=>exploded['result_paths'].map(&:last)) }
      step('raw_point_move') do
        p=query(pts)['direct_children'].find { |e| e['type']=='ConstructionPoint' }
        raw(pts,'move_points','entity_ids'=>[p['persistent_id']],'delta_mm'=>[100,0,0])
        near(@reader.call('get_entity_info',p)['item']['position_mm'][0],100)
        raw(pts,'erase','entity_ids'=>[p['persistent_id']])
      end
      step('raw_vertex_move') do
        edge=query(line)['direct_children'].find { |e| e['type']=='Edge' }
        raw(line,'move_vertices','vertex_moves'=>[{'edge_id'=>edge['persistent_id'],'endpoint'=>'start','position_mm'=>[-100,0,0]}])
        near(@reader.call('get_entity_info',edge)['item']['endpoints_mm'].first[0],-100)
      end
      step('raw_face_rebuild') do
        children=query(face)['direct_children']; f=children.find { |e| e['type']=='Face' }; edges=children.select { |e| e['type']=='Edge' }.map { |e| e['persistent_id'] }
        raw(face,'erase','entity_ids'=>[f['persistent_id']]); raw(face,'rebuild_faces','entity_ids'=>edges)
        near(query(face)['direct_geometry']['face_area_mm2'],1_000_000)
      end
      fid=query(face)['direct_children'].find { |e| e['type']=='Face' }['persistent_id']
      step('raw_reverse') { raw(face,'reverse_faces','entity_ids'=>[fid]) }
      step('raw_properties') { raw(face,'properties','entity_ids'=>[fid],'hidden'=>true); require_true(@reader.call('get_entity_info',{'instance_path'=>[face,fid]})['item']['hidden'],'Face visibility mismatch') }
      mesh=geometry('face','points_mm'=>square.first(3)); raw(mesh,'add_face','points_mm'=>[square[0],square[2],square[3]])
      internal=@model.find_entity_by_persistent_id(mesh.to_i).definition.entities.find { |e| e.typename=='Edge' && e.faces.length==2 }
      require_true(internal,'Test internal edge missing')
      step('smoothing') do
        raw(mesh,'soften','entity_ids'=>[internal.persistent_id.to_s],'angle_degrees'=>30)
        require_true(internal.soft? && internal.smooth?,'Softening flags not set')
        raw(mesh,'unsoften','entity_ids'=>[internal.persistent_id.to_s]); require_true(!internal.soft? && !internal.smooth?,'Softening flags not cleared')
      end
      step('surface_simplify') { raw(mesh,'simplify','entity_ids'=>[internal.persistent_id.to_s]); near(query(mesh)['direct_geometry']['face_area_mm2'],1_000_000) }
      # Names are unique to this run; no existing resource is renamed or purged.
      suffix=Process.pid.to_s+'-'+(@started_at*1_000_000).to_i.to_s
      material='MCP test material '+suffix; tag='MCP test tag '+suffix
      step('material_lifecycle') do
        resource('materials','create','name'=>material,'color_rgb'=>[40,80,120],'alpha'=>0.5)
        resource('materials','update','name'=>material,'color_rgb'=>[120,80,40])
        raw(face,'properties','entity_ids'=>[fid],'material'=>material,'back_material'=>material)
        raw(face,'properties','entity_ids'=>[fid],'material'=>nil,'back_material'=>nil)
        resource('materials','delete','name'=>material)
      end
      step('tag_lifecycle') do
        resource('tags','create','name'=>tag); resource('tags','update','name'=>tag,'visible'=>false)
        command('update_entity_properties','entity_ids'=>[face],'properties'=>{'tag'=>tag})
        resource('tags','delete','name'=>tag)
        require_true(@model.find_entity_by_persistent_id(face.to_i).layer==@model.layers[0],'Deleted tag did not preserve/reassign geometry')
      end
      step('resource_query') { %w[materials tags definitions scenes].each { |kind| @reader.call('get_resources','kind'=>kind,'limit'=>25) } }
      step('mirror') { command('mirror_entities','entity_ids'=>[face],'pivot_mm'=>[0,0,0],'axis'=>'X'); near(query(face)['model_bounds']['max'][0],0) }
      if camera
        step('camera_configure') { command('configure_camera','eye_mm'=>[5000,-5000,5000],'target_mm'=>[0,0,0],'up'=>[0,0,1],'perspective'=>false,'height_mm'=>10000) }
      else @checks<<{'name'=>'camera_configure','status'=>'skipped','reason'=>'Unsupported special camera'} end
    end
  end
end
