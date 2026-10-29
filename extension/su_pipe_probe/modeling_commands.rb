# encoding: UTF-8
module SUPipeProbe
  module ModelingCommands
    private
    def solid_operation(args,dry)
      root_edit!;kind=args['operation'];fail_command('invalid_arguments','Unknown solid operation') unless %w[union intersect subtract trim outer_shell].include?(kind)
      fail_command('pro_required','This native solid operation requires SketchUp Pro') unless kind=='outer_shell' || Sketchup.is_pro?
      a,b=targets([args['target_id'],args['tool_id']]);editable([a,b]);name=label(args.fetch('name','Solid result'))
      [a,b].each do |e|
        fail_command('invalid_geometry','Both inputs must be manifold solids with at most5000 direct faces/edges') unless e.manifold? && e.definition.entities.length<=5000 && e.definition.entities.all? { |x| %w[Face Edge].include?(x.typename) }
        fail_command('glued_entity','Unglue inputs before Boolean modeling') if e.respond_to?(:glued_to) && e.glued_to
        invertible(e.transformation)
      end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'operation'=>kind,'inputs_preserved'=>true,'difference_order'=>'target minus tool','target_id'=>args['target_id'],'tool_id'=>args['tool_id'])
      return data if dry
      operation('Solid '+kind) do
        # Native Boolean consumes its inputs. Copies isolate source definitions,
        # metadata and placements; never silently erase the user's operands.
        copies=[a,b].map do |source|
          copy=@model.entities.add_instance(source.definition,source.transformation);copy.make_unique;copy
        end
        result=if %w[subtract trim].include?(kind)
          copies[1].send(kind,copies[0])
        else copies[0].send(kind,copies[1]) end
        fail_command('geometry_failed','Native solid operation returned no closed result; disjoint/empty results are rejected') unless result && result.valid? && result.manifold?
        leftovers=copies.select { |e| e.valid? && e!=result };@model.entities.erase_entities(leftovers) unless leftovers.empty?
        result.name=name;result.layer=a.layer;result.material=a.material
        fail_command('postcondition_failed','Solid sources were unexpectedly consumed') unless a.valid? && b.valid?
        data.merge('created'=>[{'persistent_id'=>result.persistent_id.to_s,'instance_path'=>[result.persistent_id.to_s],'type'=>result.typename}],
          'volume_mm3'=>result.volume.to_f.abs*25.4**3,'notes'=>['New topology/IDs; native face material mapping must be reviewed. Custom source attributes are not copied to result.'])
      end
    end
    def intersect_faces(args,dry)
      root_edit!;target,cutter=targets([args['target_id'],args['cutter_id']]);editable([target,cutter])
      fail_command('shared_definition','Make target unique before inserting intersection edges') unless target.definition.instances.length==1
      [target,cutter].each do |e|
        fail_command('geometry_too_large','Intersection requires direct face/edge geometry, at most5000 items per operand') unless e.definition.entities.length<=5000 && e.definition.entities.all? { |x| %w[Face Edge].include?(x.typename) }
        invertible(e.transformation)
      end
      hidden=bool_option(args,'include_hidden');data=checked('dry_run'=>dry,'undoable'=>!dry,'grouping'=>'none','target_id'=>args['target_id']);return data if dry
      operation('Intersect faces') do
        transform=cutter.transformation.inverse*target.transformation
        edges=target.definition.entities.intersect_with(false,transform,target.definition.entities,transform,hidden,cutter.definition.entities.to_a)
        fail_command('geometry_failed','Intersection did not return an edge array') unless edges.is_a?(Array)
        fail_command('geometry_too_large','Intersection result exceeds2048 edges') if edges.length>2048
        edges.each { |e| e.layer=@model.layers[0] }
        data.merge('created'=>edges.select(&:valid?).map { |e| {'persistent_id'=>e.persistent_id.to_s,'type'=>'Edge','instance_path'=>[target.persistent_id.to_s,e.persistent_id.to_s]} },'no_change'=>edges.empty?)
      end
    end
    def face_texture(args,dry)
      root_edit!;path=args['instance_path'];face,parent=NativeQueries.new(@model).resolve(path)
      fail_command('unsupported_entity','Choose a face') unless face.typename=='Face'
      path[0...-1].each do |id|
        e=@model.find_entity_by_persistent_id(id.to_i);editable([e])
        fail_command('shared_definition','Make all face ancestors unique before changing UV mapping') unless e.definition.instances.length==1
      end
      action=args.fetch('action','position');fail_command('invalid_arguments','Unknown face texture action') unless %w[position clear].include?(action)
      if action=='clear'
        fail_command('invalid_arguments','Clear takes no material/mapping') if args.key?('material') || args.key?('mapping')
        front=bool_option(args,'front',true);data=checked('dry_run'=>dry,'undoable'=>!dry,'instance_path'=>path,'front'=>front,'note'=>'Clears direct assignment; a parent material can become visible.')
        return data if dry
        return operation('Clear face material') do
          front ? face.material=nil : face.back_material=nil
          fail_command('postcondition_failed','Face material was not cleared') unless (front ? face.material : face.back_material).nil?
          data
        end
      end
      material=material_value(args['material']);fail_command('invalid_material','Choose an existing textured material') unless material && material.texture
      front=bool_option(args,'front',true);pairs=args['mapping']
      fail_command('invalid_arguments','mapping needs1..4 point/UV pairs') unless pairs.is_a?(Array) && pairs.length.between?(1,4)
      mapping=pairs.flat_map do |pair|
        fail_command('invalid_arguments','Mapping pairs require point_mm and uv') unless pair.is_a?(Hash) && pair.keys.sort==%w[point_mm uv]
        uv=pair['uv'];fail_command('invalid_arguments','UV needs2 finite numbers') unless uv.is_a?(Array) && uv.length==2
        [mm_point(pair['point_mm']).transform(parent.inverse),Geom::Point3d.new(finite_number(uv[0],-1e6,1e6),finite_number(uv[1],-1e6,1e6),0)]
      end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'instance_path'=>path,'front'=>front);return data if dry
      operation('Position face texture') do
        ok=face.position_material(material,mapping,front)
        fail_command('postcondition_failed','Texture positioning failed') unless ok && (front ? face.material : face.back_material)==material
        data
      end
    end
    def component_behavior(args,dry)
      root_edit!;action=args['action']
      if action=='configure'
        o=options(args,%w[definition_id affect_all_instances],%w[is2d cuts_opening always_face_camera shadows_face_sun snapto no_scale_mask])
        fail_command('invalid_arguments','Definition behavior affects all instances; acknowledge explicitly') unless o['affect_all_instances']==true
        definition=definition_by_id(o['definition_id']);behavior=definition.behavior;keys=o.keys-%w[definition_id affect_all_instances]
        fail_command('invalid_arguments','No behavior properties') if keys.empty?
        definition.instances.each { |e| editable([e]) }
        keys.each do |k|
          if %w[snapto no_scale_mask].include?(k)
            max=k=='snapto' ? 3 : 127;fail_command('invalid_arguments','Invalid behavior mask/mode') unless o[k].is_a?(Integer) && o[k].between?(0,max)
          else bool_option(o,k) end
        end
        fail_command('invalid_arguments','Opening behavior requires is2d=true') if o.fetch('cuts_opening',behavior.cuts_opening?) && !o.fetch('is2d',behavior.is2d?)
      elsif %w[glue unglue].include?(action)
        o=options(args,['entity_id'],action=='glue' ? ['face_id'] : []);entity=direct_drawing(o['entity_id'],['ComponentInstance'])
        face=direct_drawing(o['face_id'],['Face']) if action=='glue'
      else fail_command('invalid_arguments','Unknown behavior action') end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'action'=>action);return data if dry
      operation('Component behavior') do
        if action=='configure'
          keys.each { |k| behavior.send(k+'=',o[k]) }
          keys.each do |k|
            getter=k=='snapto' ? k : k+'?'
            fail_command('postcondition_failed','Behavior did not match: '+k) unless behavior.send(getter)==o[k]
          end
        else
          entity.glued_to=face
          fail_command('postcondition_failed','Component did not retain requested face attachment') unless entity.glued_to==face
        end
        data
      end
    end
  end
end
