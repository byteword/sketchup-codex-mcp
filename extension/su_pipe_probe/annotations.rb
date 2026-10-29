# encoding: UTF-8
module SUPipeProbe
  module AnnotationCommands
    private
    def root_edit!
      fail_command('context_mismatch','This operation requires the model root on SketchUp2019') unless context_ids.empty?
      editable([])
    end
    def direct_drawing(id,types=nil)
      ids([id]);entity=@model.find_entity_by_persistent_id(id.to_i)
      fail_command('entity_context_mismatch','Choose a valid direct entity in the current edit context') unless entity && entity.valid? && entity.parent==@model.active_entities.parent && entity.is_a?(Sketchup::Drawingelement)
      fail_command('unsupported_entity','Unexpected entity type') if types && !types.include?(entity.typename)
      editable([entity]);entity
    end
    def mm_point(value);Geom::Point3d.new(vector(value).map { |n| n/25.4 });end
    def mm_vector(value);Geom::Vector3d.new(vector(value).map { |n| n/25.4 });end
    def bool_option(o,key,default=false)
      v=o.fetch(key,default);fail_command('invalid_arguments',key+' must be boolean') unless [true,false].include?(v);v
    end
    def annotation(args,dry)
      root_edit!;kind=args['kind'];name=label(args.fetch('name','Annotation'))
      case kind
      when 'guide'
        o=options(args,%w[point_mm direction]);point=mm_point(o['point_mm']);direction=Geom::Vector3d.new(unit(vector(o['direction'])))
      when 'linear_dimension'
        o=options(args,%w[start_mm end_mm offset_mm]);a=mm_point(o['start_mm']);b=mm_point(o['end_mm']);offset=mm_vector(o['offset_mm'])
        fail_command('invalid_geometry','Dimension endpoints/offset must define a plane') if a.distance(b)<0.01/25.4 || norm(cross(sub(vector(o['end_mm']),vector(o['start_mm'])),vector(o['offset_mm'])))<1e-6
      when 'radial_dimension'
        o=options(args,%w[edge_id leader_mm]);edge=direct_drawing(o['edge_id'],['Edge']);curve=edge.curve
        fail_command('unsupported_entity','Choose an edge of a native ArcCurve in the model root') unless curve && curve.is_a?(Sketchup::ArcCurve)
        point=mm_point(o['leader_mm'])
      when 'text'
        o=options(args,%w[text point_mm],['offset_mm']);text=label(o['text'],false,2048);point=mm_point(o['point_mm']);offset=mm_vector(o.fetch('offset_mm',[0,0,0]))
      when 'text3d'
        o=options(args,%w[text origin_mm height_mm],%w[font bold italic extrusion_mm]);text=label(o['text'],false,128);point=mm_point(o['origin_mm'])
        height=finite_number(o['height_mm'],1,10000)/25.4;extrusion=finite_number(o.fetch('extrusion_mm',0),0,10000)/25.4
        font=label(o.fetch('font','Arial'),false,128);bold=bool_option(o,'bold');italic=bool_option(o,'italic')
      when 'section'
        o=options(args,%w[point_mm normal],%w[active symbol]);point=mm_point(o['point_mm']);direction=Geom::Vector3d.new(unit(vector(o['normal'])));active=bool_option(o,'active')
        symbol=label(o.fetch('symbol','A'),false,3)
      else fail_command('invalid_arguments','Unknown annotation kind') end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'kind'=>kind,'grouping'=>kind=='text3d' ? 'group' : 'none')
      return data if dry
      operation('Create '+kind) do
        entities=@model.active_entities
        made=case kind
        when 'guide' then entities.add_cline(point,direction)
        when 'linear_dimension' then entities.add_dimension_linear(a,b,offset)
        when 'radial_dimension' then entities.add_dimension_radial(curve,point)
        when 'text' then entities.add_text(text,point,offset)
        when 'section' then entities.add_section_plane(point,direction)
        when 'text3d'
          group=entities.add_group;group.name=name
          ok=group.entities.add_3d_text(text,TextAlignLeft,font,bold,italic,height,0.0,0.0,true,extrusion)
          fail_command('geometry_failed','3D text failed or exceeded20000 entities') unless ok && group.entities.length.between?(1,20000)
          group.entities.each { |e| e.layer=@model.layers[0] }
          group.transformation=Geom::Transformation.translation(point.to_a);group
        end
        fail_command('geometry_failed','Annotation was not created') unless made && made.valid?
        made.layer=@model.layers[0]
        if kind=='section'
          made.name=name;made.symbol=symbol;made.activate if active
          fail_command('postcondition_failed','Section did not activate') if active && !made.active?
        end
        data.merge('created'=>[{'persistent_id'=>made.persistent_id.to_s,'instance_path'=>[made.persistent_id.to_s],'type'=>made.typename}])
      end
    end
    def edit_annotation(args,dry)
      root_edit!;action=args['action']
      if action=='erase'
        o=options(args,['entity_ids']);ids(o['entity_ids'],25)
        entities=o['entity_ids'].map { |id| direct_drawing(id,%w[ConstructionLine ConstructionPoint DimensionLinear DimensionRadial Text SectionPlane]) }
      elsif action=='section'
        o=options(args,['entity_id'],%w[point_mm normal active name symbol]);entity=direct_drawing(o['entity_id'],['SectionPlane'])
        fail_command('invalid_arguments','Specify section properties') if o.keys==['entity_id']
        fail_command('invalid_arguments','point_mm and normal must be supplied together') unless o.key?('point_mm')==o.key?('normal')
        plane=[mm_point(o['point_mm']),Geom::Vector3d.new(unit(vector(o['normal'])))] if o.key?('point_mm')
        active=bool_option(o,'active') if o.key?('active');label(o['name']) if o.key?('name');label(o['symbol'],false,3) if o.key?('symbol')
      elsif action=='text'
        o=options(args,%w[entity_id text]);entity=direct_drawing(o['entity_id'],['Text']);label(o['text'],false,2048)
      else fail_command('invalid_arguments','Unknown annotation edit') end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'action'=>action);return data if dry
      operation('Edit annotation') do
        if action=='erase'
          @model.active_entities.erase_entities(entities)
          fail_command('postcondition_failed','Annotation erase failed') if entities.any?(&:valid?)
        elsif action=='text'
          entity.text=o['text'];fail_command('postcondition_failed','Text did not change') unless entity.text==o['text']
        else
          entity.set_plane(plane) if plane;entity.name=o['name'] if o.key?('name');entity.symbol=o['symbol'] if o.key?('symbol')
          if o.key?('active')
            if active;entity.activate
            elsif entity.active?;@model.active_entities.active_section_plane=nil end
            fail_command('postcondition_failed','Section active state mismatch') unless entity.active? == active
          end
        end
        data
      end
    end
  end
end
