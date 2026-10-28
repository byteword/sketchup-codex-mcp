# encoding: UTF-8
require 'json'
module SUPipeProbe
  # Suppression belongs to one synchronous native operation. Never hold it
  # across pipe requests/timer ticks or toggle Windows redraw/tray visibility.
  class UiUpdateScope
    @active={}
    class << self
      attr_reader :active
      def validate(mode)
        raise CommandError.new('invalid_arguments','ui_updates must be defer or normal') unless %w[defer normal].include?(mode)
        mode
      end
    end
    attr_reader :report,:closed,:aborted
    def initialize(model,mode='defer',ui=nil)
      @model,@mode,@ui=model,self.class.validate(mode),ui || (defined?(UI) ? UI : nil)
      @closed,@aborted=false,false
      @report={'mode'=>mode,'suppression_requested'=>mode=='defer','operation_closed'=>false,
        'view_redraw_requested'=>false,'inspectors_refresh_requested'=>false,
        'outliner_control'=>'operation_disable_ui','outliner_visibility_changed'=>false,'warnings'=>[]}
    end
    def run(label,rollback=false)
      key=@model.object_id
      raise CommandError.new('operation_busy','Another MCP operation is already active for this model') if self.class.active.key?(key)
      self.class.active[key]=self
      started=false
      begin
        raise CommandError.new('operation_failed','Could not start Undo operation') unless @model.start_operation('MCP: '+label,@mode=='defer')
        started=true
        data=yield
        # Reserve room for final UI diagnostics before committing geometry.
        raise CommandError.new('result_too_large','Use a smaller operation result') unless data.is_a?(Hash) && JSON.generate(data).bytesize<=42_000
        ok=rollback ? @model.abort_operation : @model.commit_operation
        raise CommandError.new('operation_failed','Could not close Undo operation') unless ok
        @closed,@aborted,started=true,rollback,false
        data
      rescue Exception => error # Release the native operation even on Ruby interruption.
        if started
          begin
            raise 'Abort returned false' unless @model.abort_operation
            @closed,@aborted=true,true
          rescue Exception
            raise CommandError.new('outcome_unknown','Rollback/UI release could not be confirmed; inspect the model before another command')
          end
        end
        raise error
      ensure
        begin
          @report['operation_closed']=@closed
          if @closed
          # A display failure after commit is a warning, never a failed mutation
          # that might lead a caller to repeat already-committed geometry.
            attempt('view redraw') { @model.active_view.invalidate; @report['view_redraw_requested']=true }
            if @mode=='defer'
              attempt('inspector refresh') do
                raise 'API unavailable' unless @ui && @ui.respond_to?(:refresh_inspectors)
                @ui.refresh_inspectors
                @report['inspectors_refresh_requested']=true
              end
            end
          end
        ensure
          self.class.active.delete(key)
        end
      end
    end
    private
    def attempt(label)
      yield
    rescue StandardError,NotImplementedError => error
      @report['warnings']<<label+': '+error.message.to_s[0,120]
    end
  end
end
