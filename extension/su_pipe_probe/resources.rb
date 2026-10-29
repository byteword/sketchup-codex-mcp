# encoding: UTF-8
require 'json'
module SUPipeProbe
  class ResourceReader
    def initialize(model); @model=model; end
    def collection(kind)
      case kind
      when 'materials' then @model.materials
      when 'tags' then @model.layers
      when 'definitions' then @model.definitions
      when 'scenes' then @model.pages
      when 'styles' then @model.styles
      else raise ArgumentError,'Invalid resource kind'
      end
    end
    def item(kind,entity)
      # Definitions/materials/tags did not have persistent IDs in SketchUp2019.
      # Resource IDs are explicitly model-session-local, never drawing PIDs.
      data={'name'=>entity.name.to_s[0,256],'resource_id'=>kind+':'+entity.entityID.to_s}
      case kind
      when 'materials'
        data.merge!('color_rgb'=>[entity.color.red,entity.color.green,entity.color.blue],'alpha'=>entity.alpha,'textured'=>!entity.texture.nil?)
        t=entity.texture
        if t && t.respond_to?(:width)
          data['texture']={'width_mm'=>t.width.to_f*25.4,'height_mm'=>t.height.to_f*25.4,'image_width'=>t.image_width,'image_height'=>t.image_height,'filename'=>t.filename.to_s}
        end
      when 'tags' then data.merge!('visible'=>entity.visible?,'default'=>entity==@model.layers[0],'active'=>entity==@model.active_layer,'line_style'=>entity.respond_to?(:line_style) && entity.line_style ? entity.line_style.name : nil)
      when 'definitions' then data.merge!('definition_id'=>'definition:'+entity.entityID.to_s,'description'=>entity.description.to_s[0,1024],'group'=>entity.group?,'image'=>entity.image?,'instance_count'=>entity.count_instances)
      when 'styles'
        data.merge!('description'=>entity.description.to_s[0,1024],'path'=>entity.respond_to?(:path) ? entity.path.to_s[0,1024] : nil,
          'selected'=>entity==@model.styles.selected_style,'active_style_changed'=>@model.styles.active_style_changed)
      when 'scenes'
        flags=%w[camera axes hidden hidden_layers rendering_options section_planes shadow_info style hidden_geometry hidden_objects]
        data['saved_properties']=flags.select { |key| entity.respond_to?('use_'+key+'?') && entity.send('use_'+key+'?') }
        data['selected']=@model.pages.selected_page==entity if @model.pages.respond_to?(:selected_page)
        data['style_name']=entity.style && entity.style.name if entity.respond_to?(:style)
        data['transition_seconds']=entity.transition_time if entity.respond_to?(:transition_time)
        data['delay_seconds']=entity.delay_time if entity.respond_to?(:delay_time)
        data['include_in_animation']=entity.include_in_animation? if entity.respond_to?(:include_in_animation?)
        data.merge!('description'=>entity.description.to_s[0,1024],'use_camera'=>entity.use_camera?,'camera_only'=>camera_only?(entity),
          'camera'=>{'eye_mm'=>entity.camera.eye.to_a.map { |x| x*25.4 },'target_mm'=>entity.camera.target.to_a.map { |x| x*25.4 },'perspective'=>entity.camera.perspective?})
      end
      data
    end
    def camera_only?(page)
      flags=%w[use_axes? use_hidden? use_hidden_layers? use_rendering_options? use_section_planes? use_shadow_info? use_style? use_hidden_geometry? use_hidden_objects? use_environment?]
      page.use_camera? && flags.none? { |flag| page.respond_to?(flag) && page.send(flag) }
    end
    def call(args)
      kind=args['kind']; collection=collection(kind); offset=args.fetch('offset',0); limit=args.fetch('limit',25)
      raise ArgumentError,'Invalid resource page' unless offset.is_a?(Integer) && offset.between?(0,1_000_000) && limit.is_a?(Integer) && limit.between?(1,25)
      items=[]; scanned=0; deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+0.15; more=false
      collection.each_with_index do |e,i|
        if scanned>=20000 || Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline
          raise ArgumentError,'Resource page budget exceeded; use a smaller offset/model'
        end
        scanned+=1; next if i<offset
        if items.length>=limit; more=true; break; end
        candidate=item(kind,e)
        if JSON.generate('items'=>items+[candidate]).bytesize>38_000
          more=true; break
        end
        items<<candidate
      end
      {'kind'=>kind,'items'=>items,'offset'=>offset,'next_offset'=>more ? offset+items.length : nil,'collection_length'=>collection.length,'live_page'=>true}
    end
  end

  module ResourceCommands
    private
    def material_value(name)
      return nil if name.nil?
      label(name); value=@model.materials[name]; fail_command('material_not_found','Use an exact existing material name') unless value; value
    end
    def resource_collection(kind)
      ResourceReader.new(@model).collection(kind)
    end
    def manage_resource(args,dry)
      fail_command('context_mismatch','Resource changes require model root') unless context_ids.empty?
      editable([]); kind=args['kind']; action=args['action']; collection=resource_collection(kind)
      fail_command('invalid_arguments','Scenes use the scene tool') if kind=='scenes'
      fail_command('resource_too_large','Resource management limited to5000 entries') if collection.length>5000
      if action=='purge_unused'
        o=options(args,['confirm_model_wide']); fail_command('invalid_arguments','Explicit model-wide purge confirmation required') unless o['confirm_model_wide']==true
      else
        fail_command('invalid_arguments','Definitions support purge_unused only here') if kind=='definitions'
        required=['name']; optional=kind=='materials' ? %w[new_name color_rgb alpha] : %w[new_name visible line_style]
        o=options(args,required,action=='delete' ? [] : optional); name=label(o['name']); entity=collection[name]
        fail_command('resource_exists','Resource name already exists') if action=='create' && entity
        fail_command('resource_not_found','Resource not found by exact name') if action!='create' && !entity
        fail_command('invalid_arguments','Unsupported resource action') unless %w[create update delete].include?(action)
        if o.key?('new_name')
          label(o['new_name']); other=collection[o['new_name']]
          fail_command('resource_exists','New name already exists') if other && other!=entity
        end
        if o.key?('color_rgb')
          rgb=o['color_rgb']; fail_command('invalid_arguments','color_rgb needs three integers0..255') unless rgb.is_a?(Array) && rgb.length==3 && rgb.all? { |n| n.is_a?(Integer) && n.between?(0,255) }
        end
        finite_number(o['alpha'],0,1) if o.key?('alpha')
        fail_command('invalid_arguments','visible must be boolean') if o.key?('visible') && o['visible']!=true && o['visible']!=false
        if o.key?('line_style') && o['line_style']
          label(o['line_style']);line_style=@model.line_styles[o['line_style']]
          fail_command('resource_not_found','Line style must exist by exact name') unless line_style
        end
        if kind=='tags' && entity==@model.layers[0]
          fail_command('protected_resource','Layer0 properties cannot be changed')
        end
        fail_command('protected_resource','Active tag cannot be deleted or hidden') if kind=='tags' && entity==@model.active_layer && (action=='delete' || o['visible']==false)
        fail_command('invalid_arguments','Use name alone when creating; new_name is for update') if action=='create' && o.key?('new_name')
        fail_command('invalid_arguments','No update properties') if action=='update' && o.keys==['name']
      end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'kind'=>kind,'action'=>action,'before_count'=>collection.length)
      return data if dry
      operation('Manage '+kind) do
        if action=='purge_unused'
          collection.purge_unused
        elsif action=='delete'
          ok=kind=='tags' ? collection.remove(entity,false) : collection.remove(entity)
          fail_command('postcondition_failed','Resource deletion failed') unless ok && !collection[name]
        else
          entity=collection.add(name) if action=='create'
          fail_command('api_error','Could not create resource') unless entity
          entity.name=o['new_name'] if o.key?('new_name')
          entity.color=Sketchup::Color.new(*o['color_rgb']) if o.key?('color_rgb')
          entity.alpha=o['alpha'] if o.key?('alpha')
          entity.visible=o['visible'] if o.key?('visible')
          entity.line_style=line_style if o.key?('line_style')
          fail_command('postcondition_failed','Line style did not match') if o.key?('line_style') && entity.line_style!=line_style
          fail_command('postcondition_failed','Resource name changed unexpectedly') unless entity.name==(o['new_name'] || name)
          fail_command('postcondition_failed','Resource color did not match') if o.key?('color_rgb') && [entity.color.red,entity.color.green,entity.color.blue]!=o['color_rgb']
          fail_command('postcondition_failed','Resource transparency did not match') if o.key?('alpha') && (entity.alpha-o['alpha']).abs>1e-6
          fail_command('postcondition_failed','Tag visibility did not match') if o.key?('visible') && entity.visible?!=o['visible']
          data['item']=ResourceReader.new(@model).item(kind,entity)
        end
        data.merge('after_count'=>collection.length)
      end
    end

    def definition_by_id(id)
      fail_command('invalid_arguments','Use the definition_id returned by get_resources in this model session') unless id.is_a?(String) && id.match(/\Adefinition:[1-9][0-9]{0,18}\z/)
      fail_command('definition_too_large','Definition lookup limited to5000 entries') if @model.definitions.length>5000
      definition=@model.definitions.find { |d| 'definition:'+d.entityID.to_s==id }
      fail_command('definition_not_found','Choose a current non-group, non-image component definition ID') unless definition && definition.valid? && definition.typename=='ComponentDefinition' && @model.definitions.include?(definition) && !definition.group? && !definition.image?
      definition
    end
    def prevent_recursive_definition(definition)
      ancestors=(@model.active_path || []).map(&:definition); seen={}; pending=[definition]; scanned=0
      until pending.empty?
        d=pending.pop; next if seen[d.entityID]; seen[d.entityID]=true
        fail_command('recursive_definition','Definition would reference an edit ancestor') if ancestors.include?(d)
        d.entities.each do |e|
          scanned+=1; fail_command('definition_too_large','Dependency check exceeds20000 entities') if scanned>20000
          pending<<e.definition if %w[Group ComponentInstance].include?(e.typename)
        end
      end
    end
    def component(args,dry)
      action=args['action']; definition=nil; entities=[]
      case action
      when 'convert','explode'
        o=options(args,['entity_ids'],action=='convert' ? ['name'] : []); entities=targets(o['entity_ids']); editable(entities)
        fail_command('unsupported_entity','Convert accepts groups only') if action=='convert' && entities.any? { |e| e.typename!='Group' }
        label(o['name']) if o.key?('name')
        fail_command('geometry_too_large','Explode supports at most2048 resulting children') if action=='explode' && entities.inject(0) { |sum,e| sum+e.definition.entities.length }>2048
      when 'replace','instantiate'
        o=options(args,action=='replace' ? %w[entity_ids definition_id] : %w[definition_id origin_mm],action=='instantiate' ? ['name'] : [])
        definition=definition_by_id(o['definition_id']); editable([]); prevent_recursive_definition(definition)
        if action=='replace'
          entities=targets(o['entity_ids']); editable(entities)
          fail_command('unsupported_entity','Replacement accepts components only') if entities.any? { |e| e.typename!='ComponentInstance' }
        else origin=vector(o['origin_mm']); label(o['name']) if o.key?('name') end
      when 'metadata'
        o=options(args,%w[definition_id affect_all_instances],%w[name description]); definition=definition_by_id(o['definition_id']); editable([])
        fail_command('invalid_arguments','Definition metadata affects all instances; explicit confirmation required') unless o['affect_all_instances']==true
        fail_command('invalid_arguments','No metadata provided') unless o.key?('name') || o.key?('description')
        label(o['name']) if o.key?('name'); label(o['description'],true,1024) if o.key?('description')
        other=@model.definitions[o['name']] if o.key?('name'); fail_command('resource_exists','Definition name exists') if other && other!=definition
      else fail_command('invalid_arguments','Unsupported component action')
      end
      fail_command('glued_entity','Unglue components in SketchUp first') if entities.any? { |e| e.respond_to?(:glued_to) && e.glued_to }
      data=checked('dry_run'=>dry,'undoable'=>!dry,'action'=>action,'target_ids'=>entities.map { |e| e.persistent_id.to_s })
      return data if dry
      operation('Component '+action) do
        case action
        when 'explode'
          made=entities.flat_map do |e|
            result=e.explode; fail_command('geometry_failed','Explode failed') unless result.is_a?(Array) && !e.valid?; result
          end
          # Native explode also returns vertices/edge-uses and other topology
          # helpers. Only direct drawing children have usable collection paths.
          children=made.select do |e|
            e.is_a?(Sketchup::Drawingelement) && e.valid? && e.parent==@model.active_entities.parent && e.persistent_id.to_i>0
          end.uniq
          data['result_paths']=children.first(128).map { |e| context_ids+[e.persistent_id.to_s] }
          data['result_count']=children.length; data['paths_truncated']=children.length>128
        when 'convert'
          made=entities.map do |group|
            transform=group.transformation.to_a
            group.make_unique if group.definition.instances.length>1
            instance=group.to_component; validate_created(instance,'ComponentInstance',[])
            fail_command('postcondition_failed','Conversion changed the instance transform') unless same_numbers(instance.transformation.to_a,transform)
            instance.definition.name=o['name'] if o.key?('name'); instance
          end
          data['created']=made.map { |e| instance_snapshot(e,@model.edit_transform) }
        when 'replace'
          before=entities.map { |e| e.transformation.to_a }
          entities.each { |e| e.definition=definition }
          fail_command('postcondition_failed','Replacement definition/transform did not match') unless entities.zip(before).all? { |e,t| e.definition==definition && same_numbers(e.transformation.to_a,t) }
          data['after']=entities.map { |e| instance_snapshot(e,@model.edit_transform) }
        when 'instantiate'
          transform=invertible(@model.edit_transform).inverse*Geom::Transformation.translation(origin.map { |x| x/25.4 })
          instance=@model.active_entities.add_instance(definition,transform); validate_created(instance,'ComponentInstance',[])
          instance.layer=@model.layers[0]; instance.name=o.fetch('name',definition.name)
          fail_command('postcondition_failed','New instance definition/transform did not match') unless instance.definition==definition && same_numbers(instance.transformation.to_a,transform.to_a)
          data['created']=[instance_snapshot(instance,@model.edit_transform)]
        when 'metadata'
          definition.name=o['name'] if o.key?('name'); definition.description=o['description'] if o.key?('description')
          fail_command('postcondition_failed','Definition metadata did not match') if (o.key?('name') && definition.name!=o['name']) || (o.key?('description') && definition.description!=o['description'])
        end
        data['definition']=ResourceReader.new(@model).item('definitions',definition) if definition
        data
      end
    end
  end
end
