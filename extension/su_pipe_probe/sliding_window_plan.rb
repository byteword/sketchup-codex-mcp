# encoding: UTF-8
module SUPipeProbe
  # Deterministic data only. No model, UI, session IDs or native objects.
  class SlidingWindowPlan
    def self.number(args,key,default,lo,hi)
      value=args.fetch(key,default)
      raise ArgumentError,key+' must be a finite number within range' unless value.is_a?(Numeric) && value.to_f.finite? && value>=lo && value<=hi
      value.to_f
    end
    def self.build(args)
      w=number(args,'width_mm',nil,600,6000); h=number(args,'height_mm',nil,400,3600); d=number(args,'depth_mm',nil,80,300)
      fw=number(args,'frame_width_mm',40,30,100); sw=number(args,'sash_width_mm',35,20,80)
      glass=number(args,'glass_thickness_mm',6,3,12); overlap=number(args,'overlap_mm',sw+5,20,160)
      fraction=number(args,'open_fraction',0,0,1); moving=args.fetch('open_sash','none')
      raise ArgumentError,'open_sash must be none, left or right' unless %w[none left right].include?(moving)
      raise ArgumentError,'Choose a sash for a nonzero opening' if moving=='none' && fraction>0
      raise ArgumentError,'Overlap must fit the two meeting stiles' unless overlap.between?(sw,2*sw-4)
      r=fw+5; leaf_w=(w-2*r+overlap)/2; leaf_h=h-2*r; thick=0.24*d
      raise ArgumentError,'Requested frame leaves insufficient glass/handle clearance' if leaf_w-2*sw-1<100 || leaf_h-2*sw-1<100
      raise ArgumentError,'Depth is too small for the requested glass' if thick-glass<12
      pane_front=(thick-glass)/2; pane_back=(thick+glass)/2
      outer=[[0,0],[d,0],[d,fw],[0.88*d,fw],[0.88*d,fw-2],[0.70*d,fw-2],[0.70*d,r],[0.66*d,r],[0.66*d,fw-2],[0.34*d,fw-2],[0.34*d,r],[0.30*d,r],[0.30*d,fw-2],[0.12*d,fw-2],[0.12*d,fw],[0,fw]]
      profile=[[0,0],[thick,0],[thick,sw],[pane_back+3,sw],[pane_back+3,sw+2],[pane_back+1,sw+2],[pane_back+1,sw+4],[pane_back+0.2,sw+4],[pane_back+0.2,sw],[pane_front-0.2,sw],[pane_front-0.2,sw+4],[pane_front-1,sw+4],[pane_front-1,sw+2],[pane_front-3,sw+2],[pane_front-3,sw],[0,sw]]
      travel=w-2*r-leaf_w
      left=r+(moving=='left' ? travel*fraction : 0)
      right=w-r-leaf_w-(moving=='right' ? travel*fraction : 0)
      sections=[ring('fixed',0,0,w,h,0,outer,[],nil,sw)]
      [['left',left,0.20*d],['right',right,0.56*d]].each do |which,x,y|
        mesh=ring(which,x,r,leaf_w,leaf_h,y,profile,[5,6,7,9,10,11],which,sw)
        pane(mesh,x+sw+0.5,y+pane_front,r+sw+0.5,leaf_w-2*sw-1,glass,leaf_h-2*sw-1)
        validate_mesh(mesh)
        sections<<mesh
      end
      validate_mesh(sections.first)
      {'recipe'=>'sliding_two_panel_v1','size_mm'=>[w,h,d],'size_axes_xyz_mm'=>[w,d,h],
       'frame_width_mm'=>fw,'sash_width_mm'=>sw,'glass_thickness_mm'=>glass,'overlap_mm'=>overlap,
       'leaf_size_mm'=>[leaf_w,leaf_h,thick],'travel_mm'=>travel,'sash_depth_gap_mm'=>0.12*d,
       'open_sash'=>moving,'open_fraction'=>fraction,'group_count'=>4,'sections'=>sections}
    end
    def self.ring(section,left,bottom,w,h,y,profile,brown,handle,sw)
      points=profile.flat_map { |depth,r| [[left+r,y+depth,bottom+r],[left+w-r,y+depth,bottom+r],[left+w-r,y+depth,bottom+h-r],[left+r,y+depth,bottom+h-r]] }
      faces=[]; roles=[]; n=profile.length; handle_bounds=nil
      n.times do |i|
        4.times do |k|
          f=[i*4+k,i*4+(k+1)%4,((i+1)%n)*4+(k+1)%4,((i+1)%n)*4+k]
          if handle && i==n-1 && k==(handle=='left' ? 3 : 1)
            polygon=f.map { |j| points[j] }; mx=polygon.inject(0.0) { |s,p| s+p[0] }/4; mz=polygon.inject(0.0) { |s,p| s+p[2] }/4
            xmin=handle=='left' ? left+(sw-13)/2 : left+w-(sw+13)/2
            xmax=xmin+13; zmin=bottom+h/2-45; zmax=zmin+90
            q=points.length; polygon.each { |p| points<<[p[0]>mx ? xmax : xmin,y,p[2]>mz ? zmax : zmin] }
            r=points.length; 4.times { |j| points<<[points[q+j][0],y+3,points[q+j][2]] }
            4.times { |j| faces<<[f[j],f[(j+1)%4],q+(j+1)%4,q+j]; roles<<'frame' }
            4.times { |j| faces<<[q+j,q+(j+1)%4,r+(j+1)%4,r+j]; roles<<'hardware' }
            faces<<[r,r+1,r+2,r+3]; roles<<'hardware'
            handle_bounds={'min'=>[xmin,y,zmin],'max'=>[xmax,y+3,zmax]}
          else
            faces<<f; roles<<(brown.include?(i) ? 'seal' : 'frame')
          end
        end
      end
      mesh={'section'=>section,'points'=>points,'faces'=>faces,'roles'=>roles,'handle_bounds'=>handle_bounds}
      orient(mesh); mesh
    end
    def self.pane(mesh,x,y,z,w,d,h)
      box={'points'=>[[x,y,z],[x+w,y,z],[x+w,y+d,z],[x,y+d,z],[x,y,z+h],[x+w,y,z+h],[x+w,y+d,z+h],[x,y+d,z+h]],
           'faces'=>[[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]}
      orient(box); offset=mesh['points'].length
      mesh['points'].concat(box['points']); mesh['faces'].concat(box['faces'].map { |f| f.map { |i| i+offset } }); mesh['roles'].concat(Array.new(6,'glass'))
    end
    def self.volume(mesh)
      reference=mesh['points'].first; sum=0.0
      mesh['faces'].each do |f|
        a=mesh['points'][f.first].zip(reference).map { |x,r| x-r }
        f.drop(1).each_cons(2) do |j,k|
          b=mesh['points'][j].zip(reference).map { |x,r| x-r }; c=mesh['points'][k].zip(reference).map { |x,r| x-r }
          sum+=(a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6
        end
      end
      sum
    end
    def self.orient(mesh); mesh['faces'].map!(&:reverse) if volume(mesh)<0; end
    def self.validate_mesh(mesh)
      points,faces=mesh.values_at('points','faces')
      raise ArgumentError,'Recipe geometry budget exceeded' if points.length>256 || faces.length>256 || faces.inject(0) { |s,f| s+f.length }>2048
      edges=Hash.new { |hash,key| hash[key]=[] }
      faces.each do |face|
        raise ArgumentError,'Recipe has invalid face indices' unless face.uniq.length==face.length && face.all? { |i| i.is_a?(Integer) && i.between?(0,points.length-1) }
        face.each_index { |i| a,b=face[i],face[(i+1)%face.length]; edges[[a,b].sort]<<[a,b] }
      end
      raise ArgumentError,'Recipe mesh is not consistently closed' unless edges.values.all? { |e| e.length==2 && e[0]==e[1].reverse } && volume(mesh)>0.001
      raise ArgumentError,'Recipe role count mismatch' if mesh['roles'] && mesh['roles'].length!=faces.length
      true
    end
  end
end
