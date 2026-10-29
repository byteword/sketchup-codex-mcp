# encoding: UTF-8
module SUPipeProbe
  module LibraryOperationCommands
    private
    def apply_operation_plans(args,dry)
      editable([]);plans=args['plans'];bindings=args['bindings'];verify=args.fetch('verify_only',false)
      fail_command('invalid_plan','Typed plans require bindings and boolean verify_only') unless bindings.is_a?(Hash) && [true,false].include?(verify)
      fail_command('invalid_plan','Typed operations use explicit model coordinates/targets') if bindings.key?('replace_entity_id') || bindings.fetch('origin_mm',[0,0,0])!=[0,0,0]
      fail_command('invalid_plan','Plan byte/count budget exceeded') unless plans.length.between?(1,32) && JSON.generate(plans).bytesize<=48_000
      (args['fingerprints'] || []).each do |read|
        fail_command('model_stale','Declared input changed; replan') unless library_snapshot_data(read)['fingerprint']==read['fingerprint']
      end
      plans.each do |plan|
        fail_command('invalid_plan','Unexpected typed plan fields') unless plan.is_a?(Hash) && plan.keys.sort==%w[format_version steps units] && plan['format_version']=='sketchup-operations/1' && plan['units']=='mm'
      end
      # Reuse the typed command boundary, validation and native implementation.
      fail_command('invalid_plan','Too many typed steps across plans') unless plans.sum { |p| p['steps'].is_a?(Array) ? p['steps'].length : 65 }<=64
      executor=InlineCommandExecutor.new(@model)
      execute=lambda do
        started=window_clock
        reports=plans.map do |plan|
          window_budget!(started)
          executor.call('run_batch',{'expected_context'=>args['expected_context'],'steps'=>plan['steps'],'dry_run'=>dry})
        end
        window_budget!(started)
        {'dry_run'=>dry,'verify_only'=>verify,'undoable'=>!dry && !verify,'created'=>[],
          'plans'=>verify ? reports.map { |r| {'step_count'=>r['step_count']} } : reports,'cleanup_verified'=>verify}
      end
      return execute.call if dry
      before=library_model_stamp if verify
      scope=UiUpdateScope.new(@model,@ui_updates || 'defer')
      result=scope.run(verify ? 'Verify typed library plans' : 'Apply typed library plan',verify) { checked(execute.call) }
      fail_command('outcome_unknown','Typed plan verification failed to restore model stamp') if verify && library_model_stamp!=before
      result.merge('ui_update'=>scope.report)
    end
  end
end
