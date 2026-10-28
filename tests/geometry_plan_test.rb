# encoding: UTF-8
require 'minitest/autorun'
require_relative '../extension/su_pipe_probe/command_executor'
class GeometryPlanTest < Minitest::Test
  def setup; @plan=SUPipeProbe::CommandExecutor.new(nil); end
  def plan(method,*args); @plan.send(method,*args); end
  def assert_bad; assert_raises(SUPipeProbe::CommandError) { yield }; end
  def square; [[0,0,0],[100,0,0],[100,100,0],[0,100,0]]; end
  def near_points(actual,expected)
    actual.zip(expected).each { |a,b| a.zip(b).each { |x,y| assert_in_delta y,x,0.00001 } }
  end
  def test_offset_outward_inward_and_reversed_winding
    near_points(plan(:offset_polygon,square,10),[[-10,-10,0],[110,-10,0],[110,110,0],[-10,110,0]])
    near_points(plan(:offset_polygon,square,-10),[[10,10,0],[90,10,0],[90,90,0],[10,90,0]])
    near_points(plan(:offset_polygon,square.reverse,10).reverse,plan(:offset_polygon,square,10))
  end
  def test_offset_rejects_collapse_concavity_and_collinearity
    assert_bad { plan(:offset_polygon,square,-51) }
    assert_bad { plan(:offset_polygon,[[0,0,0],[100,0,0],[20,20,0],[100,100,0],[0,100,0]],10) }
    assert_bad { plan(:offset_polygon,[[0,0,0],[50,0,0],[100,0,0],[100,100,0],[0,100,0]],10) }
  end
  def test_polygon_rejects_nonplanar_crossing_touching_and_duplicate
    [square[0..2]+[[0,100,1]], [square[0],square[2],square[1],square[3]], square+[square[0]], [[0,0,0],[100,0,0],[50,0,0],[50,100,0],[0,100,0]]].each { |p| assert_bad { plan(:planar_polygon,p) } }
  end
  def test_arc_through_three_points_minor_major_and_3d
    [[[10,0,0],[0,10,0],[-10,0,0]],[[10,0,0],[-10,0,0],[0,-10,0]],[[0,10,0],[0,0,10],[0,-10,0]]].each do |points|
      arc=plan(:arc_three,points); samples=plan(:curve_points,arc,48)
      near_points([samples.first,samples.last],[points.first,points.last])
      samples.each { |p| assert_in_delta arc[3],plan(:norm,plan(:sub,p,arc[0])),0.00001 }
      assert samples.any? { |p| plan(:norm,plan(:sub,p,points[1]))<0.0001 }
    end
    assert_bad { plan(:arc_three,[[0,0,0],[1,0,0],[2,0,0]]) }
  end
  def test_bezier_endpoints_midpoint_and_precision
    points=plan(:bezier_points,[[0,0,0],[100,100,0],[200,0,0]],16)
    assert_equal 17,points.length
    near_points([points.first,points[8],points.last],[[0,0,0],[100,50,0],[200,0,0]])
  end
  def test_mesh_requires_closed_consistently_oriented_faces
    p=[[0,0,0],[100,0,0],[0,100,0],[0,0,100]]; f=[[0,2,1],[0,1,3],[1,2,3],[2,0,3]]
    assert_equal f,plan(:mesh_validate,p,f)
    assert_equal f,plan(:mesh_validate,p,f.map(&:reverse))
    translated=p.map { |v| v.map { |x| x+900_000_000 } }
    assert_equal f,plan(:mesh_validate,translated,f)
    assert_bad { plan(:mesh_validate,p,f[0..2]) }
    assert_bad { plan(:mesh_validate,p,[f[0].reverse]+f.drop(1)) }
    assert_bad { plan(:mesh_validate,p,f+[[0,1,99]]) }
  end
  def test_full_partial_and_negative_revolution_are_closed_meshes
    profile=[[100,0,0],[200,0,0],[200,0,100],[100,0,100]]
    [360,180,-180].each do |angle|
      points,faces=plan(:revolution,profile,[0,0,0],[0,0,1],angle,12)
      assert_equal angle.abs==360 ? 48 : 52,points.length
      assert_equal angle.abs==360 ? 48 : 50,faces.length
      assert_equal faces,plan(:mesh_validate,points,faces)
    end
    assert_bad { plan(:revolution,[[100,0,0],[-100,0,0],[-100,0,100],[100,0,100]],[0,0,0],[0,0,1],360,12) }
  end
  def test_revolution_with_axis_vertices_merges_seam
    p,f=plan(:revolution,[[0,0,0],[100,0,0],[100,0,100],[0,0,100]],[0,0,0],[0,0,1],360,12)
    assert_equal 26,p.length
    assert_equal 36,f.length
  end
end
