// Heightfield calculations stay in Probe; RBZ only inserts a bounded open mesh.
// Coordinates of samples/bumps are local to origin_mm, all in mm.
function build(ctx) {
  var p=ctx.params, cols=p.columns, rows=p.rows, count=(cols+1)*(rows+1);
  function fail(s){throw new Error('PROBE_INPUT_INVALID:params\t'+s);}
  if(cols*rows>128) fail('At most128 cells /256 triangles.');
  if(p.heights_mm.length && p.heights_mm.length!==count) fail('heights_mm must have (columns+1)*(rows+1) values in Y-row/X-column order.');
  if(p.heights_mm.length && p.samples_mm.length) fail('Choose heights or samples, not both.');
  for(var a=0;a<p.samples_mm.length;a++) for(var b=a+1;b<p.samples_mm.length;b++) {
    var sa=p.samples_mm[a],sb=p.samples_mm[b];
    if(sa[0]===sb[0] && sa[1]===sb[1]) fail('Duplicate sample XY; provide one elevation per point.');
  }
  var points=[],triangles=[];
  for(var y=0;y<=rows;y++) for(var x=0;x<=cols;x++) {
    var px=x*p.width_mm/cols,py=y*p.depth_mm/rows,z=p.heights_mm.length ? p.heights_mm[y*(cols+1)+x] : 0;
    if(p.samples_mm.length) {
      var sum=0,weights=0,exact=false;
      for(var i=0;i<p.samples_mm.length;i++) {
        var sample=p.samples_mm[i],dx=px-sample[0],dy=py-sample[1],d2=dx*dx+dy*dy;
        if(d2<1e-12){z=sample[2];exact=true;break;}
        var weight=1/d2;sum+=weight*sample[2];weights+=weight;
      }
      if(!exact) z=sum/weights;
    }
    for(var j=0;j<p.bumps.length;j++) {
      var bump=p.bumps[j],bx=px-bump.center_mm[0],by=py-bump.center_mm[1];
      var r=Math.sqrt(bx*bx+by*by)/bump.radius_mm;
      if(r<1) z+=bump.height_mm*(1-3*r*r+2*r*r*r); // C1 smooth falloff.
    }
    points.push([px+p.origin_mm[0],py+p.origin_mm[1],z+p.origin_mm[2]]);
  }
  for(var row=0;row<rows;row++) for(var col=0;col<cols;col++) {
    var v=row*(cols+1)+col,w=v+cols+1;
    triangles.push([v,v+1,w+1],[v,w+1,w]); // consistently upward winding.
  }
  var options={points_mm:points,triangles:triangles,smooth:p.smooth};
  if(p.material) options.material=p.material;
  return {format_version:'sketchup-operations/1',units:'mm',steps:[{method:'draw_geometry',arguments:{kind:'surface_mesh',name:p.name,grouping:p.grouping,options:options}}]};
}
