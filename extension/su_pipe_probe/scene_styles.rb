# encoding: UTF-8
module SUPipeProbe
  # Native Pages/Styles have effects outside the 2019 model Undo transaction.
  module SceneStyles
    private
    def style_changes_guard(args)
      fail_command('style_changes_pending','Commit the edited style with style update, or explicitly discard_style_changes=true') if @model.styles.active_style_changed && args['discard_style_changes']!=true
    end
    def full_scene(args,dry)
      root_edit!;name=label(args['name']);action=args['action'];pages=@model.pages;page=pages[name]
      fail_command('resource_too_large','Scene management limited to1000 pages') if pages.length>1000
      fail_command('invalid_arguments','Unsupported scene action') unless %w[create update apply delete].include?(action)
      allowed=%w[scope];allowed+=%w[new_name description transition_seconds delay_seconds include_in_animation] if %w[create update].include?(action)
      allowed+=['discard_style_changes'] if action=='apply'
      o=options(args,[],allowed)
      fail_command('resource_exists','Scene already exists') if action=='create' && page
      fail_command('resource_not_found','Scene not found') if action!='create' && !page
      if o.key?('new_name')
        label(o['new_name']);other=pages[o['new_name']];fail_command('resource_exists','Scene name already exists') if other && other!=page
      end
      label(o['description'],true,1024) if o.key?('description')
      %w[transition_seconds delay_seconds].each { |key| finite_number(o[key],-1,3600) if o.key?(key) }
      %w[include_in_animation discard_style_changes].each { |key| bool_option(o,key) if o.key?(key) }
      # Saving an uncommitted style is ambiguous in SU2019 and can open a dialog.
      style_changes_guard(action=='apply' ? o : {}) unless action=='delete'
      flags=PAGE_USE_CAMERA|PAGE_USE_RENDERING_OPTIONS|PAGE_USE_SHADOWINFO|PAGE_USE_SKETCHCS|PAGE_USE_HIDDEN|PAGE_USE_LAYER_VISIBILITY|PAGE_USE_SECTION_PLANES
      # 2020.1 split the old combined hidden flag. Never include newer environment flags.
      if defined?(PAGE_USE_HIDDEN_OBJECTS) && page_hidden_split?
        flags|=PAGE_USE_HIDDEN_GEOMETRY|PAGE_USE_HIDDEN_OBJECTS
      end
      data=checked('dry_run'=>dry,'undoable'=>false,'scope'=>'full','action'=>action,'name'=>name,
        'note'=>'Native2019 scene state/metadata is not reliably Undoable. On failure inspect before retry.')
      return data if dry
      begin
        case action
        when 'delete'
          fail_command('api_error','Scene erase failed') unless pages.erase(page) && !pages[name]
        when 'apply'
          # Force immediate selection without permanently changing animation timing.
          transition=page.transition_time
          begin
            page.transition_time=0
            selected=pages.send(:selected_page=,page)
            fail_command('postcondition_failed','Scene selection failed') unless selected && pages.selected_page==page
          ensure
            page.transition_time=transition
          end
          data['selected_scene']=page.name
          data['verification']='native_selection_acknowledged; inspect view_state for resulting view'
        else
          page=pages.add(name,flags) if action=='create'
          fail_command('api_error','Scene update failed') unless page && page.update(flags)
          %w[camera axes hidden hidden_layers rendering_options section_planes shadow_info].each { |key| page.send('use_'+key+'=',true) }
          # Unlike the other use_* setters, this2019 API accepts a Style object.
          page.use_style=@model.styles.selected_style
          if page_hidden_split?
            page.use_hidden_geometry=true;page.use_hidden_objects=true
          end
          page.name=o['new_name'] if o.key?('new_name');page.description=o['description'] if o.key?('description')
          page.transition_time=o['transition_seconds'] if o.key?('transition_seconds');page.delay_time=o['delay_seconds'] if o.key?('delay_seconds')
          page.include_in_animation=o['include_in_animation'] if o.key?('include_in_animation')
          fail_command('postcondition_failed','Scene name/flags mismatch') unless page.name==o.fetch('new_name',name) && %w[camera axes hidden_layers rendering_options section_planes shadow_info style].all? { |key| page.send('use_'+key+'?') }
          data['item']=ResourceReader.new(@model).item('scenes',page)
        end
        checked(data)
      rescue StandardError
        fail_command('outcome_unknown','Native scene change could not be verified; inspect scene list and current view before retry')
      end
    end
    def page_hidden_split?
      # Prefer feature detection to a version-string comparison (2019 has neither).
      Sketchup::Page.instance_methods.include?(:use_hidden_objects=)
    end
    def style(args,dry)
      return style_file(args,dry) if %w[export_settings import_settings].include?(args['action'])
      return style_lifecycle(args,dry) if %w[purge_unused duplicate delete].include?(args['action'])
      root_edit!;action=args['action'];styles=@model.styles
      fail_command('invalid_arguments','Unsupported style action') unless %w[load select update metadata].include?(action)
      allowed=case action;when 'load';%w[path select discard_style_changes];when 'select';%w[name discard_style_changes];when 'update';%w[affect_all_uses];else %w[name new_name description affect_all_uses];end
      o=options(args,[],allowed)
      fail_command('resource_too_large','Style management limited to1000 styles') if styles.length>1000
      path=local_file(o['path'],['.style'],true) if action=='load'
      select=action=='select' || action=='load' && bool_option(o,'select')
      bool_option(o,'discard_style_changes') if o.key?('discard_style_changes')
      style_changes_guard(o) if select
      target=styles.selected_style if action=='update'
      if %w[select metadata].include?(action)
        name=label(o['name']);matches=styles.select { |s| s.name==name }
        fail_command('resource_not_found','Choose a unique exact style name') unless matches.length==1
        target=matches.first
      end
      if %w[update metadata].include?(action)
        fail_command('invalid_arguments','Style changes affect scenes using it; require affect_all_uses=true') unless o['affect_all_uses']==true
        fail_command('resource_not_found','No selected style') unless target
      end
      if o.key?('new_name')
        label(o['new_name']);fail_command('resource_exists','Style name already exists') if styles.any? { |s| s!=target && s.name==o['new_name'] }
      end
      label(o['description'],true,1024) if o.key?('description')
      fail_command('invalid_arguments','Provide new_name or description') if action=='metadata' && !(o.key?('new_name') || o.key?('description'))
      data=checked('dry_run'=>dry,'undoable'=>false,'action'=>action,'effect'=>'native_style','path'=>path);return data if dry
      begin
        case action
        when 'load'
          before=styles.to_a
          # SU2019 returns Boolean, NOT Style (that overload was added in2026).
          fail_command('api_error','Style file did not load') unless styles.add_style(path,select)
          loaded=styles.to_a-before
          target=select ? styles.selected_style : loaded.first
          fail_command('postcondition_failed','Loaded style not identifiable') unless target && (select || loaded.length==1)
        when 'select'
          styles.selected_style=target
          fail_command('postcondition_failed','Style selection mismatch') unless styles.selected_style==target
        when 'update'
          styles.update_selected_style
          fail_command('postcondition_failed','Style still has unsaved edits') if styles.active_style_changed
        when 'metadata'
          target.name=o['new_name'] if o.key?('new_name');target.description=o['description'] if o.key?('description')
          fail_command('postcondition_failed','Style metadata mismatch') unless (!o.key?('new_name') || target.name==o['new_name']) && (!o.key?('description') || target.description==o['description'])
        end
        checked(data.merge('item'=>ResourceReader.new(@model).item('styles',target)))
      rescue StandardError
        fail_command('outcome_unknown','Native style operation could not be verified; inspect styles before retry')
      end
    end
  end
end
