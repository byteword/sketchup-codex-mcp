# encoding: UTF-8
# API double -> production DXF writer -> external DXF reader (no live SketchUp).
require_relative '../extension/su_pipe_probe/command_executor'
require_relative 'support/file_style_double'
model=SketchupDouble::Model.new
group=model.add(1);group.transformation=Geom::Transformation.translation([500,600,700].map { |n| n/25.4 })
points=[[0,0,0],[1000,0,1000],[1000,2000,500]].map { |p| p.map { |n| n/25.4 } }
points.each_with_index { |p,i| group.entities.add_line(p,points[(i+1)%3]) }
executor=SUPipeProbe::CommandExecutor.new(model)
%w[XY XZ YZ].each do |plane|
  executor.call('model_file',{'expected_context'=>[],'action'=>'export_dxf2d','path'=>File.join(ARGV.fetch(0),plane+'.dxf'),'options'=>{'plane'=>plane}})
end
