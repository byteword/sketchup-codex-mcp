# encoding: UTF-8
require_relative 'geometry_plan'
require_relative 'batch_commands'
require_relative 'display_commands'
require_relative 'texture_snapshot'
module SUPipeProbe
  class NativeQueries
    include GeometryPlan
    include TextureSnapshot
    def initialize(model);@model=model;end
    def fail_command(code,message);raise ArgumentError,code+': '+message;end
    def finite_number(v,lo,hi)
      fail_command('invalid_arguments','Expected bounded finite number') unless v.is_a?(Numeric) && v.to_f.finite? && v>=lo && v<=hi
      v.to_f
    end
    def numeric_triple(args,key,lo,hi)
      value=args[key];fail_command('invalid_arguments','Expected three finite numbers') unless value.is_a?(Array) && value.length==3
      value.map { |x| finite_number(x,lo,hi) }
    end
    def resolve(path)
      fail_command('invalid_arguments','Expected1..32 positive persistent IDs') unless path.is_a?(Array) && path.length.between?(1,32) && path.all? { |s| s.is_a?(String) && s.match(/\A[1-9][0-9]{0,18}\z/) }
      collection=@model.entities;parent=Geom::Transformation.new;entity=nil
      path.each_with_index do |id,i|
        entity=@model.find_entity_by_persistent_id(id.to_i)
        fail_command('target_stale','Instance path no longer resolves') unless entity && entity.valid? && entity.parent==collection.parent
        if i<path.length-1
          fail_command('invalid_path','Intermediate entity is not a container') unless %w[Group ComponentInstance].include?(entity.typename)
          parent=parent*entity.transformation;collection=entity.definition.entities
        end
      end
      [entity,parent]
    end
    def call(args)
      query=args['query']
      case query
      when 'capabilities'
        options(args,[])
        {'sketchup_version'=>Sketchup.version,'pro'=>Sketchup.is_pro?,
         'library_formats'=>%w[sketchup-plan/1 sketchup-operations/1 probe-report/1],
         'line_styles'=>@model.line_styles.map(&:name),'batch_methods'=>BatchCommands::METHODS,'raw_drawing'=>true,'coordinates'=>'model_axes_mm',
         'query_modes'=>%w[capabilities metrics raycast classify_point attributes display face_mesh uv face_texture view_state view_presets classification file_style_support],
         'effects'=>{'typed_operations'=>'one_model_undo','queries'=>'none','camera_scenes'=>'separate_state','full_scenes_styles'=>'native_non_undo','cad_import'=>'native_translator','file_export'=>'no_overwrite'},
         'minimum_sketchup'=>'2019','native_acceptance'=>'Check installed release validation record'}
      when 'file_style_support'
        options(args,[]);CommandExecutor.new(@model).send(:file_style_support)
      when 'classification'
        CommandExecutor.new(@model).send(:classification_query,args)
      when 'face_texture'
        o=options(args,['instance_path']);texture_snapshot(o['instance_path'])
      when 'view_state','view_presets'
        o=options(args,[],query=='view_presets' ? ['name'] : [])
        CommandExecutor.new(@model).send(:view_query,query,o['name'])
      when 'display'
        options(args,[]);DisplayContract.snapshot(@model)
      when 'raycast'
        o=options(args,%w[origin_mm direction],['include_hidden']);origin=Geom::Point3d.new(vector(o['origin_mm']).map { |n| n/25.4 });direction=Geom::Vector3d.new(unit(vector(o['direction'])))
        hidden=o.fetch('include_hidden',false);fail_command('invalid_arguments','include_hidden must be boolean') unless [true,false].include?(hidden)
        hit=@model.raytest([origin,direction],!hidden)
        {'hit'=>!hit.nil?,'point_mm'=>hit && hit[0].to_a.map { |n| n.to_f*25.4 },'instance_path'=>hit && hit[1].map { |e| e.persistent_id.to_s }}
      when 'classify_point'
        o=options(args,%w[instance_path point_mm]);root_context!
        face,parent=resolve(o['instance_path']);fail_command('unsupported_entity','Choose a face') unless face.typename=='Face'
        p=Geom::Point3d.new(vector(o['point_mm']).map { |n| n/25.4 }).transform(parent.inverse)
        value=face.classify_point(p)
        names=%w[PointUnknown PointInside PointOnVertex PointOnEdge PointOnFace PointOutside PointNotOnPlane]
        name=names.find { |n| Sketchup::Face.const_defined?(n) && Sketchup::Face.const_get(n)==value }
        {'classification'=>name || 'unknown','native_code'=>value,'instance_path'=>o['instance_path']}
      when 'attributes'
        o=options(args,%w[instance_path dictionary],%w[offset limit]);entity,_=resolve(o['instance_path']);name=label(o['dictionary'],false,128)
        offset=o.fetch('offset',0);limit=o.fetch('limit',25)
        fail_command('invalid_arguments','Invalid attribute page') unless offset.is_a?(Integer) && offset>=0 && limit.is_a?(Integer) && limit.between?(1,25)
        dictionary=entity.attribute_dictionary(name,false);fail_command('query_budget_exceeded','Attribute dictionary exceeds5000 keys') if dictionary && dictionary.length>5000;items=dictionary ? dictionary.to_a.sort_by { |k,v| k.to_s } : []
        selected=[];next_index=offset
        items.drop(offset).first(limit).each do |key,value|
          begin;encoded=JSON.generate(value);raise 'large' if encoded.bytesize>8192;value=JSON.parse(encoded);rescue StandardError;value={'unsupported_type'=>value.class.name};end
          entry={'key'=>key.to_s[0,256],'value'=>value}
          break if JSON.generate(selected+[entry]).bytesize>28000
          selected<<entry;next_index+=1
        end
        {'dictionary'=>name,'items'=>selected,'next_offset'=>next_index<items.length ? next_index : nil}
      when 'face_mesh','uv'
        o=options(args,query=='uv' ? %w[instance_path points_mm] : ['instance_path'],query=='uv' ? ['front'] : [])
        root_context!;face,parent=resolve(o['instance_path']);fail_command('unsupported_entity','Choose a face') unless face.typename=='Face'
        if query=='face_mesh'
          fail_command('query_budget_exceeded','Face has more than1000 vertices') if face.vertices.length>1000
          mesh=face.mesh(0);fail_command('query_budget_exceeded','Face mesh exceeds1000 points/2000 polygons') if mesh.count_points>1000 || mesh.count_polygons>2000
          result={'points_mm'=>mesh.points.map { |p| p.transform(parent).to_a.map { |v| v.to_f*25.4 } },'polygons'=>mesh.polygons,'indices_one_based'=>true,'negative_index_means_hidden_edge'=>true}
          fail_command('query_budget_exceeded','Face mesh exceeds response budget') if JSON.generate(result).bytesize>30000
          result
        else
          points=point_list(o['points_mm'],1,64);front=o.fetch('front',true);fail_command('invalid_arguments','front must be boolean') unless [true,false].include?(front)
          material=front ? face.material : face.back_material
          fail_command('unsupported_material','Face side must have a directly assigned texture') unless material && material.texture
          helper=face.get_UVHelper(front,!front)
          values=points.map do |p|
            local=Geom::Point3d.new(p.map { |x| x/25.4 }).transform(parent.inverse)
            q=front ? helper.get_front_UVQ(local) : helper.get_back_UVQ(local)
            fail_command('invalid_uv','UVQ contains a zero/nonfinite Q') unless q.to_a.all? { |n| n.to_f.finite? } && q.z.abs>1e-12
            [q.x/q.z,q.y/q.z]
          end
          {'uv'=>values,'front'=>front,'material'=>material.name,'coordinates'=>'normalized_uv'}
        end
      when 'metrics'
        o=options(args,%w[instance_path],%w[recursive max_entities]);root_context!
        entity,parent=resolve(o['instance_path']);recursive=o.fetch('recursive',true)
        fail_command('invalid_arguments','recursive must be boolean') unless [true,false].include?(recursive)
        limit=o.fetch('max_entities',5000);fail_command('invalid_arguments','max_entities must be1..5000') unless limit.is_a?(Integer) && limit.between?(1,5000)
        stats={'area_mm2'=>0.0,'edge_length_mm'=>0.0,'solid_volume_mm3'=>0.0,'solid_count'=>0,'non_solid_containers'=>0,'scanned'=>0,'complete'=>true,'recursive'=>recursive}
        started=Process.clock_gettime(Process::CLOCK_MONOTONIC);walk=nil
        walk=lambda do |e,t,depth|
          fail_command('query_budget_exceeded','Metrics exceeded count/depth/time budget') if stats['scanned']>=limit || depth>32 || Process.clock_gettime(Process::CLOCK_MONOTONIC)-started>0.5
          stats['scanned']+=1
          if %w[Group ComponentInstance].include?(e.typename)
            if e.manifold?
              # SDK volume includes this instance; only the parent's determinant remains.
              m=t.to_a;fail_command('unsupported_transform','Non-affine parent transform') if m[15].abs<1e-12
              determinant=(m[0]*(m[5]*m[10]-m[9]*m[6])-m[4]*(m[1]*m[10]-m[9]*m[2])+m[8]*(m[1]*m[6]-m[5]*m[2]))/(m[15]**3)
              stats['solid_volume_mm3']+=e.volume.to_f.abs*determinant.abs*25.4**3;stats['solid_count']+=1
            else stats['non_solid_containers']+=1 end
            e.definition.entities.each do |child|
              next if !recursive && %w[Group ComponentInstance].include?(child.typename)
              walk.call(child,t*e.transformation,depth+1)
            end
          elsif e.typename=='Face';stats['area_mm2']+=e.area(t).to_f*25.4**2
          elsif e.typename=='Edge';stats['edge_length_mm']+=e.length(t).to_f*25.4 end
        end
        walk.call(entity,parent,0);stats.merge('volume_scope'=>'Sum of manifold occurrences; overlapping solids are not unioned','instance_path'=>o['instance_path'])
      else fail_command('invalid_arguments','Unknown native query') end
    end
    def root_context!
      fail_command('context_mismatch','Exit edit mode before coordinate/volume analysis on SketchUp2019') unless (@model.active_path || []).empty?
    end
  end
  module AttributeCommands
    private
    def entity_attributes(args,dry)
      editable([]);o=options(args,%w[entity_id dictionary key],args['action']=='set' ? ['value_json'] : [])
      entity=@model.find_entity_by_persistent_id(o['entity_id'].to_i)
      fail_command('entity_context_mismatch','Attribute target must be a current direct drawing entity') unless entity && entity.valid? && entity.parent==@model.active_entities.parent && entity.is_a?(Sketchup::Drawingelement)
      editable([entity]);dictionary=label(o['dictionary'],false,128);key=label(o['key'],false,128)
      fail_command('invalid_arguments','Action must be set or delete') unless %w[set delete].include?(args['action'])
      value=nil
      if args['action']=='set'
        json=label(o['value_json'],false,8192);value=JSON.parse(json)
        valid=nil;valid=lambda { |v,n| n<=4 && (v.nil? || v==true || v==false || v.is_a?(String) || v.is_a?(Numeric) && v.to_f.finite? || v.is_a?(Array) && v.length<=64 && v.all? { |x| valid.call(x,n+1) }) }
        fail_command('invalid_arguments','Attributes accept JSON scalars or bounded arrays; encode object metadata as a JSON string') unless valid.call(value,0)
      end
      data=checked('dry_run'=>dry,'undoable'=>!dry,'entity_id'=>o['entity_id'],'dictionary'=>dictionary,'key'=>key,'action'=>args['action'])
      return data if dry
      operation('Set entity attribute') do
        args['action']=='set' ? entity.set_attribute(dictionary,key,value) : entity.delete_attribute(dictionary,key)
        actual=entity.get_attribute(dictionary,key)
        fail_command('postcondition_failed','Attribute result did not match') unless actual==(args['action']=='set' ? value : nil)
        data.merge('value'=>actual)
      end
    end
  end
end
