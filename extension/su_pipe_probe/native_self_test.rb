# encoding: UTF-8
require_relative 'model_reader'
require_relative 'extended_self_checks'

module SUPipeProbe
  # Fixed internal suite, never user-supplied Ruby or arbitrary batch commands.
  # Normal command validation/postconditions run inside a single outer operation;
  # sub-command Undo boundaries are deliberately suppressed and NOT certified.
  class NativeSelfTest
    include ExtendedSelfChecks
    CHECKS = %w[box rectangle circle polyline entity_info face_edge_metrics push_pull rotate scale move duplicate selection properties locked_rejection unlock erase group make_unique nested_query view_top view_front view_right view_isometric zoom].freeze
    class InlineExecutor < CommandExecutor
      private
      def operation(_label)
        checked(yield)
      end
    end

    def initialize(model,clock=nil)
      @model = model
      @clock = clock || lambda { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    end

    def call(args,dry=false)
      raise CommandError.new('invalid_arguments','confirm_test_model=true is required') unless args['confirm_test_model'] == true
      raise CommandError.new('context_mismatch','Run the suite at model root') unless (@model.active_path || []).empty? && args['expected_context'] == []
      if @model.entities.length > 1000 || @model.definitions.length > 5000 || @model.selection.length > 1000
        raise CommandError.new('test_model_too_large','Use a small dedicated test model')
      end
      suite=args.fetch('suite','core')
      raise CommandError.new('invalid_arguments','suite must be core, extended or all') unless %w[core extended all].include?(suite)
      planned=(suite=='extended' ? [] : CHECKS)+(suite=='core' ? [] : ExtendedSelfChecks::CHECKS)
      return {'dry_run'=>true,'undoable'=>false,'suite'=>suite,'planned_checks'=>planned,'temporary_geometry'=>true} if dry
      @executor,@reader = InlineExecutor.new(@model),ModelReader.new(@model)
      @checks,@started_at = [],@clock.call
      root_before = keys(@model.entities)
      definitions_before = keys(@model.definitions)
      resources_before = suite=='core' ? nil : [keys(@model.layers),keys(@model.materials),keys(@model.pages)]
      selection_before = @model.selection.to_a
      modified_before = @model.modified?
      active_layer = @model.active_layer if @model.respond_to?(:active_layer)
      camera = nil
      begin
        camera = @executor.send(:camera_copy,@model.active_view.camera)
      rescue CommandError => error
        raise unless error.code == 'unsupported_camera'
      end
      camera_before = camera && @executor.send(:camera_state,camera)
      started,aborted,restore_ok = false,false,true
      begin
        raise 'Could not start test operation' unless @model.start_operation('MCP: temporary native smoke test',true)
        started = true
        run_checks(camera) unless suite=='extended'
        run_extended_checks(camera) unless suite=='core'
      rescue StandardError => error
        @checks << {'name'=>'suite','status'=>'failed','message'=>error.message.to_s[0,256]} if @checks.none? { |c| c['status'] == 'failed' }
      ensure
        begin
          @model.selection.clear
          @model.selection.add(selection_before) unless selection_before.empty?
          @model.active_view.camera = camera if camera
        rescue StandardError
          restore_ok = false
        ensure
          begin
            aborted = !!@model.abort_operation if started
          rescue StandardError
            aborted = false
          end
        end
      end
      cleanup = aborted && restore_ok && root_before == keys(@model.entities) && definitions_before == keys(@model.definitions) &&
        keys(selection_before) == keys(@model.selection) && (!camera || camera_before == @executor.send(:camera_state,@model.active_view.camera)) &&
        (!@model.respond_to?(:active_layer) || active_layer == @model.active_layer)
      cleanup &&= resources_before == [keys(@model.layers),keys(@model.materials),keys(@model.pages)] if resources_before
      raise CommandError.new('outcome_unknown','Self-test rollback/UI restoration could not be verified; inspect the test model. Do not retry.') unless cleanup
      remaining = planned-@checks.map { |c| c['name'] }
      remaining.each { |name| @checks << {'name'=>name,'status'=>'skipped','reason'=>'Stopped after a failure'} }
      @checks << {'name'=>'cleanup','status'=>'passed'}
      if modified_before != @model.modified?
        @checks << {'name'=>'modified_state','status'=>'failed','message'=>'Geometry/UI restored but the model modified flag changed'}
      end
      {'dry_run'=>false,'undoable'=>false,'suite'=>suite,'passed'=>@checks.none? { |c| c['status'] == 'failed' },
       'passed_count'=>@checks.count { |c| c['status'] == 'passed' },'failed_count'=>@checks.count { |c| c['status'] == 'failed' },
       'skipped_count'=>@checks.count { |c| c['status'] == 'skipped' },'checks'=>@checks,
       'duration_ms'=>((@clock.call-@started_at)*1000).round,'cleanup_verified'=>true,
       'modified_before'=>modified_before,'modified_after'=>@model.modified?,
       'individual_undo_tested'=>false,'model_lifecycle_tested'=>false,
       'notes'=>['All edits were temporary and aborted in one operation. Individual command Undo, New/Open and permission revocation require separate acceptance tests.']}
    end

    private
    def keys(collection)
      collection.map { |entity| entity.entityID.to_s }.sort
    end
    def step(name)
      raise 'Four-second cooperative test budget exceeded' if @clock.call-@started_at > 4
      result = yield
      @checks << {'name'=>name,'status'=>'passed'}
      result
    rescue StandardError => error
      @checks << {'name'=>name,'status'=>'failed','message'=>error.message.to_s[0,256]}
      raise
    end
    def command(method,fields={})
      @executor.call(method,{'expected_context'=>[]}.merge(fields))
    end
    def query(id)
      @reader.call('get_entity_info',{'instance_path'=>[id]})['item']
    end
    def near(actual,expected)
      raise 'Unexpected numeric result' unless actual.to_f.finite? && (actual-expected).abs <= [0.001,expected.abs*1e-8].max
    end
    def require_true(value,message)
      raise message unless value
    end
    def created(method,fields)
      command(method,fields)['created'].first['persistent_id']
    end

    def run_checks(camera)
      prefix = 'MCP temporary test '
      box = step('box') { created('create_box','name'=>prefix+'box','origin_mm'=>[0,0,0],'size_mm'=>[1000,2000,3000]) }
      rect = step('rectangle') { created('create_rectangle','name'=>prefix+'rectangle','origin_mm'=>[0,0,0],'size_mm'=>[1000,2000],'plane'=>'XY') }
      circle = step('circle') { created('create_circle','name'=>prefix+'circle','origin_mm'=>[5000,0,0],'radius_mm'=>500,'plane'=>'XY','segments'=>24) }
      line = step('polyline') { created('create_polyline','name'=>prefix+'line','points_mm'=>[[0,5000,0],[1000,5000,0],[1000,7000,0]]) }
      step('entity_info') do
        item = query(box)
        [1000,2000,3000].zip(item['model_bounds']['size']).each { |a,b| near(b,a) }
        near(query(rect)['direct_geometry']['face_area_mm2'],2_000_000)
        near(query(circle)['direct_geometry']['face_area_mm2'],24*0.5*500**2*Math.sin(2*Math::PI/24))
        near(query(line)['direct_geometry']['edge_length_mm'],3000)
      end
      step('face_edge_metrics') do
        children = query(rect)['direct_children']
        face = children.find { |e| e['type'] == 'Face' }
        edge = children.find { |e| e['type'] == 'Edge' }
        require_true(face && edge,'Profile child paths are missing')
        near(@reader.call('get_entity_info',face)['item']['area_mm2'],2_000_000)
        require_true(@reader.call('get_entity_info',edge)['item']['length_mm'] >= 999.999,'Edge length missing')
      end
      step('push_pull') do
        command('push_pull','entity_ids'=>[rect],'distance_mm'=>3000)
        require_true(query(rect)['manifold'],'Profile did not become a solid')
        near(query(rect)['model_bounds']['size'][2],3000)
      end
      step('rotate') do
        command('rotate_entities','entity_ids'=>[box],'pivot_mm'=>[0,0,0],'axis'=>[0,0,1],'angle_degrees'=>90)
        near(query(box)['model_bounds']['min'][0],-2000)
      end
      step('scale') do
        command('scale_entities','entity_ids'=>[box],'pivot_mm'=>[0,0,0],'factors'=>[2,1,1])
        near(query(box)['model_bounds']['min'][0],-4000)
      end
      step('move') do
        command('move_entities','entity_ids'=>[box],'delta_mm'=>[1000,0,0])
        near(query(box)['model_bounds']['min'][0],-3000)
      end
      copy = step('duplicate') do
        id = command('duplicate_entities','entity_ids'=>[box],'delta_mm'=>[10000,0,0])['created'].first['persistent_id']
        near(query(id)['model_bounds']['min'][0],7000)
        id
      end
      step('selection') do
        command('set_selection','entity_ids'=>[box,copy],'mode'=>'replace')
        require_true(@model.selection.length == 2,'Selection mismatch')
      end
      step('properties') do
        command('update_entity_properties','entity_ids'=>[box],'properties'=>{'name'=>prefix+'renamed','hidden'=>true})
        item = query(box)
        require_true(item['name'] == prefix+'renamed' && item['hidden'],'Properties mismatch')
      end
      step('locked_rejection') do
        command('update_entity_properties','entity_ids'=>[box],'properties'=>{'locked'=>true})
        begin
          command('move_entities','entity_ids'=>[box],'delta_mm'=>[1,0,0])
          raise 'A locked object was moved'
        rescue CommandError => error
          raise unless error.code == 'entity_locked'
        end
      end
      step('unlock') { command('update_entity_properties','entity_ids'=>[box],'properties'=>{'locked'=>false}) }
      step('erase') do
        command('erase_entities','entity_ids'=>[copy])
        require_true(!@model.find_entity_by_persistent_id(copy.to_i) || !@model.find_entity_by_persistent_id(copy.to_i).valid?,'Copy still exists')
      end
      outer=step('group') { command('group_entities','entity_ids'=>[circle,line])['created'].first['persistent_id'] }
      step('make_unique') do
        original=@model.find_entity_by_persistent_id(outer.to_i)
        shared=original.copy
        command('make_unique','entity_ids'=>[shared.persistent_id.to_s])
        require_true(original.definition != shared.definition,'Outer definitions are still shared')
      end
      step('nested_query') do
        command('rotate_entities','entity_ids'=>[outer],'pivot_mm'=>[0,0,0],'axis'=>[0,0,1],'angle_degrees'=>30)
        command('scale_entities','entity_ids'=>[outer],'pivot_mm'=>[0,0,0],'factors'=>[2,1,1])
        nested=@reader.call('get_entity_info',{'instance_path'=>[outer,circle]})['item']
        near(nested['direct_geometry']['face_area_mm2'],2*24*0.5*500**2*Math.sin(2*Math::PI/24))
      end
      %w[top front right isometric].each do |preset|
        if camera
          step('view_'+preset) { command('set_view','preset'=>preset) }
        else
          @checks << {'name'=>'view_'+preset,'status'=>'skipped','reason'=>'Unsupported special camera'}
        end
      end
      if camera
        step('zoom') { command('zoom','scope'=>'entities','entity_ids'=>[rect]) }
      else
        @checks << {'name'=>'zoom','status'=>'skipped','reason'=>'Unsupported special camera'}
      end
    end
  end
end
