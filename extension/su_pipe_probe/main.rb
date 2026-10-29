# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require_relative 'session'
require_relative 'model_reader'
require_relative 'version'
require_relative 'model_identity'

module SUPipeProbe
  class Panel
    def initialize
      @error = ''
      # Keep the observer alive even while the panel is hidden or disconnected.
      # Synchronize authority immediately; receive also checks before dispatch.
      @model_identity = ModelIdentity.new { @session.tick if @session }
      unless Sketchup.add_observer(@model_identity)
        raise 'Cannot observe model changes; MCP control is unavailable'
      end
      begin
        require_relative 'win_pipe'
        @pipe = PipeClient.new
      rescue LoadError, StandardError => error
        @error = "#{error.class}: #{error.message}"
      end
      @want_connection = false
      @last_retry = 0
      @last_status = 0
      @session = Session.new(lambda { |m| send_message(m) }, lambda { metadata }, nil,
        lambda { |method, args| ModelReader.new(Sketchup.active_model).call(method, args) },
        lambda { |method, args| CommandExecutor.new(Sketchup.active_model).call(method, args) })
      @timer = UI.start_timer(0.05, true) { tick }
    end

    def metadata
      model = Sketchup.active_model
      {'pid' => Process.pid, 'model_id' => @model_identity.id_for(model), 'title' => model.title.to_s,
       'path' => model.path.to_s, 'sketchup_version' => Sketchup.version,
       'ruby_version' => RUBY_VERSION, 'extension_version' => VERSION,
       'library_capabilities' => %w[group/1 mesh/1 material-existing/1 verify/1 cleanup/1 target-summary/1 target-subtree/1], 'pointer_bits' => [0].pack('J').bytesize * 8}
    end

    def show
      if @dialog
        @dialog.show
        return
      end
      @dialog = UI::HtmlDialog.new(:dialog_title => "Pipe Probe — PID #{Process.pid}",
        :preferences_key => 'SUPipeProbe.Panel', :width => 540, :height => 610,
        :resizable => true, :style => UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_file(File.join(__dir__, 'panel.html'))
      @dialog.add_action_callback('action') do |_context, action|
        begin
          case action
          when 'connect'
            @want_connection = true
            @last_retry = 0
          when 'disconnect'
            @want_connection = false
            @session.reset
            @pipe.close if @pipe
          when 'grant'
            @session.grant if @pipe && @pipe.state == :connected
          when 'revoke', 'stop'
            @session.revoke('Stopped / user reclaimed control')
          when 'ping'
            @session.local_ping if @pipe && @pipe.state == :connected
          when 'clear'
            @error = ''
            @session.report_error('')
          end
        rescue StandardError => error
          fail_connection(error)
        end
        render
      end
      @dialog.set_on_closed do
        @dialog = nil
        # Closing the control panel must not leave silent remote authority.
        begin
          @session.revoke('Panel closed; user control restored')
        rescue StandardError => error
          fail_connection(error)
        end
      end
      @dialog.show
    end

    def send_message(message)
      @pipe.send_message(message) if @pipe && @pipe.state == :connected
    end

    def tick
      return if @ticking
      @ticking = true
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        if @pipe
          @pipe.poll.each { |m| @session.receive(m) }
          if @want_connection && @pipe.state == :closed && now - @last_retry >= 2
            @last_retry = now
            @pipe.connect
            @session.reset
            @session.publish('hello')
            @error = ''
          end
          @session.tick if @pipe.state == :connected
        end
        if now - @last_status >= 1
          @last_status = now
          @session.publish if @pipe && @pipe.state == :connected
          render
        end
      rescue StandardError => error
        fail_connection(error)
      ensure
        @ticking = false
      end
    end

    def fail_connection(error)
      @error = "#{error.class}: #{error.message}"
      @session.reset
      @pipe.close if @pipe
      # Retry at most once per two seconds; repeated disconnects retain error.
      @last_retry = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      render
    end

    def render
      return unless @dialog && @dialog.visible?
      data = @session.snapshot.merge('session_id' => @session.session_id,
        'connection' => @pipe ? @pipe.state.to_s : 'unavailable',
        'retrying' => @want_connection, 'transport_error' => @error)
      @dialog.execute_script("window.renderState(#{JSON.generate(data)});")
    end
  end

  unless file_loaded?(__FILE__)
    UI.menu('Extensions').add_item('SketchUp Pipe Probe') do
      @panel ||= Panel.new
      @panel.show
    end
    file_loaded(__FILE__)
  end
end
