// Pure Probe script. Root context if annotations are enabled; XY model axes.
function build(ctx) {
  var p=ctx.params, w=p.width_mm, h=p.height_mm;
  var steps=[{method:"draw_geometry",arguments:{kind:"rectangle",grouping:"none",options:{origin_mm:[0,0,0],plane:"XY",size_mm:[w,h]}}}];
  if(p.annotate) {
    steps.push({method:"annotation",arguments:{kind:"linear_dimension",options:{start_mm:[0,0,0],end_mm:[w,0,0],offset_mm:[0,-150,0]}}});
    steps.push({method:"annotation",arguments:{kind:"linear_dimension",options:{start_mm:[0,0,0],end_mm:[0,h,0],offset_mm:[-150,0,0]}}});
    steps.push({method:"annotation",arguments:{kind:"text",options:{text:w+" x "+h+" mm",point_mm:[w/2,h+150,0]}}});
  }
  return {format_version:"sketchup-operations/1",units:"mm",steps:steps};
}
