# encoding: UTF-8
module SUPipeProbe
  module StyleFiles
    private
    def style_usage
      fail_command('resource_too_large','Style reference scan supports1000 pages') if @model.pages.length>1000
      @model.pages.map { |page| [page,page.style] }.select { |page,style| style }
    end
    def file_style_support
      root_edit!;styles=@model.styles;selected=styles.selected_style
      {'sketchup_version'=>Sketchup.version,'native_style_duplicate'=>!!selected && selected.respond_to?(:duplicate),
       'native_style_delete'=>styles.respond_to?(:remove_style),'native_style_path'=>!!selected && selected.respond_to?(:path),
       'style_purge_unused'=>styles.respond_to?(:purge_unused),'display_settings_file'=>'probe-display/1',
       'selection_skp'=>'groups_components_current_format','dxf2d'=>'orthographic_wireframe_mm',
       'ifc'=>{'pro'=>Sketchup.is_pro?,'export_options'=>Sketchup.version.to_i>=26 ? '2026+' : '2019-2025','translator_verified'=>false}}
    end
    def style_file(args,dry)
      root_edit!;export=args['action']=='export_settings';o=options(args,['path'],export ? %w[name include_shadows] : [])
      path=local_file(o['path'],['.json'],!export)
      if export
        name=label(o.fetch('name','Display settings'),false,128);shadows=bool_option(o,'include_shadows')
        snapshot=DisplayContract.snapshot(@model)
        state={'rendering'=>snapshot['rendering']};state['shadows']=snapshot['shadows'] if shadows
        configure_display(state,true)
        document={'format_version'=>'probe-display/1','name'=>name}.merge(state)
        encoded=JSON.pretty_generate(document)+"\n"
        fail_command('resource_too_large','Display settings exceed16KiB') if encoded.bytesize>16_384
        data=checked('dry_run'=>dry,'undoable'=>false,'effect'=>'file_output','path'=>path,'fields'=>state.keys,'format_version'=>'probe-display/1')
        return data if dry
        publish_model_file(path,data) { |temp| File.binwrite(temp,encoded);true }
      else
        fail_command('resource_too_large','Display settings file exceeds16KiB') if File.size(path)>16_384
        begin
          raw=File.binread(path).force_encoding('UTF-8');raise ArgumentError unless raw.valid_encoding?
          document=JSON.parse(raw,:max_nesting=>12)
        rescue JSON::ParserError,JSON::NestingError,ArgumentError
          fail_command('invalid_settings_file','Expected bounded UTF-8 JSON display settings')
        end
        fail_command('invalid_settings_file','Expected probe-display/1 name/rendering and optional shadows only') unless document.is_a?(Hash) && document['format_version']=='probe-display/1' && %w[name rendering].all? { |key| document.key?(key) } && (document.keys-%w[format_version name rendering shadows]).empty?
        label(document['name'],false,128)
        state=document.select { |key,value| %w[rendering shadows].include?(key) }
        result=configure_display(state,dry)
        result.merge('name'=>document['name'],'path'=>path,'format_version'=>'probe-display/1','note'=>'Applies editable display settings; does not create, switch or commit a native Style. Textures/watermarks are not embedded.')
      end
    end
    def style_lifecycle(args,dry)
      root_edit!;action=args['action'];styles=@model.styles;uses=style_usage
      o=options(args,action=='purge_unused' ? ['confirm_model_wide'] : action=='duplicate' ? %w[name new_name] : ['name'],action=='duplicate' ? %w[select discard_style_changes] : [])
      fail_command('resource_too_large','Style lifecycle supports at most1000 styles') if styles.length>1000
      before=styles.to_a;selected=styles.selected_style
      descriptors=before.each_with_object({}) { |s,h| h[s]={'resource_id'=>'styles:'+s.entityID.to_s,'name'=>s.name.to_s[0,256]} }
      if action=='purge_unused'
        fail_command('invalid_arguments','Purging styles is model-wide; require confirm_model_wide=true') unless o['confirm_model_wide']==true
        style_changes_guard({})
      else
        name=label(o['name']);matches=before.select { |s| s.name==name }
        fail_command('resource_not_found','Choose a unique exact style name') unless matches.length==1
        target=matches.first
        if action=='duplicate'
          fail_command('unsupported_version','Native style duplication requires SketchUp2026.2+; use portable display settings on2019') unless target.respond_to?(:duplicate)
          label(o['new_name']);fail_command('resource_exists','Choose a new style name') if before.any? { |s| s.name==o['new_name'] }
          fail_command('resource_too_large','Style limit1000 reached') if styles.length>=1000
          select=bool_option(o,'select');bool_option(o,'discard_style_changes') if o.key?('discard_style_changes');style_changes_guard(o) if select
        else
          fail_command('unsupported_version','Individual style deletion requires SketchUp2026+; use purge_unused on2019') unless styles.respond_to?(:remove_style)
          fail_command('style_in_use','Cannot delete the selected style, last style or one referenced by a scene') if styles.length<=1 || target==selected || uses.any? { |page,style| style==target }
        end
      end
      data=checked('dry_run'=>dry,'undoable'=>false,'effect'=>'native_style','action'=>action,
        'note'=>action=='duplicate' ? 'Duplicates the named committed style; pending active edits are not copied.' : 'Native style cleanup has no guaranteed model Undo.')
      return data if dry
      begin
        case action
        when 'purge_unused';styles.purge_unused
        when 'delete';styles.remove_style(target)
        when 'duplicate'
          duplicate=target.duplicate
          fail_command('postcondition_failed','Style duplicate was not a new collection member') unless duplicate && !before.include?(duplicate) && styles.to_a.include?(duplicate)
          duplicate.name=o['new_name'];styles.selected_style=duplicate if select
          fail_command('postcondition_failed','Duplicate style name/selection mismatch') unless duplicate.name==o['new_name'] && (!select || styles.selected_style==duplicate)
          data['item']=ResourceReader.new(@model).item('styles',duplicate)
        end
        after=styles.to_a
        fail_command('postcondition_failed','Protected style or scene association changed') unless (action=='duplicate' && select || styles.selected_style==selected) && after.include?(styles.selected_style) && uses.all? { |page,style| page.style==style && after.include?(style) }
        fail_command('postcondition_failed','Style was not deleted') if action=='delete' && after.include?(target)
        removed=before-after;data['removed']=removed.first(25).map { |s| descriptors[s] };data['removed_count']=removed.length;data['removed_truncated']=removed.length>25
        checked(data)
      rescue StandardError
        fail_command('outcome_unknown','Native style lifecycle change could not be verified; inspect styles and scenes before retry')
      end
    end
  end
end
