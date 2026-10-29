# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require_relative 'session'
require_relative 'model_reader'
require_relative 'version'
require_relative 'model_identity'
require_relative 'control_toolbar'

module SUPipeProbe
  # Controller lifetime is independent of the optional information window.
  class Panel
    def initialize
      @error=''
      @model_identity=ModelIdentity.new { @session.tick if @session }
      raise 'Cannot observe model changes; MCP control is unavailable' unless Sketchup.add_observer(@model_identity)
      begin
        require_relative 'win_pipe'
        @pipe=PipeClient.new
      rescue LoadError,StandardError => error
        @error="#{error.class}: #{error.message}"
      end
      @want_connection=false;@last_retry=0;@last_status=0
      @session=Session.new(lambda { |m| send_message(m) },lambda { metadata },nil,
        lambda { |method,args| ModelReader.new(Sketchup.active_model).call(method,args) },
        lambda { |method,args| CommandExecutor.new(Sketchup.active_model).call(method,args) })
      @session.on_change=lambda { render }
      @timer=UI.start_timer(0.05,true) { tick }
    end
    def install_toolbar
      @toolbar ||= ControlToolbar.new(self)
    end
    def metadata
      model=Sketchup.active_model
      {'pid'=>Process.pid,'model_id'=>@model_identity.id_for(model),'title'=>model.title.to_s,
       'path'=>model.path.to_s,'sketchup_version'=>Sketchup.version,'ruby_version'=>RUBY_VERSION,
       'extension_version'=>VERSION,'library_capabilities'=>%w[commands/1 group/1 mesh/1 material-existing/1 verify/1 cleanup/1 target-summary/1 target-subtree/1 face-texture/1 surface-mesh/1],
       'pointer_bits'=>[0].pack('J').bytesize*8}
    end
    def state
      @session.snapshot.merge('session_id'=>@session.session_id,
        'connection'=>@pipe ? @pipe.state.to_s : 'unavailable','retrying'=>@want_connection,
        'transport_error'=>@error,'busy'=>@session.busy?,'info_visible'=>!!(@dialog&&@dialog.visible?))
    end
    def action(name)
      @session.tick
      connected=@pipe&&@pipe.state==:connected
      case name
      when 'toggle_connection'
        action(connected||@want_connection ? 'disconnect' : 'connect')
      when 'connect'
        return unless @pipe
        @want_connection=true;@last_retry=0
        tick
      when 'disconnect'
        @want_connection=false
        @session.reset
        @pipe.close if @pipe
      when 'toggle_permission'
        return unless connected
        @session.authority=='mcp' ? @session.revoke('사용자가 실행 권한을 회수했습니다') : @session.grant
      when 'grant'
        @session.grant if connected
      when 'revoke'
        @session.revoke('사용자가 실행 권한을 회수했습니다')
      when 'stop'
        @session.emergency_stop if @session.busy?
      when 'toggle_info'
        @dialog&&@dialog.visible? ? @dialog.close : show
      when 'ping'
        @session.local_ping if connected
      when 'clear'
        @error='';@session.report_error('')
      when 'ready'
        # HTML has finished loading; render below.
      end
      render
    rescue StandardError => error
      fail_connection(error)
    end
    def show
      if @dialog
        @dialog.show;render
        return
      end
      @dialog=UI::HtmlDialog.new(:dialog_title=>"SketchUp MCP 정보 — PID #{Process.pid}",
        :preferences_key=>'SUPipeProbe.Panel',:width=>540,:height=>570,
        :resizable=>true,:style=>UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_file(File.join(__dir__,'panel.html'))
      @dialog.add_action_callback('action') { |_context,name| action(name) }
      @dialog.set_on_closed do
        @dialog=nil
        # This is an information window. Authority remains visible on the toolbar.
        render
      end
      @dialog.show
      render
    end
    def send_message(message)
      @pipe.send_message(message) if @pipe&&@pipe.state==:connected
    end
    def tick
      return if @ticking
      @ticking=true
      now=Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        if @pipe
          @pipe.poll.each { |m| @session.receive(m) }
          if @want_connection&&@pipe.state==:closed&&now-@last_retry>=2
            @last_retry=now;@pipe.connect;@session.reset;@session.publish('hello');@error=''
            render
          end
          @session.tick if @pipe.state==:connected
        end
        if now-@last_status>=1
          @last_status=now
          @session.publish if @pipe&&@pipe.state==:connected
          render
        end
      rescue StandardError => error
        fail_connection(error)
      ensure
        @ticking=false
      end
    end
    def fail_connection(error)
      @error="#{error.class}: #{error.message}"
      @session.reset
      @pipe.close if @pipe
      @last_retry=Process.clock_gettime(Process::CLOCK_MONOTONIC)
      render
    end
    def render
      return if @rendering
      @rendering=true
      begin
        data=state
        @toolbar.update(data) if @toolbar
        @dialog.execute_script("window.renderState(#{JSON.generate(data)});") if @dialog&&@dialog.visible?
      rescue StandardError => error
        # Display failures must not turn a completed native edit into a failure.
        @error="UI: #{error.class}: #{error.message}"
      ensure
        @rendering=false
      end
    end
  end
  unless file_loaded?(__FILE__)
    @panel=Panel.new
    @panel.install_toolbar
    file_loaded(__FILE__)
  end
end
