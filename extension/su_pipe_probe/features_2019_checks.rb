# encoding: UTF-8
module SUPipeProbe
  module Features2019Checks
    CHECKS=%w[raw_face raw_reuse raw_arc linear_dimension radial_dimension leader_text text3d section_state entity_attributes native_volume classify_face solid_subtract].freeze
    private
    def run_features_2019_checks
      x=1_000_000.0
      face_id=step('raw_face') do
        result=command('draw_geometry','kind'=>'rectangle','grouping'=>'none','options'=>{'origin_mm'=>[x,0,0],'plane'=>'XY','size_mm'=>[1200,900]})
        id=result['created'].first['persistent_id'];e=@model.find_entity_by_persistent_id(id.to_i)
        require_true(e.typename=='Face' && e.parent==@model && result['group_count']==0,'Raw face was grouped');near(e.area*25.4**2,1_080_000);id
      end
      step('raw_reuse') do
        result=command('draw_geometry','kind'=>'polyline','options'=>{'points_mm'=>[[x,0,0],[x+1200,0,0]]})
        require_true(result['reused_entity_ids'].length==1 && result['new_entity_count']==0,'Existing edge was not reused')
      end
      arc_id=step('raw_arc') do
        result=command('draw_geometry','kind'=>'arc_center','options'=>{'origin_mm'=>[x+2000,0,0],'plane'=>'XY','radius_mm'=>300,'start_degrees'=>0,'sweep_degrees'=>180,'segments'=>12})
        id=result['created'].first['persistent_id'];require_true(@model.find_entity_by_persistent_id(id.to_i).curve.is_a?(Sketchup::ArcCurve),'Native ArcCurve missing');id
      end
      step('linear_dimension') { created('annotation','kind'=>'linear_dimension','options'=>{'start_mm'=>[x,0,0],'end_mm'=>[x+1200,0,0],'offset_mm'=>[0,-200,0]}) }
      step('radial_dimension') { created('annotation','kind'=>'radial_dimension','options'=>{'edge_id'=>arc_id,'leader_mm'=>[x+2400,400,0]}) }
      step('leader_text') { created('annotation','kind'=>'text','options'=>{'text'=>'MCP raw drawing','point_mm'=>[x,1000,0]}) }
      step('text3d') { created('annotation','kind'=>'text3d','options'=>{'text'=>'MCP','origin_mm'=>[x,1500,0],'height_mm'=>100}) }
      step('section_state') do
        previous=@model.entities.active_section_plane
        id=created('annotation','kind'=>'section','name'=>'MCP test section','options'=>{'point_mm'=>[x,0,500],'normal'=>[0,0,1],'active'=>true})
        section=@model.find_entity_by_persistent_id(id.to_i);require_true(section.active?,'Section did not activate')
        command('edit_annotation','action'=>'section','options'=>{'entity_id'=>id,'active'=>false})
        require_true(!section.active?,'Section did not deactivate');@model.entities.active_section_plane=previous
      end
      a=created('create_box','name'=>'MCP volume target','origin_mm'=>[x,3000,0],'size_mm'=>[100,100,100])
      b=created('create_box','name'=>'MCP volume cutter','origin_mm'=>[x+50,3000,0],'size_mm'=>[100,100,100])
      step('entity_attributes') do
        command('entity_attributes','action'=>'set','options'=>{'entity_id'=>a,'dictionary'=>'probe.test','key'=>'dimensions','value_json'=>'[100,100,100]'})
        values=@reader.call('model_query',{'query'=>'attributes','options'=>{'instance_path'=>[a],'dictionary'=>'probe.test'}})
        require_true(values['items'].first['value']==[100,100,100],'Attribute roundtrip failed')
      end
      step('native_volume') do
        result=@reader.call('model_query',{'query'=>'metrics','options'=>{'instance_path'=>[a]}})
        near(result['solid_volume_mm3'],1_000_000);near(result['area_mm2'],60_000)
      end
      step('classify_face') do
        result=@reader.call('model_query',{'query'=>'classify_point','options'=>{'instance_path'=>[face_id],'point_mm'=>[x+600,450,0]}})
        require_true(result['classification']=='PointInside','Point classification mismatch')
      end
      if Sketchup.is_pro?
        step('solid_subtract') do
          result=command('solid_operation','operation'=>'subtract','target_id'=>a,'tool_id'=>b)
          near(result['volume_mm3'],500_000)
          entity=@model.find_entity_by_persistent_id(result['created'].first['persistent_id'].to_i)
          near(entity.bounds.min.x*25.4,x);near(entity.bounds.max.x*25.4,x+50)
          require_true(@model.find_entity_by_persistent_id(a.to_i).valid? && @model.find_entity_by_persistent_id(b.to_i).valid?,'Original solids were consumed')
        end
      else
        @checks<<{'name'=>'solid_subtract','status'=>'skipped','reason'=>'SketchUp Pro required'}
      end
    end
  end
end
