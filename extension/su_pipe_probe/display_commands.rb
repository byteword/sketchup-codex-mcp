# encoding: UTF-8
require 'time'
require 'digest'
require 'securerandom'
module SUPipeProbe
  module DisplayContract
    RENDER_BOOL=%w[ModelTransparency MaterialTransparency DrawHidden DrawBackEdges DisplaySectionPlanes DisplaySectionCuts SectionCutFilled DisplayColorByLayer DisplayDims DisplayText DisplaySketchAxes DrawGround DrawHorizon Texture DisplayFog].freeze
    RENDER_COLOR=%w[BackgroundColor SkyColor GroundColor FogColor].freeze
    SHADOW_BOOL=%w[DisplayShadows DisplayOnGroundPlane DisplayOnAllFaces UseSunForAllShading EdgesCastShadows DaylightSavings].freeze
    SHADOW_NUM={'Light'=>[0,100],'Dark'=>[0,100],'Latitude'=>[-90,90],'Longitude'=>[-180,180],'TZOffset'=>[-14,14],'NorthAngle'=>[0,360]}.freeze
    def self.value(v);v.is_a?(Time) ? v.getutc.iso8601 : v.is_a?(Sketchup::Color) ? [v.red,v.green,v.blue] : v;end
    def self.snapshot(model)
      rendering=(RENDER_BOOL+RENDER_COLOR+%w[RenderMode EdgeDisplayMode]).each_with_object({}) { |k,h| v=model.rendering_options[k];h[k]=value(v) unless v.nil? }
      shadows=(SHADOW_BOOL+SHADOW_NUM.keys+['ShadowTime']).each_with_object({}) { |k,h| v=model.shadow_info[k];h[k]=value(v) unless v.nil? }
      {'rendering'=>rendering,'shadows'=>shadows}
    end
  end
  module DisplayCommands
    private
    def configure_display(args,dry)
      root_edit!;render=args.fetch('rendering',{});shadow=args.fetch('shadows',{})
      fail_command('invalid_arguments','Provide rendering and/or shadow properties') unless render.is_a?(Hash) && shadow.is_a?(Hash) && render.length+shadow.length>0
      fail_command('invalid_arguments','Unknown display key') unless (render.keys-DisplayContract::RENDER_BOOL-DisplayContract::RENDER_COLOR-%w[RenderMode EdgeDisplayMode]).empty? && (shadow.keys-DisplayContract::SHADOW_BOOL-DisplayContract::SHADOW_NUM.keys-['ShadowTime']).empty?
      changes=[]
      [[@model.rendering_options,render,DisplayContract::RENDER_BOOL],[@model.shadow_info,shadow,DisplayContract::SHADOW_BOOL]].each do |provider,values,bools|
        values.each do |k,v|
          fail_command('unsupported_setting','Setting unavailable: '+k) if provider[k].nil?
          if bools.include?(k);bool_option(values,k)
          elsif DisplayContract::RENDER_COLOR.include?(k)
            fail_command('invalid_arguments','Color needs3 integers0..255') unless v.is_a?(Array) && v.length==3 && v.all? { |n| n.is_a?(Integer) && n.between?(0,255) }
            v=Sketchup::Color.new(*v)
          elsif k=='ShadowTime'
            fail_command('invalid_arguments','Use ISO8601 date/time with explicit UTC offset') unless v.is_a?(String) && v.match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|[+-]\d\d:\d\d)\z/)
            v=Time.iso8601(v)
          elsif %w[RenderMode EdgeDisplayMode].include?(k)
            fail_command('invalid_arguments','Invalid render mode') unless v.is_a?(Integer) && v.between?(0,k=='RenderMode' ? 5 : 2)
          else finite_number(v,*DisplayContract::SHADOW_NUM[k]) end
          changes<<[provider,k,v,provider[k]]
        end
      end
      data=checked('dry_run'=>dry,'undoable'=>false,'effect'=>'display_state','before'=>DisplayContract.snapshot(@model));return data if dry
      begin
        changes.each { |provider,k,v,old| provider[k]=v }
        fail_command('postcondition_failed','Display settings did not match') unless changes.all? { |provider,k,v,old| DisplayContract.value(provider[k])==DisplayContract.value(v) }
        @model.active_view.invalidate
        data.merge('after'=>DisplayContract.snapshot(@model))
      rescue StandardError => error
        begin
          changes.reverse_each { |provider,k,v,old| provider[k]=old }
          raise 'restore mismatch' unless changes.all? { |provider,k,v,old| DisplayContract.value(provider[k])==DisplayContract.value(old) }
        rescue StandardError
          fail_command('outcome_unknown','Display restoration could not be verified')
        end
        raise error
      end
    end
    def local_file(value,extensions,input)
      path=label(value,false,1024).tr('\\','/')
      fail_command('invalid_path','Use an absolute local drive path with supported extension, without device paths or traversal') unless path.match(/\A[A-Za-z]:\/[^:]+\z/) && !path.split('/').any? { |p| p=='.' || p=='..' || p.end_with?(' ','.') } && extensions.include?(File.extname(path).downcase)
      fail_command('path_not_found','Parent folder must already exist') unless File.directory?(File.dirname(path))
      if input
        fail_command('file_not_found','Input file must exist and be at most64MiB') unless File.file?(path) && File.size(path).between?(1,64*1024*1024)
      else
        fail_command('file_exists','Choose a new filename; output never overwrites an existing file') if File.exist?(path)
      end
      path
    end
    def export_view(args,dry)
      root_edit!;path=local_file(args['path'],%w[.png .jpg .jpeg],false)
      width=args.fetch('width',1600);height=args.fetch('height',1200)
      fail_command('invalid_arguments','Image width/height must be64..4096 pixels') unless [width,height].all? { |n| n.is_a?(Integer) && n.between?(64,4096) }
      transparent=bool_option(args,'transparent');fail_command('invalid_arguments','Transparency requires PNG') if transparent && File.extname(path).downcase!='.png'
      data=checked('dry_run'=>dry,'undoable'=>false,'effect'=>'file_output','path'=>path,'width'=>width,'height'=>height);return data if dry
      temp=File.join(File.dirname(path),'.probe-'+SecureRandom.hex(12)+File.extname(path));created=false
      begin
        ok=@model.active_view.write_image(:filename=>temp,:width=>width,:height=>height,:antialias=>true,:compression=>0.9,:transparent=>transparent)
        fail_command('export_failed','View image export failed') unless ok && File.file?(temp) && File.size(temp)>0
        # EXCL protects a file created by someone else after preflight.
        File.open(path,File::WRONLY|File::CREAT|File::EXCL|File::BINARY) do |out|
          created=true;File.open(temp,'rb') { |input| IO.copy_stream(input,out) }
        end
        data.merge('bytes'=>File.size(path),'sha256'=>Digest::SHA256.file(path).hexdigest)
      rescue StandardError
        File.delete(path) if created && File.file?(path)
        raise
      ensure
        File.delete(temp) if File.file?(temp)
      end
    end
    def texture_resource(args,dry)
      root_edit!;action=args['action']
      fail_command('invalid_arguments','Unknown texture resource action') unless %w[create_texture load_skm replace_image remove_image set_size copy].include?(action)
      reads_file=%w[create_texture load_skm replace_image].include?(action)
      path=local_file(args['path'],action=='load_skm' ? ['.skm'] : %w[.png .jpg .jpeg],true) if reads_file
      fail_command('invalid_arguments','This action takes no file path') if !reads_file && args.key?('path')
      fail_command('invalid_arguments','SKM keeps embedded name and dimensions') if action=='load_skm' && (args.key?('name') || args.key?('tile_size_mm'))
      size=args['tile_size_mm']
      if size
        fail_command('invalid_arguments','tile_size_mm needs width and height') unless size.is_a?(Array) && size.length==2
        size=size.map { |n| finite_number(n,0.01,1_000_000)/25.4 }
      end
      fail_command('invalid_arguments','Remove image takes no tile size') if action=='remove_image' && size
      fail_command('invalid_arguments','set_size requires tile_size_mm') if action=='set_size' && !size
      name=label(args['name']) unless action=='load_skm'
      source=material_value(args['source_name']) if action=='copy'
      fail_command('invalid_arguments','copy requires source_name') if action=='copy' && !source
      fail_command('invalid_arguments','source_name is only for copy') if action!='copy' && args.key?('source_name')
      if %w[create_texture copy].include?(action)
        fail_command('resource_exists','Choose a new material name') if @model.materials[name]
      elsif action!='load_skm'
        source=material_value(name)
        fail_command('invalid_arguments','Material changes affect all uses; set affect_all_uses=true or copy first') unless args['affect_all_uses']==true
      end
      fail_command('invalid_material','Existing material needs a texture') if %w[set_size remove_image].include?(action) && !source.texture
      fail_command('invalid_material','A color-only copy cannot have tile dimensions') if action=='copy' && size && !source.texture
      old_size=source && source.texture && [source.texture.width.to_f,source.texture.height.to_f]
      size ||= old_size if %w[copy replace_image].include?(action)
      data=checked('dry_run'=>dry,'undoable'=>!dry,'action'=>action,'path'=>path,'scope'=>%w[replace_image remove_image set_size].include?(action) ? 'all_material_uses' : 'new_material')
      return data if dry
      operation('Edit textured material') do
        material=if action=='load_skm';@model.materials.load(path)
        elsif %w[create_texture copy].include?(action);@model.materials.add(name)
        else source end
        fail_command('resource_failed','Material did not load') unless material
        if action=='copy'
          material.texture=source.texture.image_rep if source.texture
          material.color=source.color;material.alpha=source.alpha
        elsif %w[create_texture replace_image].include?(action)
          material.texture=path
        elsif action=='remove_image'
          color=material.color;alpha=material.alpha;material.texture=nil;material.color=color;material.alpha=alpha
        end
        material.texture.size=size if size && material.texture
        textured=%w[create_texture replace_image set_size].include?(action) || action=='copy' && !!source.texture
        fail_command('postcondition_failed','Texture state did not match') if textured && !material.texture || action=='remove_image' && material.texture
        fail_command('postcondition_failed','Texture dimensions did not match') if size && material.texture && !same_numbers([material.texture.width.to_f,material.texture.height.to_f],size)
        data.merge('item'=>ResourceReader.new(@model).item('materials',material))
      end
    end
  end
end
