# encoding: UTF-8
require_relative 'extended_double'
module Geom
  class Point3d
    def x;to_a[0];end
    def y;to_a[1];end
    def z;to_a[2];end
  end
end
module Sketchup
  class Camera
    def image_width;@image_width || 0.0;end
    attr_writer :image_width
    def focal_length=(mm);self.fov=2*Math.atan((image_width==0 ? 36 : image_width)/(2*mm))*180/Math::PI;end
  end
end
module SketchupDouble
  ImageRep=Struct.new(:pixels,:image_width,:image_height)
  class Texture
    attr_accessor :width,:height,:filename,:fail_size
    def initialize(input)
      @filename=input.is_a?(String) ? input : ''
      @rep=input.is_a?(ImageRep) ? input : ImageRep.new('pixels:'+input,64,32)
      @width,@height=10.0,5.0
    end
    def image_width;@rep.image_width;end
    def image_height;@rep.image_height;end
    def image_rep;@rep.dup;end
    def size=(pair);raise 'Injected size failure' if @fail_size;@width,@height=pair;end
  end
  class TestResource
    attr_accessor :fail_visibility_once
    def texture=(value)
      raise 'Injected image failure' if value=='FAIL'
      @texture=value.nil? || value.is_a?(Texture) ? value : Texture.new(value)
    end
    def visible=(v)
      if @fail_visibility_once;@fail_visibility_once=false;raise 'Injected layer failure';end
      @visible=v
    end
  end
  class Axes
    attr_reader :origin,:xaxis,:yaxis,:zaxis
    attr_accessor :ignore_once
    def initialize;set(Geom::Point3d.new(0,0,0),Geom::Vector3d.new(1,0,0),Geom::Vector3d.new(0,1,0),Geom::Vector3d.new(0,0,1));end
    def set(o,x,y,z)
      if @ignore_once;@ignore_once=false;return self;end
      @origin,@xaxis,@yaxis,@zaxis=o,x,y,z;self
    end
  end
  class Model
    def rendering_options;@rendering_options ||= {'RenderMode'=>3,'Texture'=>true,'DisplayFog'=>false,'BackgroundColor'=>Sketchup::Color.new(255,255,255),'DisplaySketchAxes'=>true};end
    def shadow_info;@shadow_info ||= {'DisplayShadows'=>false,'ShadowTime'=>Time.utc(2026,1,1),'Light'=>80,'Dark'=>45};end
    def axes;@axes ||= Axes.new;end
    def get_attribute(d,k,default=nil);(@model_attributes || {}).fetch(d,{}).fetch(k,default);end
    def set_attribute(d,k,v);@model_attributes||={};(@model_attributes[d]||={})[k]=v;end
    alias_method :start_before_texture_view,:start_operation
    def start_operation(label,disable)
      result=start_before_texture_view(label,disable)
      @operation[:view_attributes]=Marshal.load(Marshal.dump(@model_attributes || {}))
      @operation[:texture_state]=materials.map { |m| [m,m.texture && Marshal.load(Marshal.dump(m.texture))] }
      @operation[:face_sides]=(@primitives || {}).values.select { |e| e.typename=='Face' }.map { |f| [f,f.back_material] }
      result
    end
    alias_method :restore_before_texture_view,:restore
    def restore(snapshot)
      restore_before_texture_view(snapshot)
      @model_attributes=snapshot[:view_attributes]
      snapshot[:texture_state].each { |m,t| m.texture=t }
      snapshot[:face_sides].each { |f,m| f.back_material=m }
    end
  end
  class View;def invalidate;nil;end;end
  class Face
    attr_accessor :uv_shift
    def get_UVHelper(_front,_back)
      shift=@uv_shift || 0
      helper=Object.new
      %w[get_front_UVQ get_back_UVQ].each do |name|
        helper.define_singleton_method(name) { |p| Geom::Point3d.new(p.x+shift,p.y,1+0.01*p.x) }
      end
      helper
    end
  end
end
