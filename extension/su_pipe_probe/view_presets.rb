# encoding: UTF-8
module SUPipeProbe
  module ViewPresets
    PRESET_DICTIONARY='SUPipeProbe.ViewPresets.v1'.freeze
    private
    def preset_store
      raw=@model.get_attribute(PRESET_DICTIONARY,'presets','{}')
      fail_command('preset_invalid','Stored preset data exceeds256KB') unless raw.is_a?(String) && raw.bytesize<=256_000
      value=JSON.parse(raw)
      fail_command('preset_invalid','Invalid preset store') unless value.is_a?(Hash) && value.length<=16
      fail_command('preset_invalid','Invalid preset names or states') unless value.all? { |name,state| name.is_a?(String) && name.length.between?(1,128) && !name.include?("\0") && state.is_a?(Hash) && JSON.generate(state).bytesize<=12_000 }
      value
    end
    def view_state
      root_edit!
      camera=camera_copy(@model.active_view.camera)
      fail_command('query_budget_exceeded','View presets support at most128 layers') if @model.layers.length>128
      c=camera_state(camera).reject { |k,v| v.nil? }
      c['image_width_mm']=camera.image_width.to_f
      axes=@model.axes
      data=DisplayContract.snapshot(@model).merge('camera'=>c,
        'tags'=>@model.layers.map { |layer| {'name'=>layer.name,'visible'=>layer.visible?} },
        'axes'=>{'origin_mm'=>axes.origin.to_a.map { |n| n.to_f*25.4 },'xaxis'=>axes.xaxis.to_a,'yaxis'=>axes.yaxis.to_a,'zaxis'=>axes.zaxis.to_a})
      fail_command('query_budget_exceeded','View state exceeds12KB') if JSON.generate(data).bytesize>12_000
      data
    end
    def view_query(kind,name=nil)
      if kind=='view_state';view_state
      else
        root_edit!
        store=preset_store
        return {'presets'=>store.keys.sort.map { |key| {'name'=>key} }} unless name
        label(name,false,128);fail_command('preset_not_found','Unknown saved view') unless store.key?(name)
        {'name'=>name,'state'=>store[name]}
      end
    end
    def validate_view_state(state)
      fail_command('invalid_arguments','Use camera, rendering, shadows, tags or axes') unless state.is_a?(Hash) && !state.empty? && (state.keys-%w[camera rendering shadows tags axes]).empty? && JSON.generate(state).bytesize<=12_000
      if state.key?('camera')
        c=state['camera']
        fail_command('invalid_arguments','Invalid camera properties') unless c.is_a?(Hash) && (c.keys-%w[eye_mm target_mm up perspective fov_degrees height_mm aspect_ratio focal_length_mm image_width_mm]).empty?
        state['camera']=configure_camera(c,true)['planned'].reject { |k,v| v.nil? }
      end
      display=state.select { |k,v| %w[rendering shadows].include?(k) }
      configure_display(display,true) unless display.empty?
      if state.key?('tags')
        tags=state['tags']
        fail_command('invalid_arguments','Expected at most128 distinct layers') unless tags.is_a?(Array) && tags.length<=128 && tags.all? { |e| e.is_a?(Hash) && e.keys.sort==%w[name visible] } && tags.map { |e| e['name'] }.uniq.length==tags.length
        tags.each do |item|
          label(item['name']);bool_option(item,'visible');layer=@model.layers[item['name']]
          fail_command('tag_not_found','Preset layer no longer exists: '+item['name']) unless layer
          fail_command('protected_tag','Cannot hide Layer0 or the active layer') if !item['visible'] && [@model.layers[0],@model.active_layer].include?(layer)
        end
      end
      if state.key?('axes')
        a=state['axes'];fail_command('invalid_arguments','Axes need origin_mm and xaxis/yaxis/zaxis') unless a.is_a?(Hash) && a.keys.sort==%w[origin_mm xaxis yaxis zaxis]
        vector(a['origin_mm']);x,y,z=%w[xaxis yaxis zaxis].map { |k| unit(vector(a[k])) }
        fail_command('invalid_geometry','Axes must be orthogonal and right handed') unless [dot(x,y),dot(y,z),dot(z,x)].all? { |n| n.abs<1e-8 } && dot(cross(x,y),z)>1-1e-8
        a['xaxis'],a['yaxis'],a['zaxis']=x,y,z
      end
    end
    def apply_view_fields(state)
      configure_camera(state['camera'],false) if state.key?('camera')
      display=state.select { |k,v| %w[rendering shadows].include?(k) }
      configure_display(display,false) unless display.empty?
      (state['tags'] || []).each { |item| @model.layers[item['name']].visible=item['visible'] }
      if state.key?('axes')
        a=state['axes'];@model.axes.set(Geom::Point3d.new(vector(a['origin_mm']).map { |n| n/25.4 }),*%w[xaxis yaxis zaxis].map { |k| Geom::Vector3d.new(unit(vector(a[k]))) })
      end
      @model.active_view.invalidate
    end
    def view_fields_match?(actual,wanted)
      wanted.all? do |k,v|
        if k=='tags';v.all? { |item| actual[k].include?(item) }
        elsif v.is_a?(Hash);view_fields_match?(actual[k],v.reject { |key,_| key=='focal_length_mm' })
        elsif v.is_a?(Array);actual[k].is_a?(Array) && same_numbers(actual[k],v)
        elsif v.is_a?(Numeric);actual[k].is_a?(Numeric) && (actual[k]-v).abs<=1e-6*[1,v.abs].max
        else actual[k]==v end
      end
    end
    def view_preset(args,dry)
      root_edit!;action=args['action'];name=args['name'];store=preset_store
      label(name,false,128) if name
      if %w[save delete].include?(action)
        fail_command('invalid_arguments','Save/delete requires name and no state') unless name && !args.key?('state')
        if action=='save'
          fail_command('preset_limit','At most16 saved presets') if !store.key?(name) && store.length>=16
          captured=view_state;validate_view_state(captured);store[name]=captured
        else
          fail_command('preset_not_found','Unknown saved view') unless store.key?(name)
          store.delete(name)
        end
        data=checked('action'=>action,'name'=>name,'dry_run'=>dry,'undoable'=>!dry)
        return data if dry
        operation('Save view preset') do
          @model.set_attribute(PRESET_DICTIONARY,'presets',JSON.generate(store))
          fail_command('postcondition_failed','Preset storage did not match') unless preset_store==store
          data
        end
      elsif action=='apply'
        fail_command('invalid_arguments','Apply either a saved name or an explicit state') unless (!!name) != args.key?('state')
        state=name ? store[name] : args['state'];fail_command('preset_not_found','Unknown saved view') unless state
        state=JSON.parse(JSON.generate(state));validate_view_state(state);before=view_state
        validate_view_state(JSON.parse(JSON.generate(before)))
        data=checked('action'=>action,'name'=>name,'dry_run'=>dry,'undoable'=>false,'effect'=>'view_state','before'=>before)
        return data.merge('planned'=>state) if dry
        begin
          apply_view_fields(state);after=view_state
          fail_command('postcondition_failed','View state did not match requested settings') unless view_fields_match?(after,state)
          checked(data.merge('after'=>after))
        rescue StandardError => error
          begin
            apply_view_fields(before)
            raise 'View restore mismatch' unless view_fields_match?(view_state,before)
          rescue StandardError
            fail_command('outcome_unknown','Could not verify complete view-state restoration')
          end
          raise error
        end
      else fail_command('invalid_arguments','Unknown view preset action') end
    end
  end
end
