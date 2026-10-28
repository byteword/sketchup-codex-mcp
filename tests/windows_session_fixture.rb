# encoding: UTF-8
# Two real Win32 pipe peers driven by the Python MCP integration test.
require 'json'
require_relative '../extension/su_pipe_probe/win_pipe'
require_relative '../extension/su_pipe_probe/session'
require_relative '../extension/su_pipe_probe/version'
require_relative '../extension/su_pipe_probe/model_reader'
require_relative 'support/extended_double'
require_relative '../extension/su_pipe_probe/model_identity'
$stdout.sync = true
control_path = ARGV.fetch(0)
clients, sessions, metadata, identities = [], [], [], []
clock = 0.0
2.times do |index|
  client = SUPipeProbe::PipeClient.new
  model = SketchupDouble::Model.new
  building = model.add(1000 + index)
  model.selection.add([building])
  column = model.add_child(building, 2000 + index, 'ComponentInstance')
  column.name = '기둥 ' + index.to_s
  column.layer = model.layers['구조']
  session = nil
  identity = SUPipeProbe::ModelIdentity.new { session.tick if session }
  data = {'pid' => Process.pid, 'model_id' => identity.id_for(model),
    'title' => "인스턴스 #{index}", 'path' => '', 'extension_version' => SUPipeProbe::VERSION,
    'test_model_wrapper_id' => model.object_id}
  session = SUPipeProbe::Session.new(lambda { |m| client.send_message(m) },
    lambda { data['model_id'] = identity.id_for(model); data },
    lambda { clock }, lambda { |method, args| SUPipeProbe::ModelReader.new(model).call(method, args).merge('instance_index'=>index, 'method'=>method) },
    lambda { |method, args| SUPipeProbe::CommandExecutor.new(model).call(method, args) })
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
  begin
    client.connect
  rescue SUPipeProbe::PipeError
    raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep 0.01
    retry
  end
  clients << client
  sessions << session
  identities << [identity, model]
  metadata << data.merge('session_id' => session.session_id)
  session.publish('hello')
end
puts JSON.generate('instances' => metadata)
sequence = nil
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 90
begin
  loop do
    raise 'Fixture lifetime exceeded' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    begin
      command = JSON.parse(File.read(control_path, :encoding => 'UTF-8'))
    rescue Errno::EACCES, Errno::ENOENT
      # Windows can briefly deny a read while Python atomically replaces this
      # test-control file. Retry only the read, within the fixture deadline.
      sleep 0.005
      next
    end
    if command['sequence'] != sequence
      sequence = command['sequence']
      break if command['stop']
      clock = command['clock'].to_f if command.key?('clock')
      sessions[command['grant']].grant if command.key?('grant')
      if command.key?('change_model')
        # Simulate native New/Open reusing the same Model wrapper and entity IDs.
        # Exercise the production observer, rather than manually replacing UUIDs.
        index = command['change_model']
        changed_identity, changed_model = identities[index]
        if command['change_model_event'] == 'open'
          changed_identity.onOpenModel(changed_model)
        else
          changed_identity.onNewModel(changed_model)
        end
        metadata[index]['model_id'] = sessions[index].snapshot['model_id']
      end
      puts JSON.generate('ack' => sequence, 'instances' => metadata)
    end
    clients.each_with_index do |client, index|
      client.poll.each { |message| sessions[index].receive(message) }
      sessions[index].tick
    end
    sleep 0.005
  end
ensure
  clients.each(&:close)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
  until clients.all? { |client| client.state == :closed }
    raise 'Fixture close timed out' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    clients.each(&:poll)
    sleep 0.01
  end
end
