# encoding: UTF-8
module SUPipeProbe
  class ControlToolbar
    attr_reader :commands, :toolbar
    def initialize(controller)
      @controller=controller;@commands={};@flags={};@appearance={}
      @toolbar=UI::Toolbar.new('SketchUp MCP')
      labels={'connection'=>'연결 / 연결 해제','permission'=>'권한 부여 / 회수','stop'=>'긴급 정지','info'=>'추가 정보창'}
      actions={'connection'=>'toggle_connection','permission'=>'toggle_permission','stop'=>'stop','info'=>'toggle_info'}
      labels.each do |key,label|
        command=UI::Command.new(label) { @controller.action(actions[key]) }
        command.set_validation_proc { @flags.fetch(key,MF_GRAYED|MF_DISABLED) }
        @commands[key]=command
      end
      update(@controller.state)
      @commands.each_value { |command| @toolbar.add_item(command) }
      menu=UI.menu('Extensions').add_submenu('SketchUp MCP')
      @commands.each_value { |command| menu.add_item(command) }
      menu.add_item('툴바 표시') { @toolbar.show }
      @toolbar.get_last_state==TB_NEVER_SHOWN ? @toolbar.show : @toolbar.restore
    end
    def update(s)
      connected=s['connection']=='connected'
      pending=s['retrying']&&!connected
      unavailable=s['connection']=='unavailable'
      error=(pending||unavailable)&&!s['transport_error'].to_s.empty?
      connection=connected ? 'connected' : error ? 'error' : pending ? 'waiting' : 'disconnected'
      connection_text=connected ? '연결됨 · 클릭하여 연결 해제' : pending ? '연결 대기 중 · 클릭하여 재연결 중단' : '연결 안 됨 · 클릭하여 Probe에 연결'
      connection_text='연결 기능을 사용할 수 없음 · 정보창 확인' if unavailable
      decorate('connection','connection_'+connection,connection_text,unavailable ? MF_GRAYED|MF_DISABLED : (connected||pending ? MF_CHECKED : MF_UNCHECKED))
      granted=connected&&s['authority']=='mcp'
      decorate('permission',granted ? 'permission_mcp' : 'permission_user',
        granted ? '명령 실행 허용 중 · 클릭하여 권한 회수' : '사용자 제어 · 클릭하여 명령 실행 허용',
        !connected ? MF_GRAYED|MF_DISABLED : granted ? MF_CHECKED : MF_UNCHECKED)
      busy=s['busy'];stopping=s['stop_requested']
      decorate('stop','stop',stopping ? '중지 요청됨 · 실행 결과 확인 중' : '진행 중 작업 중지 요청 + 실행 권한 회수',
        busy&&!stopping ? MF_ENABLED : MF_GRAYED|MF_DISABLED)
      decorate('info','info',s['info_visible'] ? '정보창 닫기' : '연결·권한·작업 상세 정보',s['info_visible'] ? MF_CHECKED : MF_UNCHECKED)
    end
    private
    def decorate(key,icon,tooltip,flags)
      @flags[key]=flags
      current=[icon,tooltip,flags]
      return if @appearance[key]==current
      command=@commands.fetch(key)
      if !@appearance[key] || @appearance[key][0]!=icon
        path=File.join(__dir__,'icons',icon+'.svg')
        command.small_icon=path;command.large_icon=path
      end
      command.tooltip=tooltip;command.status_bar_text=tooltip
      @appearance[key]=current
      UI.refresh_toolbars if UI.respond_to?(:refresh_toolbars)
    end
  end
end
