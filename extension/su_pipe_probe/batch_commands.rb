# encoding: UTF-8
module SUPipeProbe
  module BatchCommands
    # Only commands whose complete model mutation uses operation(). Excludes
    # selection/camera/scenes, self-tests, nested batches, grants and file I/O.
    METHODS=%w[update_entity_properties move_entities create_box duplicate_entities create_rectangle create_circle create_polyline rotate_entities scale_entities erase_entities group_entities make_unique push_pull manage_resource component create_geometry edit_geometry mirror_entities].freeze
    private
    def batch_clock; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
    def run_batch(args,dry)
      steps=args['steps']
      fail_command('invalid_arguments','Provide1..64 typed steps') unless steps.is_a?(Array) && steps.length.between?(1,64)
      fail_command('invalid_arguments','Batch request exceeds48000-byte budget') if JSON.generate(steps).bytesize>48_000
      steps.each do |step|
        unless step.is_a?(Hash) && step.keys.sort==%w[arguments method] && METHODS.include?(step['method']) && step['arguments'].is_a?(Hash)
          fail_command('invalid_arguments','Unsupported batch method or step structure')
        end
        reserved=%w[session_id model_id command_id expected_context dry_run ui_updates owner_id lease expires_at_ms]
        fail_command('invalid_arguments','Step cannot override transport, context, permission or UI policy') unless (step['arguments'].keys & reserved).empty?
      end
      executor=InlineCommandExecutor.new(@model)
      execute=lambda do
        started=batch_clock; results=[]
        steps.each_with_index do |step,index|
          fail_command('batch_budget_exceeded','Four-second batch budget exceeded; entire batch rolled back') if batch_clock-started>4
          begin
            value=executor.call(step['method'],step['arguments'].merge('expected_context'=>args['expected_context'],'dry_run'=>dry))
          rescue StandardError => error
            raise error if error.is_a?(CommandError) && error.code=='outcome_unknown'
            code=error.is_a?(CommandError) ? error.code : 'api_error'
            fail_command('batch_step_failed','Step '+(index+1).to_s+' ('+step['method']+'): '+code+' / '+error.message.to_s[0,160])
          end
          results<<{'index'=>index+1,'method'=>step['method'],'created_ids'=>(value['created'] || []).map { |e| e['persistent_id'] },'no_change'=>value['no_change']==true}
          checked('results'=>results)
        end
        {'dry_run'=>dry,'undoable'=>!dry,'step_count'=>steps.length,'results'=>results,
          'duration_ms'=>((batch_clock-started)*1000).round,
          'notes'=>['One atomic operation; no per-step UI refresh or command IDs. Refresh discovery after topology changes. Created IDs can be used only in a later request, not as references within this batch.']}
      end
      return execute.call.merge('preview_semantics'=>'Each step validated against the original model; previews do not simulate earlier steps') if dry
      operation('Batch '+steps.length.to_s+' commands') { execute.call }
    end
  end
end
