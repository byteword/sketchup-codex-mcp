# encoding: UTF-8
require 'json'
require 'digest'
module SUPipeProbe
  # General native bridge only. Technique calculation/source never executes here.
  module LibraryPlanSupport
    def library_point(point)
      point.to_a.map { |n| (n.to_f*25.4).round(6) }
    end
    def library_material(material)
      return nil unless material
      texture=material.texture
      {'name'=>material.name.to_s,'color'=>material.color.to_a.first(3),'alpha'=>material.alpha.to_f,
       'texture'=>texture && [texture.filename.to_s,texture.width.to_f*25.4,texture.height.to_f*25.4]}
    end
    def library_resolve(path)
      raise ArgumentError,'Invalid instance path' unless path.is_a?(Array) && path.length.between?(1,32) && path.all? { |v| v.is_a?(String) && v.match(/\A[1-9][0-9]{0,18}\z/) }
      collection=@model.entities; world=Geom::Transformation.new; entity=nil
      path.each do |id|
        entity=@model.find_entity_by_persistent_id(id.to_i)
        raise ArgumentError,'Target path is stale' unless entity && entity.valid? && entity.parent==collection.parent && %w[Group ComponentInstance].include?(entity.typename)
        world=world*entity.transformation; collection=entity.definition.entities
      end
      [entity,world]
    end
    def library_snapshot_data(args)
      kind=args['query']; raise ArgumentError,'Unsupported snapshot query' unless %w[target-summary/1 target-subtree/1].include?(kind)
      target,world=library_resolve(args['instance_path'])
      limit=args.fetch('max_entities',2048); raise ArgumentError,'Invalid snapshot entity budget' unless limit.is_a?(Integer) && limit.between?(1,2048)
      started=Process.clock_gettime(Process::CLOCK_MONOTONIC); entries=[]
      visit=nil
      visit=lambda do |entity,transform,path,depth|
        raise ArgumentError,'Snapshot depth/entity/time budget exceeded' if depth>8 || entries.length>=limit || Process.clock_gettime(Process::CLOCK_MONOTONIC)-started>0.5
        data={'instance_path'=>path,'type'=>entity.typename,'material'=>library_material(entity.material),
          'tag'=>entity.layer.name.to_s,'hidden'=>entity.hidden?}
        if %w[Group ComponentInstance].include?(entity.typename)
          data.merge!('name'=>entity.name.to_s[0,256],'locked'=>entity.locked?,'transform'=>transform.to_a.each_with_index.map { |v,i| v.to_f*([12,13,14].include?(i) ? 25.4 : 1) },
                      'child_count'=>entity.definition.entities.length)
          box=entity.definition.bounds
          data['model_bounds']=unless box.empty?
            corners=8.times.map { |i| library_point(box.corner(i).transform(transform)) }
            {'min'=>corners.transpose.map(&:min),'max'=>corners.transpose.map(&:max)}
          end
        elsif entity.typename=='Face'
          data.merge!('vertices_mm'=>entity.vertices.map { |v| library_point(v.position.transform(transform)) },
            'loops'=>entity.loops.map { |loop| loop.vertices.map { |v| library_point(v.position.transform(transform)) } },
            'back_material'=>library_material(entity.back_material))
        elsif entity.typename=='Edge'
          data.merge!('points_mm'=>[library_point(entity.start.position.transform(transform)),library_point(entity.end.position.transform(transform))],
                      'soft'=>entity.soft?,'smooth'=>entity.smooth?)
        end
        entries<<data
        if %w[Group ComponentInstance].include?(entity.typename)
          entity.definition.entities.sort_by { |e| e.persistent_id.to_i }.each do |child|
            next unless child.is_a?(Sketchup::Drawingelement)
            child_transform=%w[Group ComponentInstance].include?(child.typename) ? transform*child.transformation : transform
            visit.call(child,child_transform,path+[child.persistent_id.to_s],depth+1)
          end
        end
      end
      visit.call(target,world,args['instance_path'],0)
      # The full traversal fingerprints summary reads too, so contents cannot change
      # unnoticed between a semantic analysis and a later apply.
      fingerprint='sha256:'+Digest::SHA256.hexdigest(JSON.generate(entries))
      visible=kind=='target-summary/1' ? entries.first(1) : entries
      {'snapshot'=>{'target'=>entries.first,'entities'=>visible},'fingerprint'=>fingerprint}
    end
  end

  class LibrarySnapshotReader
    include LibraryPlanSupport
    def initialize(model); @model=model; end
    def palette(args)
      names=args['materials']
      raise ArgumentError,'Provide at most16 material roles' unless names.is_a?(Hash) && names.length<=16
      values={}
      names.each do |role,name|
        raise ArgumentError,'Invalid material role/name' unless role.is_a?(String) && name.is_a?(String) && name.length.between?(1,256)
        material=@model.materials[name]
        raise ArgumentError,'Existing material not found: '+name unless material
        values[role]=library_material(material)
      end
      {'materials'=>values}
    end
    def call(args)
      value=library_snapshot_data(args); entries=value['snapshot']['entities']
      offset=args.fetch('offset',0)
      raise ArgumentError,'Invalid snapshot offset' unless offset.is_a?(Integer) && offset.between?(0,2048)
      page=[]; index=offset
      while index<entries.length && page.length<64
        candidate=entries[index]
        raise ArgumentError,'Snapshot entry exceeds response budget' if JSON.generate(candidate).bytesize>24_000
        break if JSON.generate(page+[candidate]).bytesize>28_000
        page<<candidate;index+=1
      end
      {'snapshot'=>{'target'=>value['snapshot']['target'],'entities'=>page},'fingerprint'=>value['fingerprint'],
       'next_offset'=>index<entries.length ? index : nil}
    end
  end

  module LibraryPlanCommands
    include LibraryPlanSupport
    private
    def library_transform(value)
      return Geom::Transformation.new unless value
      fail_command('invalid_plan','Expected16 transform numbers') unless value.is_a?(Array) && value.length==16 && value.all? { |v| v.is_a?(Numeric) && v.to_f.finite? }
      a=value.map(&:to_f);fail_command('invalid_plan','Transform is not affine') unless [a[3],a[7],a[11],a[15]-1].all? { |v| v.abs<1e-10 }
      [12,13,14].each { |i| a[i]/=25.4 }
      invertible(Geom::Transformation.new(a))
    end
    def library_bounds(entity,world)
      points=[];walk=nil
      walk=lambda do |group,transform|
        group.definition.entities.each do |item|
          if item.typename=='Face'
            item.vertices.each { |v| points<<library_point(v.position.transform(transform)) }
          elsif %w[Group ComponentInstance].include?(item.typename)
            walk.call(item,transform*item.transformation)
          end
        end
      end
      walk.call(entity,world)
      fail_command('postcondition_failed','Empty library geometry') if points.empty?
      {'min'=>points.transpose.map(&:min),'max'=>points.transpose.map(&:max)}
    end
    def library_model_stamp
      keys=lambda do |collection|
        collection.map do |e|
          id=if e.respond_to?(:entityID); e.entityID.to_s
             elsif e.respond_to?(:persistent_id); e.persistent_id.to_s
             else e.name.to_s end
          [e.class.name,id]
        end.sort
      end
      box=@model.bounds
      {'roots'=>keys.call(@model.entities),'definitions'=>keys.call(@model.definitions),
       'materials'=>keys.call(@model.materials),'tags'=>keys.call(@model.layers),
       'selection'=>keys.call(@model.selection),'context'=>(@model.active_path || []).map { |e| e.persistent_id.to_s },
       'modified'=>@model.modified?,'bounds'=>box.empty? ? nil : [library_point(box.min),library_point(box.max)]}
    end
    def apply_library_plan(args,dry)
      if args['plans'].is_a?(Array) && !args['plans'].empty? && args['plans'].all? { |p| p.is_a?(Hash) && p['format_version']=='sketchup-operations/1' }
        return apply_operation_plans(args,dry)
      end
      editable([]); verify=args.fetch('verify_only',false)
      fail_command('invalid_arguments','verify_only must be boolean') unless verify==true || verify==false
      plans=args['plans'];fail_command('invalid_plan','Provide1..32 plans') unless plans.is_a?(Array) && plans.length.between?(1,32) && JSON.generate(plans).bytesize<=48_000
      bindings=args['bindings'];fail_command('invalid_arguments','bindings must be an object') unless bindings.is_a?(Hash)
      origin=bindings.fetch('origin_mm',[0,0,0]);numeric_triple({'v'=>origin},'v',-1_000_000_000,1_000_000_000)
      palette=bindings.fetch('materials',{});fail_command('invalid_arguments','materials must be an object') unless palette.is_a?(Hash)
      materials=Hash[palette.map { |role,name| [label(role),material_value(label(name))] }]
      replacements=bindings.key?('replace_entity_id') ? targets([bindings['replace_entity_id']]) : []
      editable(replacements)
      (args['fingerprints'] || []).each do |read|
        actual=library_snapshot_data(read)
        fail_command('model_stale','A declared read target changed; make a new plan') unless actual['fingerprint']==read['fingerprint']
      end
      normalized=plans.map do |plan|
        fail_command('invalid_plan','Unsupported plan format') unless plan.is_a?(Hash) && plan['format_version']=='sketchup-plan/1' && plan['units']=='mm'
        nodes=plan['nodes'];fail_command('invalid_plan','Plan node budget exceeded') unless nodes.is_a?(Array) && nodes.length.between?(1,64)
        groups={};ids=[];points_total=0;faces_total=0
        sections=nodes.map do |node|
          fail_command('invalid_plan','Node must be an object') unless node.is_a?(Hash)
          id=label(node['id']);name=label(node['name']);kind=node['kind']
          fail_command('invalid_plan','Duplicate node or unsupported kind') if ids.include?(id) || !%w[group mesh].include?(kind)
          if ids.empty?
            fail_command('invalid_plan','First node must be root group') unless id==plan['root'] && kind=='group' && !node.key?('parent')
          else
            fail_command('invalid_plan','Parent must be an earlier group') unless groups[node['parent']]
          end
          ids<<id;groups[id]=true if kind=='group'
          transform=library_transform(node['transform'])
          data={'id'=>id,'name'=>name,'kind'=>kind,'parent'=>node['parent'],'transform'=>transform}
          if kind=='mesh'
            points=point_list(node['points_mm'],4,4096)
            faces=node['faces'];fail_command('invalid_plan','Mesh face budget exceeded') unless faces.is_a?(Array) && faces.length.between?(4,2048)
            # Existing validator includes planarity, self intersections, oriented closure.
            # Existing tools keep their old budgets; library totals are checked separately.
            faces=mesh_validate(points,faces,2048,131072)
            roles=node['face_roles'];fail_command('invalid_plan','Face role mapping mismatch') unless roles.is_a?(Array) && roles.length==faces.length && roles.all? { |r| materials[r] }
            fail_command('invalid_plan','Only closed meshes supported') unless node['solid']==true
            cleanup=node.fetch('cleanup','none');fail_command('invalid_plan','Unsupported cleanup') unless %w[none material_safe].include?(cleanup)
            points_total+=points.length;faces_total+=faces.length
            data.merge!('points'=>points,'faces'=>faces,'roles'=>roles,'cleanup'=>cleanup)
          end
          data
        end
        fail_command('invalid_plan','Geometry total budget exceeded') if points_total>4096 || faces_total>2048
        assertions=plan['assertions'];fail_command('invalid_plan','Assertions required') unless assertions.is_a?(Array) && assertions.length.between?(1,128)
        [sections,assertions]
      end
      return {'dry_run'=>true,'planned_count'=>plans.length,'undoable'=>false} if dry
      edit=invertible(@model.edit_transform);placement=Geom::Transformation.translation(origin.map { |v| v/25.4 })
      scope=UiUpdateScope.new(@model,@ui_updates || 'defer')
      before=library_model_stamp if verify
      data=scope.run(verify ? 'Verify library plans' : 'Apply library plan',verify) do
        started=window_clock;created=[];reports=[]
        normalized.each do |sections,assertions|
          by_id={};worlds={};root=nil;cleanup={'removed_coplanar_edges'=>0,'hidden_textured_seams'=>0}
          sections.each do |node|
            window_budget!(started)
            parent=node['parent'] && by_id[node['parent']]
            group=(parent ? parent.entities : @model.active_entities).add_group
            fail_command('geometry_failed','Could not create library group') unless group && group.valid?
            group.name,group.layer,group.material=(!parent && bindings.key?('name') ? label(bindings['name']) : node['name']),@model.layers[0],nil
            group.transformation=parent ? node['transform'] : edit.inverse*placement*node['transform']
            world=parent ? worlds[node['parent']]*group.transformation : edit*group.transformation
            by_id[node['id']]=group;worlds[node['id']]=world;root||=group
            if node['kind']=='mesh'
              points=node['points'].map { |p| p.map { |n| n/25.4 } }
              node['faces'].each_with_index do |indices,index|
                window_budget!(started) if index%16==0
                face=group.entities.add_face(indices.map { |i| points[i] })
                fail_command('geometry_failed','Could not create library mesh face') unless face && face.valid?
                normal=planar_polygon(indices.map { |i| node['points'][i] })[3]
                face.reverse! if face.normal.dot(Geom::Vector3d.new(normal))<0
                face.material=materials[node['roles'][index]];face.back_material=materials[node['roles'][index]]
                face.layer=@model.layers[0]
              end
              group.entities.each { |e| e.layer=@model.layers[0] }
              fail_command('postcondition_failed','Library mesh is not solid') unless group.manifold?
              if node['cleanup']=='material_safe'
                window_optimize(group,started).each { |key,n| cleanup[key]+=n }
              end
            end
          end
          assertions.each do |assertion|
            fail_command('invalid_plan','Invalid assertion') unless assertion.is_a?(Hash) && by_id[assertion['node']]
            entity=by_id[assertion['node']]
            if assertion['kind']=='solid'
              fail_command('postcondition_failed','Solid assertion failed') unless entity.manifold?
            elsif assertion['kind']=='bounds'
              actual=library_bounds(entity,worlds[assertion['node']])
              tolerance=finite_number(assertion.fetch('tolerance_mm',0.001),0.000001,0.1)
              %w[min max].each do |key|
                expected=numeric_triple({'p'=>assertion[key+'_mm']},'p',-1_000_000_000,1_000_000_000).zip(origin).map { |a,b| a+b }
                fail_command('postcondition_failed','Library bounds assertion failed') unless actual[key].zip(expected).all? { |a,b| (a-b).abs<=tolerance }
              end
            else fail_command('invalid_plan','Unsupported assertion') end
          end
          bounds=library_bounds(root,worlds[sections.first['id']])
          created<<instance_snapshot(root,edit) unless verify
          reports<<{'group_count'=>sections.length,'geometry_bounds'=>bounds,'cleanup'=>cleanup,
                    'sections'=>sections.drop(1).map { |n| {'id'=>n['id'],'persistent_id'=>by_id[n['id']].persistent_id.to_s,'solid'=>n['kind']=='mesh' && by_id[n['id']].manifold?} }}
        end
        @model.active_entities.erase_entities(replacements) unless verify || replacements.empty?
        fail_command('postcondition_failed','Replacement did not erase') if !verify && replacements.any?(&:valid?)
        window_budget!(started)
        checked('dry_run'=>false,'verify_only'=>verify,'undoable'=>!verify,'created'=>created,'plans'=>reports,
                'duration_ms'=>((window_clock-started)*1000).round(3),'cleanup_verified'=>verify)
      end
      fail_command('outcome_unknown','Library verification cleanup did not restore the model stamp') if verify && library_model_stamp!=before
      data['cleanup_scope']=%w[root_entities definitions materials tags selection edit_context modified bounds] if verify
      data.merge('ui_update'=>scope.report)
    end
  end
end
