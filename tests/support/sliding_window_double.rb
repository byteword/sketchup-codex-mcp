# encoding: UTF-8
require_relative 'extended_double'
# Geometry doubles cannot dissolve a whole perforated annulus. Full recipe
# topology/cleanup remains a native acceptance gate; transport tests use this
# explicit builder fixture and test the optimizer separately on a split cube.
module SlidingWindowDouble
  class Model < SketchupDouble::Model
    def spawn(collection,type)
      entity=super
      entity.definition.define_singleton_method(:bounds) do
        children=entities.select { |e| %w[Group ComponentInstance].include?(e.typename) }
        return @bounds if children.empty?
        box=Geom::BoundingBox.new
        8.times { |i| box.add(@bounds.corner(i)) } unless @bounds.empty?
        children.each do |child|
          b=child.definition.bounds
          8.times { |i| box.add(b.corner(i).transform(child.transformation)) } unless b.empty?
        end
        box
      end
      entity
    end
  end
  class Executor < SUPipeProbe::CommandExecutor
    attr_reader :optimized_sections
    def window_optimize(group,started)
      window_budget!(started)
      @optimized_sections ||= []; @optimized_sections<<group
      {'removed_coplanar_edges'=>0,'hidden_textured_seams'=>0}
    end
  end
end
