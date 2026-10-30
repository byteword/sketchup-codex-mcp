function build(ctx){
 var p=ctx.params,site=p.site_mm,r2=p.radius_mm*p.radius_mm;
 function d(p,a,b){var x=b[0]-a[0],y=b[1]-a[1],t=((p[0]-a[0])*x+(p[1]-a[1])*y)/(x*x+y*y);t=Math.max(0,Math.min(1,t));return Math.pow(p[0]-a[0]-t*x,2)+Math.pow(p[1]-a[1]-t*y,2);}
 function inside(p,ring){var c=false;for(var i=0,j=ring.length-1;i<ring.length;j=i++){var a=ring[i],b=ring[j];if((a[1]>p[1])!==(b[1]>p[1]) && p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0])c=!c;}return c;}
 function cross(a,b,c){return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);}
 function distance(a,b){if(inside(a[0],b)||inside(b[0],a))return 0;var v=Infinity;for(var i=0;i<a.length;i++)for(var j=0;j<b.length;j++){var u=a[i],w=a[(i+1)%a.length],x=b[j],y=b[(j+1)%b.length];if(cross(u,w,x)*cross(u,w,y)<0&&cross(x,y,u)*cross(x,y,w)<0)return 0;v=Math.min(v,d(u,x,y),d(w,x,y),d(x,u,w),d(y,u,w));}return v;}
 var selected=[],faces=0;ctx.inputs.source.entities.forEach(function(e){if(e.type!=='Face')return;faces++;var loop=e.loops[0];var dist=distance(loop,site);if(dist<=r2)selected.push({path:e.instance_path,loops:e.loops,distance_mm:Math.sqrt(dist)});});
 return {format_version:'probe-report/1',summary:'SITE boundary radius footprint scan',metrics:{faces_examined:faces,footprints:selected},findings:[]};
}
