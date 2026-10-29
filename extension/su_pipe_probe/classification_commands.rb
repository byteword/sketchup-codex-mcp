# encoding: UTF-8
module SUPipeProbe
  module ClassificationCommands
    private
    def classification_path(value)
      fail_command('invalid_arguments','classification_path needs2..16 exact nonempty keys') unless value.is_a?(Array) && value.length.between?(2,16)
      value.map { |key| label(key,false,256) }
    end
    def classification_scalar(value)
      return value if value==true || value==false || value.nil?
      if value.is_a?(Numeric);finite_number(value,-1e12,1e12);return value;end
      return label(value,true,4096) if value.is_a?(String)
      fail_command('unsupported_value','Only scalar classification values are supported, not choice/list/tree objects')
    end
    def classification_query(args)
      root_edit!;o=options(args,[],%w[definition_id classification_path offset limit])
      if o.key?('definition_id') || o.key?('classification_path')
        fail_command('invalid_arguments','Value read needs definition_id and classification_path only') unless o.keys.sort==%w[classification_path definition_id]
        definition=definition_by_id(o['definition_id']);path=classification_path(o['classification_path'])
        value=definition.get_classification_value(path)
        {'definition_id'=>o['definition_id'],'classification_path'=>path,'value'=>classification_scalar(value),'nil_means'=>'Absent path or native nil value'}
      else
        offset=o.fetch('offset',0);limit=o.fetch('limit',25)
        fail_command('invalid_arguments','Invalid schema page') unless offset.is_a?(Integer) && offset.between?(0,1000) && limit.is_a?(Integer) && limit.between?(1,25)
        fail_command('query_budget_exceeded','At most1000 classification schemas') if @model.classifications.length>1000
        list=@model.classifications.to_a.sort_by(&:name)
        checked('items'=>list.drop(offset).first(limit).map { |s| {'name'=>s.name,'namespace'=>s.namespace} },'next_offset'=>offset+limit<list.length ? offset+limit : nil,
          'type_catalog_available'=>false,'note'=>'2019 public API lists schemas only; supply schema-defined type/property paths from its documentation.')
      end
    end
    def classification_locks!(definition)
      scanned=0;walk=nil
      walk=lambda do |entities,locked,depth|
        fail_command('query_budget_exceeded','Classification reference scan exceeded depth32') if depth>32
        entities.each do |e|
          scanned+=1;fail_command('query_budget_exceeded','Classification reference scan exceeds20000 entities') if scanned>20000
          next unless %w[Group ComponentInstance].include?(e.typename)
          inherited=locked || e.locked?
          fail_command('locked_entity','A classified occurrence or its ancestor is locked') if e.definition==definition && inherited
          walk.call(e.definition.entities,inherited,depth+1)
        end
      end
      walk.call(@model.entities,false,0)
    end
    def classification(args,dry)
      root_edit!;action=args['action']
      allowed=case action
        when 'load_schema';%w[path]
        when 'add','remove';%w[definition_id schema_name type_name affect_all_instances]
        when 'set_value';%w[definition_id classification_path value affect_all_instances]
        else fail_command('invalid_arguments','Unsupported classification action');end
      o=options(args,allowed,[])
      if action=='load_schema'
        path=local_file(o['path'],['.skc'],true)
        data=checked('dry_run'=>dry,'undoable'=>false,'action'=>action,'path'=>path);return data if dry
        begin
          fail_command('schema_load_failed','Classification schema did not load') unless @model.classifications.load_schema(path)
          data.merge('verification'=>'native_loader_acknowledged','note'=>'Query classification schema list; schema loading is outside the model Undo guarantee.')
        rescue StandardError
          fail_command('outcome_unknown','Classification schema load may have changed model resources; inspect before retry')
        end
      else
        definition=definition_by_id(o['definition_id']);classification_locks!(definition)
        fail_command('invalid_arguments','Classification changes affect every occurrence; require affect_all_instances=true') unless o['affect_all_instances']==true
        if action=='set_value'
          path=classification_path(o['classification_path']);value=classification_scalar(o['value'])
          fail_command('invalid_arguments','Null cannot set a classification value') if value.nil?
          fail_command('resource_not_found','Classification path does not exist') if definition.get_classification_value(path).nil?
        else
          schema=label(o['schema_name']);type=label(o['type_name'])
          fail_command('resource_not_found','Load the classification schema first') unless @model.classifications[schema]
        end
        data=checked('dry_run'=>dry,'undoable'=>!dry,'action'=>action,'definition_id'=>o['definition_id'],'instance_count'=>definition.count_instances)
        return data if dry
        operation('Edit component classification') do
          begin
            ok=case action
              when 'add';definition.add_classification(schema,type)
              when 'remove';definition.remove_classification(schema,type)
              else definition.set_classification_value(path,value);end
          rescue NotImplementedError
            fail_command('unsupported_value','SketchUp2019 cannot set choice classification attributes')
          end
          fail_command('classification_failed','Native classification API rejected the type/path/value') unless ok
          if action=='set_value'
            after=classification_scalar(definition.get_classification_value(path))
            fail_command('postcondition_failed','Classification value mismatch') unless after==value
            data['value']=after
          end
          data.merge('verification'=>action=='set_value' ? 'value_readback' : 'native_classification_acknowledged')
        end
      end
    end
  end
end
