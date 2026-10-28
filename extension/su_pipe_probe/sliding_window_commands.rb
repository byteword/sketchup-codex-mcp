# encoding: UTF-8
require_relative 'sliding_window_plan'
module SUPipeProbe
  module SlidingWindowCommands
    private
    def window_clock; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
    def window_budget!(started)
      fail_command('recipe_budget_exceeded','Four-second window recipe budget exceeded; entire change rolled back') if window_clock-started>4
    end
    def window_materials(value)
      keys=%w[frame glass seal hardware]
      fail_command('invalid_arguments','materials requires frame, glass, seal and hardware names') unless value.is_a?(Hash) && value.keys.sort==keys.sort
      Hash[keys.map do |key|
        name=label(value[key]); material=material_value(name)
        fail_command('material_not_found','Choose an existing model material: '+name) unless material
        [key,material]
      end]
    end
    def window_optimize(group,started)
      collection=group.entities; dissolve=[]; hide=[]
      collection.each do |edge|
        next unless edge.typename=='Edge'
        faces=edge.faces; next unless faces.length==2
        a,b=faces; next unless a.normal.dot(b.normal)>1-1e-10
        next unless a.vertices.all? { |v| (v.position-b.vertices.first.position).dot(b.normal).to_f.abs<1e-7 }
        next unless %w[material back_material layer hidden?].all? { |property| a.send(property)==b.send(property) }
        next unless faces.all? { |f| f.get_glued_instances.empty? }
        materials=[a.material,a.back_material,group.material].compact
        if materials.any? { |m| m.texture }
          hide<<edge
        else
          dissolve<<edge
        end
      end
      window_budget!(started)
      area=lambda { collection.select { |e| e.typename=='Face' }.inject(0.0) { |s,f| s+f.area.to_f } }
      before=area.call
      hide.each { |edge| edge.hidden=true }
      collection.erase_entities(dissolve) unless dissolve.empty?
      after=area.call
      fail_command('postcondition_failed','Window cleanup changed surface area') if (after-before).abs>[1e-7,before*1e-8].max
      fail_command('postcondition_failed','Window cleanup opened a solid') unless group.manifold?
      {'removed_coplanar_edges'=>dissolve.length,'hidden_textured_seams'=>hide.length}
    end
    def create_sliding_window(args,dry)
      plan_started=window_clock
      begin
        plan=SlidingWindowPlan.build(args)
      rescue ArgumentError => error
        fail_command('invalid_arguments',error.message)
      end
      name=label(args['name']); origin=numeric_triple(args,'origin_mm',-1_000_000_000,1_000_000_000)
      materials=window_materials(args['materials'])
      replacements=args.key?('replace_entity_id') ? targets([args['replace_entity_id']]) : []
      editable(replacements)
      edit=invertible(@model.edit_transform)
      preview=plan.reject { |key,_| key=='sections' }.merge('name'=>name,'origin_mm'=>origin,
        'materials'=>args['materials'],'replace_entity_ids'=>replacements.map { |e| e.persistent_id.to_s },
        'initial_face_count'=>plan['sections'].inject(0) { |s,m| s+m['faces'].length })
      data=checked('dry_run'=>dry,'undoable'=>!dry,'planned'=>preview)
      plan_ms=((window_clock-plan_started)*1000).round(3)
      return data.merge('plan_ms'=>plan_ms) if dry
      operation('Create two-panel sliding window') do
        started=window_clock; cleanup={'removed_coplanar_edges'=>0,'hidden_textured_seams'=>0}; sections=[]; used=[]
        parent=@model.active_entities.add_group
        validate_created(parent,'Group',used)
        parent.name,parent.layer,parent.material=name,@model.layers[0],nil
        parent.transformation=edit.inverse*Geom::Transformation.translation(origin.map { |v| v/25.4 })
        plan['sections'].each do |mesh|
          window_budget!(started)
          child=parent.entities.add_group
          valid=child && child.valid? && child.typename=='Group' && child.parent==parent.definition && child.persistent_id.to_i>0 && !used.include?(child.persistent_id.to_s)
          fail_command('postcondition_failed','Invalid window section') unless valid
          used<<child.persistent_id.to_s
          child.name={'fixed'=>'본틀_복열레일','left'=>'좌창짝_외측매립손잡이','right'=>'우창짝_외측매립손잡이'}[mesh['section']]
          child.layer,child.material=@model.layers[0],materials['frame']
          points=mesh['points'].map { |p| p.map { |v| v/25.4 } }
          mesh['faces'].each_with_index do |indices,index|
            window_budget!(started) if index%16==0
            face=child.entities.add_face(indices.map { |i| points[i] })
            fail_command('geometry_failed','Could not create window surface') unless face && face.valid?
            normal=planar_polygon(indices.map { |i| mesh['points'][i] })[3]
            face.reverse! if face.normal.dot(Geom::Vector3d.new(normal))<0
            fail_command('postcondition_failed','Window face orientation changed') unless face.normal.dot(Geom::Vector3d.new(normal))>0
            role=mesh['roles'][index]
            unless role=='frame'
              face.material=materials[role]; face.back_material=materials[role]
              fail_command('postcondition_failed','Window material did not match') unless face.material==materials[role] && face.back_material==materials[role]
            end
          end
          child.entities.each { |e| e.layer=@model.layers[0] }
          fail_command('geometry_failed','Window section is not a closed solid') unless child.manifold?
          sections<<[mesh,child]
        end
        geometry_ms=((window_clock-started)*1000).round(3)
        optimize_started=window_clock
        sections.each do |_mesh,child|
          value=window_optimize(child,started)
          value.each { |key,n| cleanup[key]+=n }
        end
        window_budget!(started)
        snapshot=instance_snapshot(parent,edit)
        expected_max=origin.zip(plan['size_axes_xyz_mm']).map { |a,b| a+b }
        box=snapshot['model_bounds']
        fail_command('postcondition_failed','Window outer dimensions did not match') unless box && same_numbers(box['min'],origin) && same_numbers(box['max'],expected_max)
        @model.active_entities.erase_entities(replacements) unless replacements.empty?
        fail_command('postcondition_failed','Replacement target was not erased') if replacements.any?(&:valid?)
        section_data=sections.map do |mesh,child|
          counts=Hash.new(0); child.entities.each { |e| counts[e.typename]+=1 }
          path=context_ids+[parent.persistent_id.to_s,child.persistent_id.to_s]
          handle=mesh['handle_bounds']
          {'section'=>mesh['section'],'persistent_id'=>child.persistent_id.to_s,'instance_path'=>path,
           'parent_path'=>path[0...-1],'solid'=>true,'geometry'=>counts,
           'handle_bounds_mm'=>handle && Hash[handle.map { |key,p| [key,p.zip(origin).map { |a,b| a+b }] }]}
        end
        checked(data.merge('created'=>[snapshot],'sections'=>section_data,'cleanup'=>cleanup,
          'timing_ms'=>{'plan'=>plan_ms,'geometry'=>geometry_ms,'cleanup'=>((window_clock-optimize_started)*1000).round(3),'native_total'=>((window_clock-started)*1000).round(3)},
          'notes'=>['One typed request and one operation/Undo. No per-face pipe calls or UI refresh. No explicit selection/camera changes; replaced selected objects leave selection. No automatic retry after an unknown outcome.']))
      end
    end
  end
end
