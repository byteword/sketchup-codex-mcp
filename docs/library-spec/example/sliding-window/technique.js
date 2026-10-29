// Parametric sliding window. Geometry stays local in model-axis mm.
// Actual SDK operations, existing materials, Undo and cleanup are host responsibilities.
function validate(ctx) {
  var p=ctx.params, sw=p.sash_width_mm, fw=p.frame_width_mm;
  var overlap=p.overlap_mm===undefined?sw+5:p.overlap_mm;
  var issues=[];
  function bad(path,message){issues.push({path:path,code:'input_invalid',message:message});}
  if(p.open_sash==='none'&&p.open_fraction>0)bad('/open_sash','Choose a sash for a nonzero opening');
  if(overlap<sw||overlap>2*sw-4)bad('/overlap_mm','Overlap must fit the meeting stiles');
  var r=fw+5, leafW=(p.width_mm-2*r+overlap)/2, leafH=p.height_mm-2*r;
  if(leafW-2*sw-1<100||leafH-2*sw-1<100)bad('/width_mm','Insufficient glass or handle clearance');
  if(.24*p.depth_mm-p.glass_thickness_mm<12)bad('/depth_mm','Depth is too small for requested glass');
  return issues;
}
function build(ctx) {
  var p=ctx.params,w=p.width_mm,h=p.height_mm,d=p.depth_mm,fw=p.frame_width_mm,sw=p.sash_width_mm;
  var glass=p.glass_thickness_mm,overlap=p.overlap_mm===undefined?sw+5:p.overlap_mm;
  var r=fw+5,leafW=(w-2*r+overlap)/2,leafH=h-2*r,thick=.24*d;
  var pf=(thick-glass)/2,pb=(thick+glass)/2,travel=w-2*r-leafW;
  function volume(mesh){
    var ref=mesh.points_mm[0],v=0;
    function sub(a,b){return a.map(function(x,i){return x-b[i];});}
    mesh.faces.forEach(function(f){
      var a=sub(mesh.points_mm[f[0]],ref);
      for(var i=1;i<f.length-1;i++){
        var b=sub(mesh.points_mm[f[i]],ref),c=sub(mesh.points_mm[f[i+1]],ref);
        v+=(a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6;
      }
    });return v;
  }
  function orient(mesh){if(volume(mesh)<0)mesh.faces=mesh.faces.map(function(f){return f.slice().reverse();});}
  function ring(id,left,bottom,width,height,y,profile,seals,handle){
    var mesh={kind:'mesh',id:id,name:id==='fixed'?'본틀_복열레일':id==='left'?'좌창짝_외측매립손잡이':'우창짝_외측매립손잡이',
      parent:'window',points_mm:[],faces:[],face_roles:[],solid:true,cleanup:'material_safe'};
    profile.forEach(function(pr){
      var z=pr[1],depth=pr[0];
      mesh.points_mm.push([left+z,y+depth,bottom+z],[left+width-z,y+depth,bottom+z],
        [left+width-z,y+depth,bottom+height-z],[left+z,y+depth,bottom+height-z]);
    });
    function face(f,role){mesh.faces.push(f);mesh.face_roles.push(role);}
    for(var i=0;i<profile.length;i++)for(var k=0;k<4;k++){
      var f=[i*4+k,i*4+(k+1)%4,((i+1)%profile.length)*4+(k+1)%4,((i+1)%profile.length)*4+k];
      if(handle&&i===profile.length-1&&k===(handle==='left'?3:1)){
        var polygon=f.map(function(index){return mesh.points_mm[index];});
        var mx=polygon.reduce(function(s,p){return s+p[0];},0)/4,mz=polygon.reduce(function(s,p){return s+p[2];},0)/4;
        var xmin=handle==='left'?left+(sw-13)/2:left+width-(sw+13)/2;
        var xmax=xmin+13,zmin=bottom+height/2-45,zmax=zmin+90,q=mesh.points_mm.length;
        polygon.forEach(function(p){mesh.points_mm.push([p[0]>mx?xmax:xmin,y,p[2]>mz?zmax:zmin]);});
        var inner=mesh.points_mm.length;
        for(var j=0;j<4;j++)mesh.points_mm.push([mesh.points_mm[q+j][0],y+3,mesh.points_mm[q+j][2]]);
        for(j=0;j<4;j++)face([f[j],f[(j+1)%4],q+(j+1)%4,q+j],'frame');
        for(j=0;j<4;j++)face([q+j,q+(j+1)%4,inner+(j+1)%4,inner+j],'hardware');
        face([inner,inner+1,inner+2,inner+3],'hardware');
      }else face(f,seals.indexOf(i)>=0?'seal':'frame');
    }
    orient(mesh);return mesh;
  }
  function pane(mesh,x,y,z,width,depth,height){
    var box={points_mm:[[x,y,z],[x+width,y,z],[x+width,y+depth,z],[x,y+depth,z],
      [x,y,z+height],[x+width,y,z+height],[x+width,y+depth,z+height],[x,y+depth,z+height]],
      faces:[[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]};
    orient(box);var start=mesh.points_mm.length;
    mesh.points_mm=mesh.points_mm.concat(box.points_mm);
    box.faces.forEach(function(f){mesh.faces.push(f.map(function(index){return index+start;}));mesh.face_roles.push('glass');});
  }
  var outer=[[0,0],[d,0],[d,fw],[.88*d,fw],[.88*d,fw-2],[.70*d,fw-2],[.70*d,r],[.66*d,r],
    [.66*d,fw-2],[.34*d,fw-2],[.34*d,r],[.30*d,r],[.30*d,fw-2],[.12*d,fw-2],[.12*d,fw],[0,fw]];
  var profile=[[0,0],[thick,0],[thick,sw],[pb+3,sw],[pb+3,sw+2],[pb+1,sw+2],[pb+1,sw+4],[pb+.2,sw+4],
    [pb+.2,sw],[pf-.2,sw],[pf-.2,sw+4],[pf-1,sw+4],[pf-1,sw+2],[pf-3,sw+2],[pf-3,sw],[0,sw]];
  var nodes=[{kind:'group',id:'window',name:'두 짝 미닫이창'},ring('fixed',0,0,w,h,0,outer,[],null)];
  [['left',r+(p.open_sash==='left'?travel*p.open_fraction:0),.20*d],
   ['right',w-r-leafW-(p.open_sash==='right'?travel*p.open_fraction:0),.56*d]].forEach(function(item){
    var mesh=ring(item[0],item[1],r,leafW,leafH,item[2],profile,[5,6,7,9,10,11],item[0]);
    pane(mesh,item[1]+sw+.5,item[2]+pf,r+sw+.5,leafW-2*sw-1,glass,leafH-2*sw-1);nodes.push(mesh);
  });
  return {format_version:'sketchup-plan/1',units:'mm',root:'window',nodes:nodes,
    assertions:[{kind:'bounds',node:'window',min_mm:[0,0,0],max_mm:[w,d,h],tolerance_mm:.001},
      {kind:'solid',node:'fixed'},{kind:'solid',node:'left'},{kind:'solid',node:'right'}]};
}
