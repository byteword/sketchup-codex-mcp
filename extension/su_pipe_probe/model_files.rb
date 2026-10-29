# encoding: UTF-8
require 'tmpdir'
require 'fileutils'
module SUPipeProbe
  module ModelFiles
    private
    CAD_IMPORT_BOOL=%w[import_materials merge_coplanar_faces orient_faces preserve_origin].freeze
    CAD_EXPORT_BOOL=%w[faces_flag construction_geometry dimensions text edges materials].freeze
    def model_file(args,dry)
      return ifc_file(args,dry) if %w[import_ifc export_ifc].include?(args['action'])
      return export_selection_skp(args,dry) if args['action']=='export_selection_skp'
      return export_dxf2d(args,dry) if args['action']=='export_dxf2d'
      root_edit!;action=args['action'];o=options(args,[],case action
        when 'import_skp';%w[origin_mm name]
        when 'import_cad';CAD_IMPORT_BOOL
        when 'save_copy';%w[version]
        when 'export_cad';CAD_EXPORT_BOOL+['acad_version']
        else fail_command('invalid_arguments','Unsupported model file action');end)
      input=%w[import_skp import_cad].include?(action);cad=%w[import_cad export_cad].include?(action)
      path=local_file(args['path'],cad ? %w[.dwg .dxf] : ['.skp'],input)
      fail_command('pro_required','DWG/DXF requires SketchUp Pro and the installed translator') if cad && !Sketchup.is_pro?
      native={:show_summary=>false}
      if cad
        (input ? CAD_IMPORT_BOOL : CAD_EXPORT_BOOL).each { |key| native[key.to_sym]=bool_option(o,key) if o.key?(key) }
        if !input
          version=o.fetch('acad_version','acad_2013')
          fail_command('invalid_arguments','Unsupported CAD version') unless %w[acad_12 acad_13 acad_14 acad_2000 acad_2004 acad_2007 acad_2010 acad_2013].include?(version)
          native[:acad_version]=version
        end
      elsif action=='import_skp'
        origin=vector(o.fetch('origin_mm',[0,0,0]));label(o['name']) if o.key?('name')
      else
        version=o.fetch('version','2019')
        fail_command('invalid_arguments','SKP copy version must be current or2019') unless %w[current 2019].include?(version)
        fail_command('model_unsaved','Save the model once in SketchUp before save_copy; its current path will be preserved') if @model.path.to_s.empty?
      end
      data=checked('dry_run'=>dry,'action'=>action,'path'=>path,'undoable'=>!dry && action=='import_skp',
        'effect'=>input ? 'model_import' : 'file_output','options'=>o)
      return data if dry
      if action=='import_skp'
        operation('Import SKP component') do
          definition=@model.definitions.load(path)
          fail_command('import_failed','SKP definition failed to load') unless definition && definition.valid?
          entity=@model.entities.add_instance(definition,Geom::Transformation.translation(origin.map { |v| v/25.4 }))
          fail_command('import_failed','SKP instance failed to place') unless entity && entity.valid?
          entity.name=o['name'] if o.key?('name');entity.layer=@model.layers[0]
          data.merge('created'=>[{'persistent_id'=>entity.persistent_id.to_s,'instance_path'=>[entity.persistent_id.to_s],'type'=>'ComponentInstance'}],
            'definition_id'=>'definition:'+definition.entityID.to_s)
        end
      elsif action=='import_cad'
        # DefinitionList#import is2021.1+, so2019 uses Model#import. Translators
        # may own Undo/UI/operations. Never nest them in our atomic operation.
        before_count=@model.entities.length
        begin
          fail_command('import_failed','CAD translator returned false') unless @model.import(path,native)
          data.merge('entity_count_before'=>before_count,'entity_count_after'=>@model.entities.length,
            'verification'=>'translator_acknowledged','note'=>'Native importer controls grouping, units and Undo. Refresh entity discovery. Geometry fidelity requires inspection.')
        rescue StandardError
          fail_command('outcome_unknown','CAD importer may have partially changed the model; inspect before retry')
        end
      else
        publish_model_file(path,data) do |temp|
          if action=='export_cad';@model.export(temp,native)
          elsif version=='current';@model.save_copy(temp)
          else @model.save_copy(temp,Sketchup::Model::VERSION_2019) end
        end
      end
    end
    def publish_model_file(path,data)
      created=false
      # An owned directory also isolates any translator sidecars. Only a single
      # self-contained SKP/DWG/DXF is published by this contract.
      Dir.mktmpdir('.probe-export-',File.dirname(path)) do |dir|
        temp=File.join(dir,File.basename(path))
        begin
          ok=yield(temp)
          fail_command('export_failed','Exporter failed or produced an empty file') unless ok && File.file?(temp) && File.size(temp)>0
          fail_command('unsupported_export','Exporter produced sidecar files; single-file export required') unless Dir.entries(dir).sort==['.','..',File.basename(path)].sort
          File.open(path,File::WRONLY|File::CREAT|File::EXCL|File::BINARY) do |output|
            created=true;File.open(temp,'rb') { |input| IO.copy_stream(input,output) }
          end
          data.merge('bytes'=>File.size(path),'sha256'=>Digest::SHA256.file(path).hexdigest)
        rescue StandardError
          File.delete(path) if created && File.file?(path)
          raise
        end
      end
    end
  end
end
