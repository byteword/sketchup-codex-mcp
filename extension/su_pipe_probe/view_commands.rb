# encoding: UTF-8
module SUPipeProbe
  module ViewCommands
    private
    def apply_camera(desired,dry)
      before=camera_copy(@model.active_view.camera)
      data=checked('dry_run'=>dry,'undoable'=>false,'before'=>camera_state(before),'planned'=>camera_state(desired))
      return data if dry
      begin
        @model.active_view.camera=desired
        after=camera_state(@model.active_view.camera)
        fail_command('postcondition_failed','Camera did not retain projection/position') unless view_fields_match?(after,data['planned'])
        data.merge('after'=>after)
      rescue StandardError => error
        begin
          @model.active_view.camera=before
          raise 'Camera restore mismatch' unless camera_state(@model.active_view.camera)==camera_state(before)
        rescue StandardError
          fail_command('outcome_unknown','Camera restoration could not be verified')
        end
        raise error
      end
    end
    def configure_camera(args,dry)
      perspective=args['perspective']; fail_command('invalid_arguments','perspective must be boolean') unless perspective==true || perspective==false
      fail_command('invalid_arguments','Use FOV for perspective or height for orthographic projection') if perspective && args.key?('height_mm') || !perspective && (args.key?('fov_degrees') || args.key?('focal_length_mm'))
      eye,target,up=vector(args['eye_mm']),vector(args['target_mm']),unit(vector(args['up']))
      direction=unit(sub(target,eye)); fail_command('invalid_geometry','Up vector is parallel to view direction') if norm(cross(direction,up))<1e-6
      fail_command('invalid_arguments','Choose FOV or focal_length_mm, not both') if args.key?('fov_degrees') && args.key?('focal_length_mm')
      ratio=finite_number(args.fetch('aspect_ratio',@model.active_view.camera.aspect_ratio),0,10)
      fail_command('invalid_arguments','Aspect ratio must be0(viewport) or0.1..10') if ratio>0 && ratio<0.1
      image_width=finite_number(args.fetch('image_width_mm',@model.active_view.camera.respond_to?(:image_width) ? @model.active_view.camera.image_width.to_f : 0),0,1000)
      focal=finite_number(args['focal_length_mm'],1,2000) if args.key?('focal_length_mm')
      fov=finite_number(args.fetch('fov_degrees',35),1,120)
      height=finite_number(args.fetch('height_mm',10000),1,1_000_000_000)
      desired=Sketchup::Camera.new(Geom::Point3d.new(eye.map { |x| x/25.4 }),Geom::Point3d.new(target.map { |x| x/25.4 }),Geom::Vector3d.new(up),perspective,fov)
      desired.aspect_ratio=ratio
      desired.image_width=image_width if desired.respond_to?(:image_width=)
      desired.focal_length=focal if focal
      # Coupled film-width/focal inputs must stay in the same restorable FOV range.
      finite_number(desired.fov,1,120) if perspective
      desired.height=height/25.4 unless perspective
      apply_camera(desired,dry)
    end
    def scene(args,dry)
      return full_scene(args,dry) if args['options'].is_a?(Hash) && args['options']['scope']=='full'
      fail_command('context_mismatch','Scene management requires model root') unless context_ids.empty?
      name=label(args['name']); action=args['action']; pages=@model.pages; page=pages[name]
      fail_command('resource_too_large','Scene management limited to1000 pages') if pages.length>1000
      o=options(args,[],%w[create update].include?(action) ? %w[new_name description] : [])
      fail_command('invalid_arguments','Unsupported scene action') unless %w[create update apply delete].include?(action)
      fail_command('resource_exists','Scene already exists') if action=='create' && page
      fail_command('resource_not_found','Scene not found by exact name') if action!='create' && !page
      if %w[update delete].include?(action) && !ResourceReader.new(@model).camera_only?(page)
        fail_command('unsupported_scene','Only camera-only scenes can be updated/deleted by this version')
      end
      if o.key?('new_name')
        label(o['new_name']); other=pages[o['new_name']]; fail_command('resource_exists','Scene name already exists') if other && other!=page
      end
      label(o['description'],true,1024) if o.key?('description')
      return apply_camera(camera_copy(page.camera),dry).merge('scene'=>name,'applied_properties'=>['camera']) if action=='apply'
      camera=camera_copy(@model.active_view.camera) if %w[create update].include?(action)
      data=checked('dry_run'=>dry,'undoable'=>false,'action'=>action,'name'=>name,'camera_only'=>true,
        'note'=>'SketchUp2019 scene metadata/cameras do not have reliable model Undo. Errors are conservatively unknown; inspect before retry.')
      return data if dry
      # Scene camera changes became Undoable only in SketchUp2026. Never claim an
      # aborted model operation restores scenes on older installed versions.
      begin
        if action=='delete'
          fail_command('api_error','Scene erase failed') unless pages.erase(page) && !pages[name]
        else
          page=pages.add(name,PAGE_USE_CAMERA) if action=='create'
          fail_command('api_error','Scene creation/update failed') unless page && page.update(PAGE_USE_CAMERA)
          page.name=o['new_name'] if o.key?('new_name'); page.description=o['description'] if o.key?('description')
          fail_command('postcondition_failed','Scene saved unexpected properties') unless ResourceReader.new(@model).camera_only?(page) && page.name==o.fetch('new_name',name)
          fail_command('postcondition_failed','Scene camera mismatch') unless camera_state(camera_copy(page.camera))==camera_state(camera)
          data['item']=ResourceReader.new(@model).item('scenes',page)
        end
        data
      rescue StandardError
        fail_command('outcome_unknown','Scene operation could not be verified; inspect the scene list before another command')
      end
    end
    def mirror_entities(args,dry)
      entities=targets(args['entity_ids']); editable(entities); pivot=vector(args['pivot_mm']); axis=args['axis']
      index=%w[X Y Z].index(axis); fail_command('invalid_arguments','Mirror axis must be X/Y/Z') unless index
      factors=[1,1,1]; factors[index]=-1; edit=invertible(@model.edit_transform)
      world=Geom::Transformation.scaling(Geom::Point3d.new(pivot.map { |x| x/25.4 }),*factors)
      desired=entities.map { |e| invertible(edit.inverse*world*edit*e.transformation) }
      data=checked('dry_run'=>dry,'undoable'=>!dry,'axis'=>axis,'pivot_mm'=>pivot,'planned_local_transforms'=>desired.map { |t| wire_transform(t) },'matrix_translation_unit'=>'mm')
      return data if dry
      operation('Mirror instances') do
        entities.zip(desired).each { |e,t| e.transformation=t }
        fail_command('postcondition_failed','Mirror transformation mismatch') unless entities.zip(desired).all? { |e,t| same_numbers(e.transformation.to_a,t.to_a) }
        data.merge('after'=>entities.map { |e| instance_snapshot(e,edit) })
      end
    end
  end
end
