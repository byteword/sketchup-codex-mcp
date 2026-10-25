# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'
require_relative 'su_pipe_probe/version'

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new('SketchUp Pipe Probe', 'su_pipe_probe/main')
  extension.description = 'Local MCP bridge with model queries and permission-controlled selection, view, properties and movement commands.'
  extension.version = SUPipeProbe::VERSION
  extension.creator = 'byteword'
  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
