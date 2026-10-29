function build(ctx) {
  var p=ctx.params, input=ctx.inputs.face, s=input && input.target;
  function fail(message){throw new Error('PROBE_INPUT_INVALID:params\t'+message);}
  if(!s || s.type!=='Face' || !s.frame || !s.sides) fail('Bind a face-texture/1 snapshot to face.');
  var front=p.side==='front', side=s.sides[p.side], f=s.frame;
  var args={instance_path:s.instance_path,front:front};
  if(p.mode==='clear') {
    args.action='clear';
    return {format_version:'sketchup-operations/1',units:'mm',steps:[{method:'face_texture',arguments:args}]};
  }
  var material=p.material || side.material;
  if(!material) fail('Choose an existing textured material.');
  if(p.mode==='transform' && (!side.uv || !side.texture)) fail('Relative editing needs a directly assigned texture on this face side.');
  var uv=p.mode==='transform' ? side.uv : [[0,0],[1,0],[1,1],[0,1]];
  var width=p.mode==='tile' ? p.tile_size_mm[0] : f.width_mm;
  var height=p.mode==='tile' ? p.tile_size_mm[1] : f.height_mm;
  if(p.mode==='tile' && (width<=0 || height<=0)) fail('Tile width/height must be positive.');
  var xy=[[0,0],[width,0],[width,height],[0,height]];
  var pivot=[f.width_mm*p.pivot_fraction[0],f.height_mm*p.pivot_fraction[1]];
  var angle=p.rotation_degrees*Math.PI/180, c=Math.cos(angle),sn=Math.sin(angle);
  var shear=Math.tan(p.shear_degrees*Math.PI/180);
  var sx=p.scale[0]*(p.flip_u?-1:1),sy=p.scale[1]*(p.flip_v?-1:1);
  var transformed=xy.map(function(q,i){
    var x=(q[0]-pivot[0])*sx,y=(q[1]-pivot[1])*sy;
    x+=shear*y;
    var rx=c*x-sn*y,ry=sn*x+c*y;
    var denominator=1+p.tilt[0]*rx/f.width_mm+p.tilt[1]*ry/f.height_mm;
    if(denominator<=0.001) fail('Tilt crosses the perspective horizon; reduce tilt or scale.');
    return [rx/denominator+pivot[0]+p.offset_mm[0]+p.corner_offsets_mm[i][0],
            ry/denominator+pivot[1]+p.offset_mm[1]+p.corner_offsets_mm[i][1]];
  });
  // Reject folded/self-intersecting or nearly collapsed four-pin mappings.
  var sign=0;
  transformed.forEach(function(a,i){
    var b=transformed[(i+1)%4],d=transformed[(i+2)%4];
    var cross=(b[0]-a[0])*(d[1]-b[1])-(b[1]-a[1])*(d[0]-b[0]);
    if(Math.abs(cross)<1e-6 || sign && cross*sign<=0) fail('Four pins must form a nondegenerate convex quadrilateral.');
    sign=cross;
  });
  args.material=material;
  args.mapping=transformed.map(function(q,i){
    var point=f.origin_mm.map(function(n,j){return n+f.u[j]*q[0]+f.v[j]*q[1];});
    if(point.some(function(n){return !isFinite(n) || Math.abs(n)>1e9;}) || uv[i].some(function(n){return !isFinite(n) || Math.abs(n)>1e6;})) fail('Mapping exceeds coordinate budget.');
    return {point_mm:point,uv:uv[i]};
  });
  return {format_version:'sketchup-operations/1',units:'mm',steps:[{method:'face_texture',arguments:args}]};
}
