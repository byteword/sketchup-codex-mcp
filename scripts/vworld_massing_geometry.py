"""Pure geometry for VWorld massing. Model coordinates are mm, +X east/+Y north."""
import math

def cross(a,b,c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])

def signed_area(p):
    return sum(p[i][0]*p[(i+1)%len(p)][1]-p[(i+1)%len(p)][0]*p[i][1] for i in range(len(p)))/2

def clean_ring(points):
    out=[]
    for p in points:
        q=list(p[:2])
        if not out or math.dist(out[-1],q)>.001:out.append(q)
    if len(out)>1 and math.dist(out[0],out[-1])<.001:out.pop()
    changed=True
    while changed and len(out)>3:
        changed=False
        for i in range(len(out)):
            a,b,c=out[i-1],out[i],out[(i+1)%len(out)]
            if abs(cross(a,b,c))<.001:
                out.pop(i);changed=True;break
    if len(out)<3 or abs(signed_area(out))<1:raise ValueError('Degenerate footprint')
    if signed_area(out)<0:out.reverse()
    return out

def triangles(points):
    p=clean_ring(points);indices=list(range(len(p)));out=[]
    while len(indices)>3:
        for k,b in enumerate(indices):
            a,c=indices[k-1],indices[(k+1)%len(indices)]
            if cross(p[a],p[b],p[c])<=.001:continue
            if any(cross(p[a],p[b],p[t])>=-.001 and cross(p[b],p[c],p[t])>=-.001 and cross(p[c],p[a],p[t])>=-.001 for t in indices if t not in (a,b,c)):continue
            out.append([p[a],p[b],p[c]]);indices.pop(k);break
        else:raise ValueError('Self-intersecting or invalid footprint')
    out.append([p[i] for i in indices]);return out

def triangle_intersection_area(subject,clip):
    out=subject[:]
    for a,b in zip(clip,clip[1:]+clip[:1]):
        before=out;out=[]
        if not before:break
        for p,q in zip(before,before[1:]+before[:1]):
            dp,dq=cross(a,b,p),cross(a,b,q)
            ip,iq=dp>=-1e-6,dq>=-1e-6
            if ip:out.append(p)
            if ip!=iq:
                t=dp/(dp-dq);out.append([p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])])
    return abs(signed_area(out)) if len(out)>2 else 0

def bounds(p):
    return [min(q[0] for q in p),min(q[1] for q in p),max(q[0] for q in p),max(q[1] for q in p)]

def box_overlap(a,b):
    return a[0]<b[2] and b[0]<a[2] and a[1]<b[3] and b[1]<a[3]

def align_site(model,geo):
    """Fit translation only to the four cardinal extrema, preserving north and scale."""
    if len(model)!=4:raise ValueError('This workflow requires a four-corner SITE boundary')
    selectors=[lambda p:p[1],lambda p:-p[0],lambda p:-p[1],lambda p:p[0]]
    mc=[max(model,key=f) for f in selectors];gc=[max(geo,key=f) for f in selectors]
    if len({tuple(p[:2]) for p in mc})!=4 or len({tuple(p[:2]) for p in gc})!=4:raise ValueError('Ambiguous SITE extrema')
    lon0=sum(p[0] for p in gc)/4;lat0=sum(p[1] for p in gc)/4;lat=math.radians(lat0)
    a=6378137;e2=6.69437999014e-3;n=a/math.sqrt(1-e2*math.sin(lat)**2);m=a*(1-e2)/(1-e2*math.sin(lat)**2)**1.5
    sx=math.pi/180*n*math.cos(lat)*1000;sy=math.pi/180*m*1000
    local=[[(p[0]-lon0)*sx,(p[1]-lat0)*sy] for p in gc]
    origin=[sum(mc[i][j]-local[i][j] for i in range(4))/4 for j in range(2)]
    residual=[math.dist(mc[i][:2],[origin[j]+local[i][j] for j in range(2)]) for i in range(4)]
    rms=math.sqrt(sum(x*x for x in residual)/4)
    if max(residual)>500:raise ValueError('SITE correspondence exceeds 500 mm; provide corrected anchors')
    return dict(lon0=lon0,lat0=lat0,mm_per_lon_degree=sx,mm_per_lat_degree=sy,origin_mm=origin,corner_residual_mm=residual,rms_mm=rms)

def to_model(p,a):
    return [a['origin_mm'][0]+(p[0]-a['lon0'])*a['mm_per_lon_degree'],a['origin_mm'][1]+(p[1]-a['lat0'])*a['mm_per_lat_degree']]

def match_footprints(footprints,features,alignment):
    candidates=[]
    for feature in features:
        g=feature['geometry'];polys=g['coordinates'] if g['type']=='MultiPolygon' else [g['coordinates']]
        rings=[(1 if i==0 else -1,[to_model(p,alignment) for p in ring]) for poly in polys for i,ring in enumerate(poly)]
        try:
            area=sum(sign*abs(signed_area(r)) for sign,r in rings)
            ts=[(sign,t) for sign,r in rings for t in triangles(r)]
            candidates.append(dict(feature=feature,area=area,triangles=ts,bounds=bounds([p for _,r in rings for p in r])))
        except ValueError:continue
    matches=[];skipped=[]
    for f in footprints:
        if len(f['loops'])!=1:
            skipped.append(dict(path=f['path'],reason='footprint_has_holes'));continue
        ring=f['loops'][0];area=abs(signed_area(ring));ts=triangles(ring);box=bounds(ring);scores=[]
        for c in candidates:
            if not box_overlap(box,c['bounds']):continue
            overlap=max(0,sum(sign*triangle_intersection_area(t,u) for t in ts for sign,u in c['triangles']))
            if overlap<1:continue
            coverage=overlap/area;iou=overlap/(area+c['area']-overlap)
            scores.append(dict(coverage=coverage,iou=iou,feature=c['feature']))
        scores.sort(key=lambda s:s['iou'],reverse=True)
        best=scores[0] if scores else None
        reason=None
        if not best or best['coverage']<.45 or best['iou']<.25:reason='no_confident_match'
        elif len(scores)>1 and scores[1]['iou']>best['iou']*.65:reason='ambiguous_match'
        elif best['feature']['properties'].get('height_m') is None:reason='height_unavailable'
        if reason:
            skipped.append(dict(path=f['path'],reason=reason,candidate_pnu=best['feature']['properties']['pnu'] if best else None,coverage=best['coverage'] if best else 0));continue
        props=best['feature']['properties']
        matches.append(dict(path=f['path'],ring_mm=ring,height_m=props['height_m'],height_mm=props['height_mm'],pnu=props['pnu'],building_id=props['building_id'],updated_at=props['source_updated_at'],coverage=best['coverage'],iou=best['iou'],distance_mm=f['distance_mm']))
    # Multiple source footprints matched to one building are not silently assigned one shared height.
    duplicate={m['building_id'] for m in matches if sum(x['building_id']==m['building_id'] for x in matches)>1}
    for m in matches[:]:
        if m['building_id'] in duplicate:matches.remove(m);skipped.append(dict(path=m['path'],reason='duplicate_building_match',candidate_pnu=m['pnu']))
    return matches,skipped
