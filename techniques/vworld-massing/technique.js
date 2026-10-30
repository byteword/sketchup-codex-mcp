function build(ctx) {
 function fail(message){throw new Error('PROBE_INPUT_INVALID:params\t'+message);}
 var p=ctx.params,lookup={},seen={};
 Object.keys(ctx.inputs).forEach(function(k){ctx.inputs[k].entities.forEach(function(e){if(e.type==='Face')lookup[e.instance_path.join('/')]=e;});});
 var nodes=[{kind:'group',id:'assembly',name:p.name}],assertions=[];
 p.buildings.forEach(function(b,i){
  var key=b.path.join('/'),f=lookup[key];if(seen[key])fail('Duplicate footprint');seen[key]=true;
  if(!f || f.loops.length!==1)fail('Missing footprint or holes require manual review');
  var ring=f.loops[0].map(function(v){return v.slice();}),n=ring.length;
  if(n!==b.expected_ring_mm.length)fail('Source geometry changed; query and match again');
  for(var j=0;j<n;j++)for(var k=0;k<3;k++)if(Math.abs(ring[j][k]-b.expected_ring_mm[j][k])>0.1)fail('Source geometry moved; query and match again');
  if(n<3||n>64)fail('Footprint vertex limit');
  var z=ring[0][2];if(ring.some(function(v){return Math.abs(v[2]-z)>0.1;}))fail('Footprint is not horizontal');
  var area=0;for(var j=0;j<n;j++)area+=ring[j][0]*ring[(j+1)%n][1]-ring[(j+1)%n][0]*ring[j][1];
  if(Math.abs(area)<1)fail('Degenerate footprint');if(area<0)ring.reverse();
  var pts=ring.concat(ring.map(function(v){return [v[0],v[1],v[2]+b.height_mm];})),bottom=[],top=[],faces=[];
  for(var j=0;j<n;j++){bottom.unshift(j);top.push(j+n);}faces.push(bottom,top);
  for(var j=0;j<n;j++)faces.push([j,(j+1)%n,(j+1)%n+n,j+n]);
  var id='building_'+i;nodes.push({kind:'mesh',id:id,parent:'assembly',name:b.pnu+' | '+(b.height_mm/1000)+'m | '+b.path[b.path.length-1],points_mm:pts,faces:faces,face_roles:faces.map(function(){return 'mass';}),solid:true,cleanup:'none'});
  assertions.push({kind:'solid',node:id});
  assertions.push({kind:'bounds',node:id,min_mm:[Math.min.apply(null,ring.map(function(v){return v[0];})),Math.min.apply(null,ring.map(function(v){return v[1];})),z],max_mm:[Math.max.apply(null,ring.map(function(v){return v[0];})),Math.max.apply(null,ring.map(function(v){return v[1];})),z+b.height_mm],tolerance_mm:0.01});
 });
 return {format_version:'sketchup-plan/1',units:'mm',root:'assembly',nodes:nodes,assertions:assertions};
}
