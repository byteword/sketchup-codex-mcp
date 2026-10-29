# encoding: UTF-8
module SUPipeProbe
  # Pure numeric geometry in model-space millimeters, also exercised without SketchUp.
  module GeometryPlan
    private
    def options(args,required,optional=[])
      value=args['options']
      fail_command('invalid_arguments','options must be an object') unless value.is_a?(Hash)
      missing=required-value.keys; unknown=value.keys-required-optional
      fail_command('invalid_arguments','Missing options: '+missing.join(', ')) unless missing.empty?
      fail_command('invalid_arguments','Unexpected options: '+unknown.join(', ')) unless unknown.empty?
      value
    end
    def label(value,empty=false,maximum=256)
      fail_command('invalid_arguments','Invalid text') unless value.is_a?(String) && value.valid_encoding? && value.length.between?(empty ? 0 : 1,maximum) && !value.include?("\0")
      value
    end
    def vector(value); numeric_triple({'v'=>value},'v',-1_000_000_000,1_000_000_000); end
    def point_list(value,minimum=1,maximum=256)
      fail_command('invalid_arguments','Invalid point count') unless value.is_a?(Array) && value.length.between?(minimum,maximum)
      value.map { |p| vector(p) }
    end
    def add(a,b); a.zip(b).map { |x,y| x+y }; end
    def sub(a,b); a.zip(b).map { |x,y| x-y }; end
    def mul(a,k); a.map { |x| x*k }; end
    def dot(a,b); a.zip(b).inject(0.0) { |s,(x,y)| s+x*y }; end
    def cross(a,b); [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]; end
    def norm(a); Math.sqrt(dot(a,a)); end
    def unit(a)
      n=norm(a); fail_command('invalid_geometry','Zero or degenerate vector') if n < 1e-8
      mul(a,1.0/n)
    end
    def segments(value,minimum=3)
      fail_command('invalid_arguments','segments must be an integer within bounds') unless value.is_a?(Integer) && value.between?(minimum,128)
      value
    end
    def planar_polygon(points,convex=false)
      fail_command('invalid_geometry','Polygon needs distinct vertices') unless points.length.between?(3,64) && points.uniq.length == points.length
      origin=points.first; u=unit(sub(points[1],origin))
      normal=points.drop(2).map { |p| cross(u,sub(p,origin)) }.find { |n| norm(n)>1e-6 }
      fail_command('invalid_geometry','Collinear polygon') unless normal
      n=unit(normal); v=cross(n,u)
      fail_command('invalid_geometry','Polygon is not planar') if points.any? { |p| dot(sub(p,origin),n).abs>0.001 }
      xy=points.map { |p| d=sub(p,origin); [dot(d,u),dot(d,v)] }
      edges=xy.each_index.map { |i| [xy[i],xy[(i+1)%xy.length]] }
      orient=lambda { |a,b,c| (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]) }
      edges.each_with_index do |(a,b),i|
        fail_command('invalid_geometry','Polygon edge too short') if norm(sub(points[i],points[(i+1)%points.length]))<0.01
        edges.each_with_index do |(c,d),j|
          next if j<=i || j==i+1 || (i==0 && j==edges.length-1)
          o1,o2,o3,o4=[orient.call(a,b,c),orient.call(a,b,d),orient.call(c,d,a),orient.call(c,d,b)]
          overlap=[0,1].all? { |k| [a[k],b[k]].min <= [c[k],d[k]].max+1e-8 && [c[k],d[k]].min <= [a[k],b[k]].max+1e-8 }
          fail_command('invalid_geometry','Self-intersecting/touching polygon') if overlap && o1*o2<=1e-12 && o3*o4<=1e-12
        end
      end
      area=edges.inject(0.0) { |s,(a,b)| s+a[0]*b[1]-a[1]*b[0] }/2.0
      fail_command('invalid_geometry','Polygon area too small') if area.abs<0.01
      if convex
        turns=xy.each_index.map { |i| orient.call(xy[i],xy[(i+1)%xy.length],xy[(i+2)%xy.length])* (area>0 ? 1 : -1) }
        fail_command('unsupported_profile','Offset requires a strictly convex polygon without collinear edges') unless turns.all? { |t| t>1e-6 }
      end
      [origin,u,v,n,xy,area]
    end
    def offset_polygon(points,distance)
      origin,u,v,_n,xy,area=planar_polygon(points,true)
      lines=xy.each_index.map do |i|
        a,b=xy[i],xy[(i+1)%xy.length]; dx,dy=b[0]-a[0],b[1]-a[1]; len=Math.sqrt(dx*dx+dy*dy)
        outward=[dy/len,-dx/len].map { |x| x*(area>0 ? 1 : -1) }
        [add(a,mul(outward,distance)),[dx,dy],outward]
      end
      result=lines.each_index.map do |i|
        a,d=lines[(i-1)%lines.length]; b,e=lines[i]
        determinant=d[0]*e[1]-d[1]*e[0]
        fail_command('invalid_geometry','Parallel offset edges') if determinant.abs<1e-10
        t=((b[0]-a[0])*e[1]-(b[1]-a[1])*e[0])/determinant
        add(a,mul(d,t))
      end
      fail_command('invalid_geometry','Offset collapsed or inverted') unless result.all? { |p| lines.all? { |a,_d,n| dot(sub(p,a),n)<=0.001 } }
      output=result.map { |p| add(origin,add(mul(u,p[0]),mul(v,p[1]))) }
      planar_polygon(output,true); output
    end
    def arc_three(points)
      a,b,c=points; ab,ac=sub(b,a),sub(c,a); n=cross(ab,ac); squared=dot(n,n)
      fail_command('invalid_geometry','Arc points must be distinct and noncollinear') if squared<1e-8
      center=add(a,mul(add(mul(cross(ac,n),dot(ab,ab)),mul(cross(n,ab),dot(ac,ac))),1.0/(2*squared)))
      radius=norm(sub(a,center)); fail_command('invalid_geometry','Arc radius outside 1..1000000 mm') unless radius.between?(1,1_000_000)
      u=unit(sub(a,center)); normal=unit(n); v=cross(normal,u)
      angle=Math.atan2(dot(sub(c,center),v),dot(sub(c,center),u)); angle+=2*Math::PI if angle<=0
      [center,u,normal,radius,0.0,angle]
    end
    def curve_points(arc,count)
      c,u,n,r,start,sweep=arc; v=cross(n,u)
      (0..count).map { |i| angle=start+sweep*i/count; add(c,mul(add(mul(u,Math.cos(angle)),mul(v,Math.sin(angle))),r)) }
    end
    def bezier_points(control,count)
      (0..count).map do |i|
        t=i.to_f/count; work=control.map(&:dup)
        while work.length>1; work=work.each_cons(2).map { |a,b| add(mul(a,1-t),mul(b,t)) }; end
        work.first
      end
    end
    def mesh_validate(points,faces,maximum_faces=256,maximum_corners=2048)
      fail_command('invalid_geometry','Invalid polyhedron face count') unless faces.is_a?(Array) && faces.length.between?(4,maximum_faces) && faces.inject(0) { |s,f| s+(f.is_a?(Array) ? f.length : maximum_corners+1) }<=maximum_corners
      usage=Hash.new { |h,k| h[k]=[] }
      volume=0.0
      faces.each do |face|
        fail_command('invalid_geometry','Invalid face indices') unless face.is_a?(Array) && face.length.between?(3,64) && face.uniq.length==face.length && face.all? { |i| i.is_a?(Integer) && i.between?(0,points.length-1) }
        p=face.map { |i| points[i] }; planar_polygon(p)
        face.each_index { |i| a,b=face[i],face[(i+1)%face.length]; usage[[a,b].sort]<<[a,b] }
        # Translate before the volume sum to avoid cancellation far from origin.
        reference=points.first
        p.drop(1).each_cons(2) { |b,c| volume+=dot(sub(p.first,reference),cross(sub(b,reference),sub(c,reference)))/6.0 }
      end
      fail_command('invalid_geometry','Mesh must be closed with consistently oriented faces') unless usage.values.all? { |edges| edges.length==2 && edges[0]==edges[1].reverse } && volume.abs>0.001
      volume<0 ? faces.map(&:reverse) : faces
    end
    def revolution(points,pivot,axis,sweep,count)
      planar_polygon(points)
      axis=unit(axis)
      radial=points.map { |p| d=sub(p,pivot); sub(d,mul(axis,dot(d,axis))) }.find { |p| norm(p)>0.01 }
      fail_command('invalid_geometry','Profile lies on rotation axis') unless radial
      radial=unit(radial); normal=cross(axis,radial)
      fail_command('unsupported_profile','Revolution profile must lie in one half-plane through the axis') unless points.all? { |p| d=sub(p,pivot); dot(d,normal).abs<=0.001 && dot(d,radial)>=-0.001 }
      closed=(sweep.abs-360).abs<1e-8; rows=closed ? count : count+1
      vertices=[]; index={}
      rings=(0...rows).map do |i|
        angle=sweep*Math::PI/180*i/count
        points.map do |p|
          d=sub(p,pivot); rotated=add(add(mul(d,Math.cos(angle)),mul(cross(axis,d),Math.sin(angle))),mul(axis,dot(axis,d)*(1-Math.cos(angle))))
          q=add(pivot,rotated); key=q.map { |x| (x*10000).round }
          index[key] ||= begin vertices<<q; vertices.length-1 end
        end
      end
      faces=[]
      count.times do |i|
        a,b=rings[i],rings[(i+1)%rows]
        points.each_index do |j|
          k=(j+1)%points.length; face=[a[j],a[k],b[k],b[j]].uniq
          faces<<face if face.length>=3
        end
      end
      faces += [rings.first.reverse,rings.last] unless closed
      [vertices,mesh_validate(vertices,faces)]
    end
  end
end
