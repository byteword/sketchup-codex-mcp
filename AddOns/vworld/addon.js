// Official VWorld references: NED apiNum=76 (buildings), apiNum=92 (parcels).
// Pure source; credentials and HTTPS are handled by Probe.
function text(v){return v===undefined || v===null?null:String(v).slice(0,256);}
function blank(v){return v===undefined || v===null || v==='';}
function pair(v) {
    var a=Array.isArray(v)?v:String(v || '').split(',').map(function(s){return s.trim()===''?NaN:Number(s);});
    if(a.length!==2 || a.some(function(n){return typeof n!=='number' || !isFinite(n);}) || Math.abs(a[0])>180 || Math.abs(a[1])>90)
        throw new Error('경도,위도 두 숫자를 입력하세요.');
    return a;
}
function bounds(v) {
    var a=Array.isArray(v)?v:String(v || '').split(',').map(function(s){return s.trim()===''?NaN:Number(s);});
    if(a.length!==4 || a.some(function(n){return typeof n!=='number' || !isFinite(n);}) ||
       a[0]<-180 || a[2]>180 || a[1]<-90 || a[3]>90 || a[0]>=a[2] || a[1]>=a[3] ||
       a[2]-a[0]>0.020000001 || a[3]-a[1]>0.020000001)throw new Error('범위는 서쪽경도,남쪽위도,동쪽경도,북쪽위도 순서이며 각 방향 최대 0.02도입니다.');
    return a;
}
function prepare(input) {
    var op=input.operation || 'buildings';
    var allowed=op==='address'?['operation','address','address_type']:['operation','pnu','bbox','point','limit'];
    if(['buildings','parcels','address'].indexOf(op)<0)throw new Error('지형 높이는 지형 높이 · 지점/격자 조회 버튼을 이용하세요.');
    Object.keys(input).forEach(function(k){if(allowed.indexOf(k)<0)throw new Error('Unknown input: '+k);});
    if(op==='address') {
        var address=String(input.address || '').trim(),type=String(input.address_type || 'road').toLowerCase();
        if(!address || address.length>200 || ['road','parcel'].indexOf(type)<0)throw new Error('주소와 주소 유형 road / parcel을 확인하세요.');
        return {endpoint:'address',operation:op,query:{service:'address',request:'getCoord',version:'2.0',
            crs:'EPSG:4326',format:'json',type:type,address:address,refine:'true',simple:'false'}};
    }
    if(input.pnu!==undefined && typeof input.pnu!=='string')throw new Error('PNU must be a string');
    var pnu=(input.pnu || '').trim(),b=null,limit=Number(input.limit===undefined?20:input.limit);
    if(!Number.isInteger(limit) || limit<1 || limit>100)throw new Error('limit must be 1..100');
    if((pnu?1:0)+(!blank(input.bbox)?1:0)+(!blank(input.point)?1:0)!==1)throw new Error('PNU, 범위, 중심점 중 하나만 입력하세요.');
    var q={typename:op==='buildings'?'dt_d010':'dt_d002',maxFeatures:String(limit),
        resultType:'results',srsName:'EPSG:4326',output:'application/json'};
    if(pnu) {
        if(!/^\d{19}$/.test(pnu))throw new Error('PNU must be exactly 19 digits');q.pnu=pnu;
    }else {
        if(!blank(input.point)) {var c=pair(input.point);b=bounds([c[0]-0.0001,c[1]-0.0001,c[0]+0.0001,c[1]+0.0001]);}
        else b=bounds(input.bbox);
        // The official endpoint specifies latitude-first BBOX for EPSG:4326.
        q.bbox=[b[1],b[0],b[3],b[2],'EPSG:4326'].join(',');
    }
    return {endpoint:op,operation:op,query:q,limit:limit,pnu:pnu,bbox:b};
}
function geometry(g,budget) {
    if(!g)return null;
    if(g.type!=='Polygon' && g.type!=='MultiPolygon')throw new Error('지원하지 않는 경계 형식');
    var polygons=g.type==='Polygon'?[g.coordinates]:g.coordinates;
    if(!Array.isArray(polygons) || polygons.length===0 || polygons.length>256)throw new Error('잘못된 경계');
    var normalized=polygons.map(function(poly) {
        if(!Array.isArray(poly) || !poly.length || poly.length>256)throw new Error('잘못된 경계 링');
        return poly.map(function(ring) {
            if(!Array.isArray(ring) || ring.length<4 || ring.length>5000)throw new Error('경계 점 개수를 확인하세요.');
            budget.points+=ring.length;if(budget.points>8000)throw new Error('경계가 너무 큽니다. 조회 범위를 줄이세요.');
            var r=ring.map(function(p){if(!Array.isArray(p) || p.length<2)throw new Error('잘못된 경계 좌표');return pair(p.slice(0,2));});
            if(r[0][0]!==r[r.length-1][0] || r[0][1]!==r[r.length-1][1])throw new Error('닫히지 않은 경계');return r;
        });
    });
    return {type:g.type,coordinates:g.type==='Polygon'?normalized[0]:normalized};
}
function parse(input) {
    var body,req=input.request,op=req.operation || 'buildings';
    try{body=JSON.parse(input.body);}catch(e){return {status:'error',message:'JSON 대신 XML/HTML 응답입니다. 키·등록 URL·API 권한을 확인하세요.'};}
    if(op==='address') {
        var r=body && body.response;
        if(!r || r.status!=='OK' || !r.result || !r.result.point)
            return {status:'error',message:r && r.status==='NOT_FOUND'?'주소를 찾지 못했습니다. 도로명/지번 유형을 확인하세요.':'주소 조회 실패. 키·등록 URL·서비스 상태를 확인하세요.'};
        var coords=[r.result.point.x,r.result.point.y];
        if(coords.some(function(v){return (typeof v!=='string' && typeof v!=='number') || String(v).trim()==='';}))
            return {status:'error',message:'주소 응답에 유효한 좌표가 없습니다.'};
        var pt=pair(coords.map(Number));
        return {status:'ok',source:'국토교통부 VWorld 지오코딩',coordinate_order:'longitude,latitude',point:pt,
            followup:{operation:'parcels',inputs:{point:pt.join(',')}},
            suggested_bbox:[pt[0]-0.001,pt[1]-0.001,pt[0]+0.001,pt[1]+0.001],
            note:'주소 대표 좌표입니다. 지적도 중심점 또는 작은 범위 조회 후 대상 필지를 확인하세요.',
            geojson:{type:'FeatureCollection',features:[{type:'Feature',geometry:{type:'Point',coordinates:pt},properties:{label:req.query.address}}]}};
    }
    if(!body || body.type!=='FeatureCollection' || !Array.isArray(body.features))
        return {status:'error',message:'VWorld 목록 응답이 아닙니다. 인증키·할당량·서비스 상태를 확인하세요.'};
    if(body.features.length>req.limit)throw new Error('Unexpected response count');
    var budget={points:0},features=[],missing=0;
    var rows=body.features.map(function(f) {
        if(!f || f.type && f.type!=='Feature')throw new Error('잘못된 피처');
        var p=f.properties || {},row;
        if(req.pnu && String(p.pnu)!==req.pnu)throw new Error('Response PNU does not match request');
        if(op==='buildings') {
            var raw=p.hg,n=null,state='missing';
            if(raw!==undefined && raw!==null && String(raw).trim()!=='') {
                n=typeof raw==='string' || typeof raw==='number'?Number(raw):NaN;
                if(!isFinite(n) || !isFinite(n*1000) || n<0){n=null;state='invalid';}
                else if(n===0){n=null;state='zero_unavailable';}else state='available';
            }
            row={feature_id:text(f.id),building_id:text(p.gis_idntfc_no),pnu:text(p.pnu),height_m:n,height_mm:n===null?null:n*1000,
                height_status:state,source_height_raw:text(raw),source_height_field:'hg',source_updated_at:text(p.last_updt_dt)};
        }else {
            row={feature_id:text(f.id),pnu:text(p.pnu),parcel_label:text(p.lnm_lndcgr_smbol),main_number:text(p.mnnm),sub_number:text(p.slno),
                source_updated_at:text(p.last_updt_dt),source_id:text(p.src_objectid)};
        }
        var geom=geometry(f.geometry,budget);
        if(geom) {
            var properties=Object.assign({},row);
            properties.label=op==='buildings'?(row.height_m===null?'높이 미제공':row.height_m+' m'):(row.parcel_label || row.pnu || '필지');
            features.push({type:'Feature',id:text(f.id),geometry:geom,properties:properties});
        }else missing++;
        return row;
    });
    var limited=rows.length>=req.limit;
    var result={status:'ok',operation:op,source:'국토교통부 VWorld / '+(op==='buildings'?'GIS건물통합정보':'연속지적도'),
        reference:'https://www.vworld.kr/dtna/dtna_apiSvcFc_s001.do?apiNum='+(op==='buildings'?'76':'92'),
        count:rows.length,possibly_truncated:limited,missing_geometry_count:missing,coordinate_order:'longitude,latitude',
        geojson:{type:'FeatureCollection',features:features},
        note:(limited?'조회 한도에 도달했습니다. 범위를 줄이세요. ':'')+(op==='buildings'?
            'hg는 건물 자체 높이이며 지형 표고가 아닙니다. 0·누락은 추정하지 않습니다.':
            '연속지적도는 참고용 경계입니다. 중심점 조회는 주변 후보 필지도 포함합니다.')};
    result[op==='buildings'?'buildings':'parcels']=rows;return result;
}
