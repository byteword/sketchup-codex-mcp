# encoding: UTF-8
module SUPipeProbe
  module FileExtensions
    private
    IFC_TYPES=%w[IfcNonDefined IfcBeam IfcBuilding IfcBuildingElementProxy IfcBuildingStorey IfcColumn IfcCurtainWall IfcDoor IfcFooting IfcFurnishingElement IfcMember IfcPile IfcPlate IfcProject IfcRailing IfcRamp IfcRampFlight IfcRoof IfcSite IfcSlab IfcSpace IfcStair IfcStairFlight IfcWall IfcWallStandardCase IfcWindow].freeze
    def ifc_file(args,dry)
      root_edit!;input=args['action']=='import_ifc';modern=Sketchup.version.to_i>=26
      allowed=input ? [] : modern ? %w[ifc_version standard_ifc_hierarchy hidden_geometry tessellated_geometry] : %w[hidden_geometry doublesided_faces ifc_mapped_items ifc_types]
      o=options(args,[],allowed);path=local_file(args['path'],['.ifc'],input)
      fail_command('pro_required','IFC requires SketchUp Pro and the installed translator') unless Sketchup.is_pro?
      native={:show_summary=>false}
      if !input && modern
        version=o.fetch('ifc_version','IFC 2x3');fail_command('invalid_arguments','IFC version must be IFC 2x3 or IFC 4') unless ['IFC 2x3','IFC 4'].include?(version)
        fail_command('invalid_arguments','tessellated_geometry requires IFC 4') if o.key?('tessellated_geometry') && version!='IFC 4'
        native[:ifc_version]=version;native[:selectionset_only]=false
        (allowed-['ifc_version']).each { |key| native[key.to_sym]=bool_option(o,key) if o.key?(key) }
      elsif !input
        types=o.fetch('ifc_types',IFC_TYPES)
        fail_command('invalid_arguments','Provide nonempty distinct supported IFC types') unless types.is_a?(Array) && types.length.between?(1,IFC_TYPES.length) && types.uniq==types && (types-IFC_TYPES).empty?
        native[:ifc_types]=types
        (allowed-['ifc_types']).each { |key| native[key.to_sym]=bool_option(o,key) if o.key?(key) }
      end
      data=checked('dry_run'=>dry,'undoable'=>false,'effect'=>input ? 'model_import' : 'file_output','action'=>args['action'],'path'=>path,'translator_options'=>native)
      return data if dry
      if input
        begin
          fail_command('import_failed','IFC translator returned false') unless @model.import(path,native)
          data.merge('verification'=>'translator_acknowledged','note'=>'Native importer controls structure, units and Undo; inspect before retry on failure.')
        rescue StandardError
          fail_command('outcome_unknown','IFC import may have partially changed the model; inspect before retry')
        end
      else
        publish_model_file(path,data) { |temp| @model.export(temp,native) }
      end
    end
    def export_source_stamp(entities)
      fail_command('resource_too_large','Selection export supports at most5000 definitions') if @model.definitions.length>5000
      library_model_stamp.merge('source_instances'=>entities.map { |e| [e.persistent_id,e.transformation.to_a,e.name,e.hidden?,e.locked?,e.layer.entityID,e.material && e.material.entityID] },
        'definition_metadata'=>@model.definitions.map { |d| [d.entityID,d.guid,d.path,d.name] }.sort)
    end
    def export_selection_skp(args,dry)
      root_edit!;o=options(args,['entity_ids'],%w[coordinates]);entities=targets(o['entity_ids'])
      mode=o.fetch('coordinates','model');fail_command('invalid_arguments','coordinates must be model or first_local') unless %w[model first_local].include?(mode)
      base=mode=='first_local' ? invertible(entities.first.transformation).inverse : Geom::Transformation.new
      path=local_file(args['path'],['.skp'],false);budget={:entries=>0,:bytes=>0}
      attributes=entities.map do |e|
        fail_command('unsupported_glued_entity','Glued instances cannot be exported separately from their host') if e.respond_to?(:glued_to) && e.glued_to
        component_attributes(e,budget)
      end
      transforms=entities.map { |e| invertible(base*e.transformation) }
      before=export_source_stamp(entities)
      data=checked('dry_run'=>dry,'undoable'=>false,'effect'=>'file_output','path'=>path,'coordinates'=>mode,'source_ids'=>o['entity_ids'],
        'skp_version'=>'current','note'=>'Exports one temporary wrapper containing component instances; originals and current selection remain unchanged.')
      return data if dry
      publish_model_file(path,data) do |temp|
        scope=UiUpdateScope.new(@model,@ui_updates || 'defer');failure=nil
        begin
          scope.run('Export selected instances',true) do
            wrapper=@model.entities.add_group;wrapper.name='Exported selection';wrapper.layer=@model.layers[0]
            entities.each_with_index do |source,index|
              copy=wrapper.entities.add_instance(source.definition,transforms[index])
              fail_command('export_failed','Could not copy source instance') unless copy && copy.valid?
              copy.name=source.name;copy.layer=source.layer;copy.material=source.material;copy.hidden=source.hidden?
              copy.casts_shadows=source.casts_shadows?;copy.receives_shadows=source.receives_shadows?
              attributes[index].each { |dict,key,value| copy.set_attribute(dict,key,value) }
              copy.locked=source.locked?
            end
            #2019 has only save_as(path); save_copy/version overloads are2022+.
            fail_command('export_failed','Temporary definition did not save') unless wrapper.definition.save_as(temp)
            {'saved'=>true}
          end
        rescue StandardError => error
          failure=error
        end
        fail_command('outcome_unknown','Selection export did not restore model/definition state; output was not published') unless before==export_source_stamp(entities)
        raise failure if failure
        data['model_unchanged']=true;data['ui_update']=scope.report;true
      end
    end
    def export_dxf2d(args,dry)
      root_edit!;o=options(args,['plane'],%w[entity_ids origin_mm include_hidden include_soft]);plane=o['plane']
      axes={'XY'=>[0,1],'XZ'=>[0,2],'YZ'=>[1,2]}[plane];fail_command('invalid_arguments','plane must be XY, XZ or YZ') unless axes
      origin=vector(o.fetch('origin_mm',[0,0,0]));hidden=bool_option(o,'include_hidden');soft=bool_option(o,'include_soft')
      path=local_file(args['path'],['.dxf'],false)
      roots=if o.key?('entity_ids')
        ids(o['entity_ids'],25).map { |id| NativeQueries.new(@model).resolve([id]).first }
      else @model.entities end
      fail_command('query_budget_exceeded','DXF root scan exceeds20000 entities') if roots.length>20000
      lines={};scanned=0;started=Process.clock_gettime(Process::CLOCK_MONOTONIC);walk=nil
      walk=lambda do |entity,transform,depth|
        scanned+=1
        fail_command('query_budget_exceeded','DXF exceeds20000 visited entities,32 levels or2 seconds') if scanned>20000 || depth>32 || Process.clock_gettime(Process::CLOCK_MONOTONIC)-started>2
        next unless %w[Group ComponentInstance Edge Face].include?(entity.typename)
        next if !hidden && (entity.hidden? || !entity.layer.visible?)
        if %w[Group ComponentInstance].include?(entity.typename)
          world=transform*entity.transformation;entity.definition.entities.each { |child| walk.call(child,world,depth+1) }
        elsif entity.typename=='Face'
          # Model traversal already encounters its edges; explicit face roots need them.
          entity.edges.each { |edge| walk.call(edge,transform,depth+1) } if depth==0 && o.key?('entity_ids')
        else
          next if !soft && (entity.soft? || entity.smooth?)
          a,b=[entity.start.position,entity.end.position].map do |p|
            xyz=p.transform(transform).to_a.map { |v| v.to_f*25.4 }
            fail_command('invalid_geometry','Nonfinite or excessively large projected coordinates') unless xyz.all? { |v| v.finite? && v.abs<=1e9 }
            axes.map { |i| (xyz[i]-origin[i]).round(6) }
          end
          next if a==b
          lines[[a,b].sort]=true
          fail_command('query_budget_exceeded','DXF supports at most5000 projected lines') if lines.length>5000
        end
      end
      roots.each { |e| walk.call(e,Geom::Transformation.new,0) }
      fail_command('empty_export','No nonzero edges after projection/filtering') if lines.empty?
      data=checked('dry_run'=>dry,'undoable'=>false,'effect'=>'file_output','path'=>path,'plane'=>plane,'origin_mm'=>origin,'line_count'=>lines.length,'units'=>'mm',
        'projection'=>'orthographic_wireframe','hidden_line_removal'=>false,'section_clipping'=>false,'layers'=>'all exported lines on0')
      return data if dry
      publish_model_file(path,data) do |temp|
        # ASCII DXF2000 LINE entities with explicit millimeter insertion units.
        File.open(temp,'wb') do |f|
          f.write("0\r\nSECTION\r\n2\r\nHEADER\r\n9\r\n$ACADVER\r\n1\r\nAC1015\r\n9\r\n$INSUNITS\r\n70\r\n4\r\n0\r\nENDSEC\r\n0\r\nSECTION\r\n2\r\nENTITIES\r\n")
          lines.keys.sort.each do |a,b|
            f.write("0\r\nLINE\r\n100\r\nAcDbEntity\r\n8\r\n0\r\n100\r\nAcDbLine\r\n10\r\n#{a[0]}\r\n20\r\n#{a[1]}\r\n30\r\n0.0\r\n11\r\n#{b[0]}\r\n21\r\n#{b[1]}\r\n31\r\n0.0\r\n")
          end
          f.write("0\r\nENDSEC\r\n0\r\nEOF\r\n")
        end
        true
      end
    end
  end
end
