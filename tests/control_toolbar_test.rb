# encoding: UTF-8
require 'minitest/autorun'
# Exercise the production controller and toolbar without opening native windows.
MF_ENABLED=0;MF_GRAYED=1;MF_DISABLED=2;MF_CHECKED=8;MF_UNCHECKED=0
TB_NEVER_SHOWN=-1;TB_HIDDEN=0;TB_VISIBLE=1
module Sketchup
  class AppObserver;end
  Model=Struct.new(:title,:path)
  def self.active_model;@model ||= Model.new('시험','');end
  def self.add_observer(observer);(@observers ||= []) << observer;true;end
  def self.version;'20.0';end
end
module UI
  class << self
    attr_accessor :last_state,:dialogs,:refreshes
    def reset;self.last_state=TB_NEVER_SHOWN;self.dialogs=[];self.refreshes=0;end
    def start_timer(*args,&block);block;end
    def refresh_toolbars;self.refreshes+=1;end
    def menu(name);Menu.new;end
  end
  class Menu
    def add_submenu(name);Menu.new;end
    def add_item(*args,&block);end
  end
  class Command
    attr_accessor :tooltip,:status_bar_text
    attr_reader :small_icon,:large_icon,:icon_writes,:label
    def initialize(label,&action);@label=label;@action=action;@icon_writes=0;end
    def set_validation_proc(&block);@validation=block;end
    def flags;@validation.call;end
    def invoke;@action.call;end
    def small_icon=(path);raise 'Missing icon' unless File.file?(path);@small_icon=path;@icon_writes+=1;end
    def large_icon=(path);@large_icon=path;@icon_writes+=1;end
  end
  class Toolbar
    attr_reader :items,:restored,:shown
    def initialize(name);@items=[];end
    def get_last_state;UI.last_state;end
    def add_item(command);@items << command;end
    def show;@shown=true;end
    def restore;@restored=true;@shown=UI.last_state==TB_VISIBLE;end
  end
  class HtmlDialog
    STYLE_DIALOG=0
    attr_accessor :script_failure
    attr_reader :scripts
    def initialize(options);@scripts=[];UI.dialogs << self;end
    def set_file(path);raise 'Missing HTML' unless File.file?(path);end
    def add_action_callback(name,&block);@action=block;end
    def set_on_closed(&block);@closed=block;end
    def show;@visible=true;end
    def visible?;@visible;end
    def close;@visible=false;@closed.call;end
    def execute_script(script);raise 'Display failure' if @script_failure;@scripts << script;end
    def ready;@action.call(nil,'ready');end
  end
end
module SUPipeProbe
  class PipeClient
    attr_accessor :state,:connect_error,:messages
    attr_reader :sent
    def initialize;@state=:closed;@sent=[];@messages=[];end
    def connect;raise @connect_error if @connect_error;@state=:connected;end
    def close;@state=:closed;end
    def send_message(message);@sent << message;end
    def poll;result=@messages;@messages=[];result;end
  end
end
def file_loaded?(path);false;end
def file_loaded(path);end
UI.reset
$LOADED_FEATURES << 'sketchup.rb'
$LOADED_FEATURES << File.expand_path('../extension/su_pipe_probe/win_pipe.rb',__dir__)
require_relative '../extension/su_pipe_probe/main'

class ControlToolbarTest < Minitest::Test
  def setup
    UI.reset
    @panel=SUPipeProbe::Panel.new
    @toolbar=@panel.install_toolbar
    @commands=@toolbar.commands
    @session=@panel.instance_variable_get(:@session)
    @pipe=@panel.instance_variable_get(:@pipe)
  end
  def click(key);@commands.fetch(key).invoke;end
  def disabled?(key);(@commands[key].flags&(MF_DISABLED|MF_GRAYED))!=0;end
  def connected
    click('connection');assert_equal 'connected',@panel.state['connection']
  end
  def granted
    connected;click('permission');assert_equal 'mcp',@session.authority
  end
  def jobs(*ids)
    @session.receive(@session.envelope('bridge_state','library_jobs'=>ids.map { |id| {'job_id'=>id,'model_id'=>@panel.metadata['model_id'],'stage'=>'plan'} }))
  end
  def test_initial_four_buttons_and_no_information_popup
    assert_equal %w[connection permission stop info],@commands.keys
    assert_equal 4,@toolbar.toolbar.items.length
    assert @toolbar.toolbar.shown
    assert_empty UI.dialogs
    assert disabled?('permission');assert disabled?('stop')
    assert_match(/disconnected.svg$/,@commands['connection'].small_icon)
  end
  def test_restore_hidden_toolbar_preference
    UI.last_state=TB_HIDDEN
    other=SUPipeProbe::Panel.new.install_toolbar
    assert other.toolbar.restored
    refute other.toolbar.shown
  end
  def test_connection_and_permission_colors_without_dialog
    granted
    assert_match(/connected.svg$/,@commands['connection'].small_icon)
    assert_match(/permission_mcp.svg$/,@commands['permission'].small_icon)
    lease=@session.lease
    click('permission');assert_nil @session.lease
    assert_match(/permission_user.svg$/,@commands['permission'].small_icon)
    click('permission');refute_equal lease,@session.lease
    assert_empty UI.dialogs
  end
  def test_information_toggle_and_close_preserve_connection_and_lease
    granted;lease=@session.lease
    click('info');dialog=UI.dialogs.last
    assert dialog.visible?
    assert_equal MF_CHECKED,@commands['info'].flags
    dialog.ready;refute_empty dialog.scripts
    click('info');refute dialog.visible?
    assert_equal lease,@session.lease
    assert_equal 'connected',@panel.state['connection']
    click('info');refute_same dialog,UI.dialogs.last
    UI.dialogs.last.close
    assert_equal lease,@session.lease
    assert_equal MF_UNCHECKED,@commands['info'].flags
  end
  def test_disconnect_revokes_and_reconnect_does_not_regrant
    granted;jobs('job-a')
    click('connection')
    assert_nil @session.lease;refute @session.busy?
    assert disabled?('permission');assert disabled?('stop')
    click('connection')
    assert_equal 'user',@session.authority
  end
  def test_idle_stop_is_disabled_and_does_not_revoke
    granted;lease=@session.lease
    assert disabled?('stop')
    click('stop')
    assert_equal lease,@session.lease
  end
  def test_stop_cancels_demo_and_revokes_permission
    granted
    @session.receive(@session.envelope('request','id'=>'demo-a','method'=>'demo','lease'=>@session.lease,'model_id'=>@panel.metadata['model_id']))
    refute disabled?('stop')
    click('stop')
    assert_nil @session.job;assert_nil @session.lease
    assert_equal 'user',@session.authority
    assert disabled?('stop')
    assert @pipe.sent.any? { |m| m['event']=='emergency_stop' }
  end
  def test_library_stop_is_pending_until_activity_clears_and_new_jobs_can_stop
    granted;jobs('a')
    refute disabled?('stop')
    click('stop')
    assert_equal 'user',@session.authority
    assert @session.busy?;assert @session.stop_requested?
    assert disabled?('stop')
    jobs('a');assert disabled?('stop')
    jobs('a','b');refute disabled?('stop')
    jobs;assert disabled?('stop');refute @session.stop_requested?
  end
  def test_foreign_model_activity_is_ignored
    connected
    @session.receive(@session.envelope('bridge_state','library_jobs'=>[{'job_id'=>'other','model_id'=>'foreign'}]))
    refute @session.busy?
    assert disabled?('stop')
  end
  def test_model_change_revokes_while_information_hidden
    granted;jobs('a')
    @panel.instance_variable_get(:@model_identity).onNewModel(Sketchup.active_model)
    assert_nil @session.lease;assert_empty @session.snapshot['library_jobs']
    assert_match(/permission_user.svg$/,@commands['permission'].small_icon)
    assert_empty UI.dialogs
  end
  def test_connection_error_and_manual_stop_retry
    @pipe.connect_error=RuntimeError.new('Probe unavailable')
    click('connection')
    assert @panel.state['retrying']
    assert_match(/connection_error.svg$/,@commands['connection'].small_icon)
    click('connection')
    refute @panel.state['retrying']
    assert_match(/connection_disconnected.svg$/,@commands['connection'].small_icon)
  end
  def test_render_errors_do_not_revoke_permission
    granted;lease=@session.lease
    click('info');UI.dialogs.last.script_failure=true
    @session.publish
    assert_equal lease,@session.lease
    assert_equal 'connected',@panel.state['connection']
    assert_match(/UI:/,@panel.state['transport_error'])
  end
  def test_unchanged_state_does_not_reload_icons
    connected
    before=@commands.values.map(&:icon_writes)
    10.times { @panel.render }
    assert_equal before,@commands.values.map(&:icon_writes)
  end
end
