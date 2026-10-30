"""Query -> align -> match -> pinned Probe technique -> one new root group.

Default is plan-only. --apply explicitly creates a NEW group; never overwrites the source.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid
from datetime import datetime
sys.path.insert(0,str(Path(__file__).resolve().parent))
from vworld_massing_geometry import align_site, bounds, match_footprints

ROOT=Path(__file__).resolve().parent.parent

def load(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def write(path,value):Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf8')
def request():return str(uuid.uuid4())

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['config','probe-root','query-helper','mcp']:ap.add_argument('--'+key,required=True)
    ap.add_argument('--apply',action='store_true');ap.add_argument('--name');args=ap.parse_args()
    config=load(args.config);radius=float(config['radius_m'])*1000
    if not 1000<=radius<=200000:raise ValueError('Radius must be 1..200 m')
    output=ROOT/'dist'/('vworld-run-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]);output.mkdir(parents=True)
    print('Report folder:',output,flush=True)
    # Reuse the repository's bounded production STDIO client; no native test suite runs here.
    spec=importlib.util.spec_from_file_location('probe_client',ROOT/'skills/sketchup-self-test/scripts/run_native_tests.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    client=module.Client([args.mcp],60)
    jobs=[]
    def tool(name,**kwargs):return client.tool('sketchup_'+name,kwargs)
    def wait(start):
        jid=start['data']['job_id'];jobs.append(jid);write(output/'jobs.json',jobs)
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            result=tool('library_job',action='get',job_id=jid,wait_ms=1000)['data']
            if result['state']=='succeeded':return result['result']
            if result['state'] in ('failed','canceled','outcome_unknown'):raise RuntimeError('Job stopped: '+json.dumps(result,ensure_ascii=False))
        raise TimeoutError('Job pending: '+jid+'; inspect library_job before further model edits')
    def query(parameters):
        key='query-'+str(len(list(output.glob('query-*-input.json')))+1)
        inp=output/(key+'-input.json');out=output/(key+'-result.json');write(inp,parameters)
        subprocess.run([args.query_helper,args.probe_root,str(inp),str(out)],check=True,timeout=35,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        result=load(out)
        if not result.get('ok'):raise RuntimeError('VWorld query: '+json.dumps(result,ensure_ascii=False))
        return result
    try:
        client.rpc('initialize',dict(protocolVersion='2025-11-25',capabilities={},clientInfo=dict(name='vworld-massing-workflow',version='1')))
        client.send(dict(jsonrpc='2.0',method='notifications/initialized',params={}))
        instances=tool('list_instances')['instances']
        matching=[i for i in instances if i['title']==config['model_title']]
        if len(matching)!=1:raise RuntimeError('Exactly one model matching configured title must be connected')
        ids={k:matching[0][k] for k in ('session_id','model_id')}
        summary=tool('get_model_summary',**ids)['data']
        if summary['edit_context']['depth']!=0:raise RuntimeError('Exit group editing to model root first')
        write(output/'model-before.json',summary)
        site=tool('get_entity_info',**ids,instance_path=config['site_path'])['data']['item']
        if site['next_child_offset'] is not None:raise RuntimeError('SITE must be one simple face')
        faces=[x for x in site['direct_children'] if x['type']=='Face']
        if len(faces)!=1:raise RuntimeError('SITE must contain one boundary face')
        face=tool('get_entity_info',**ids,instance_path=faces[0]['instance_path'])['data']['item']
        if face['hole_count']:raise RuntimeError('SITE holes are unsupported')
        site_mm=face['vertices_mm']
        geographic=[]
        for pnu in config['site_pnus']:
            parcel=query(dict(operation='parcels',pnu=pnu,limit=100))['data']
            if parcel['possibly_truncated'] or not parcel['geojson']['features']:raise RuntimeError('SITE parcel query incomplete')
            for f in parcel['geojson']['features']:
                polys=f['geometry']['coordinates'] if f['geometry']['type']=='MultiPolygon' else [f['geometry']['coordinates']]
                geographic.extend(p for poly in polys for p in poly[0])
        alignment=align_site(site_mm,geographic);write(output/'alignment.json',alignment)
        print('SITE alignment RMS mm:',round(alignment['rms_mm'],3),flush=True)
        box=bounds(site_mm);lo=[box[0]-radius,box[1]-radius];hi=[box[2]+radius,box[3]+radius]
        a=alignment;bbox=[a['lon0']+(lo[0]-a['origin_mm'][0])/a['mm_per_lon_degree'],a['lat0']+(lo[1]-a['origin_mm'][1])/a['mm_per_lat_degree'],a['lon0']+(hi[0]-a['origin_mm'][0])/a['mm_per_lon_degree'],a['lat0']+(hi[1]-a['origin_mm'][1])/a['mm_per_lat_degree']]
        api=query(dict(operation='buildings',bbox=bbox,limit=100))
        if api['data']['possibly_truncated']:raise RuntimeError('100-building query limit reached; reduce radius')
        refs={}
        for name in ['geo.footprint-scan','geo.vworld-massing']:
            entries=tool('library_list',library_id='user',kind='techniques',state='all',limit=25,query=name)['data']['items']
            entry=next((x for x in entries if x['technique_ref']['technique_id']==name),None)
            if entry is None:
                folder=ROOT/'techniques'/('vworld-footprint-scan' if name=='geo.footprint-scan' else 'vworld-massing')
                files={p:p2.read_text(encoding='utf-8-sig') for p in ['manifest.json','inputs.schema.json','technique.js','tests.json'] for p2 in [folder/p]}
                saved=tool('library_save',library_id='user',technique_id=name,request_id=request(),base_revision=None,files=files,change_summary='Install VWorld massing workflow source')
                ref=saved['data']['technique_ref']
                wait(tool('library_run',**ref,request_id=request(),mode='verify',activate_if_passed=True,expected_active_revision=None))
            # Read the exact stored contract instead of relying on a stale revision in the config.
            contract=tool('library_get',library_id='user',technique_id=name,sections=['contract'])['data']
            ref=contract['technique_ref'];refs[name]=ref
            wait(tool('library_run',**ref,request_id=request(),mode='verify'))
        children=[];cursor=None
        while True:
            kw=dict(ids,parent_path=config['source_path'],limit=25)
            if cursor:kw['cursor']=cursor
            page=tool('get_children',**kw)['data'];children+=page['items'];cursor=page['next_cursor']
            if not cursor:break
        footprints=[]
        for child in children:
            detail=tool('get_entity_info',**ids,instance_path=child['instance_path'],child_limit=1)['data']['item'];b=detail['model_bounds']
            if b['max'][0]<lo[0] or b['min'][0]>hi[0] or b['max'][1]<lo[1] or b['min'][1]>hi[1]:continue
            report=wait(tool('library_run',**refs['geo.footprint-scan'],request_id=request(),mode='plan',params=dict(site_mm=site_mm,radius_mm=radius),bindings=dict(ids,expected_context=[],targets=dict(source=child['instance_path']))))
            footprints+=report['report']['metrics']['footprints']
        matches,skipped=match_footprints(footprints,api['data']['geojson']['features'],alignment)
        report=dict(ids=ids,alignment=alignment,queried_at=api['retrieved_at'],matches=matches,skipped=skipped)
        write(output/'match.json',report)
        print('Footprints:',len(footprints),'matched:',len(matches),'skipped:',len(skipped),flush=True)
        if not matches:raise RuntimeError('No reliable heights to generate')
        if len(matches)>63:raise RuntimeError('At most 63 masses per new group')
        sources=[]
        for m in matches:
            path=m['path'][:-1]
            if path not in sources:sources.append(path)
        if len(sources)>4:raise RuntimeError('More than four source subgroups; narrow radius for one atomic technique run')
        while len(sources)<4:sources.append(sources[0])
        name=args.name or config['name_prefix']+'_'+str(len(matches))+'동_'+datetime.now().strftime('%H%M%S')
        buildings=[dict(path=m['path'],expected_ring_mm=m['ring_mm'],height_mm=m['height_mm'],pnu=m['pnu']) for m in matches]
        bindings=dict(ids,expected_context=[],origin_mm=[0,0,0],materials=dict(mass=config['material']),targets={'source'+str(i):p for i,p in enumerate(sources)})
        plan=wait(tool('library_run',**refs['geo.vworld-massing'],request_id=request(),mode='plan',params=dict(name=name,buildings=buildings),bindings=bindings));write(output/'plan.json',plan)
        if not args.apply:
            print('Plan ready. No model edits. Use -Apply to query again and create a new group.',flush=True);return
        current=tool('get_instance',session_id=ids['session_id'])['state']
        if current['model_id']!=ids['model_id'] or current['authority']!='mcp':raise RuntimeError('Model changed or local MCP permission missing')
        summary=tool('get_model_summary',**ids)['data']
        if summary['edit_context']['depth']:raise RuntimeError('Edit context changed')
        apply_args=dict(ids,request_id=request(),mode='apply',expected_context=[],command_id=current['next_command_id'],plan_id=plan['plan_id'],plan_hash=plan['plan_hash'])
        write(output/'apply-request.json',apply_args)
        result=wait(tool('library_run',**apply_args));write(output/'apply-result.json',result)
        print('Created:',result['created'],flush=True)
        created=result['created'][0]['persistent_id'];children=[];cursor=None
        while True:
            kw=dict(ids,parent_path=[created],limit=25)
            if cursor:kw['cursor']=cursor
            page=tool('get_children',**kw)['data'];children+=page['items'];cursor=page['next_cursor']
            if not cursor:break
        if len(children)!=len(matches):raise RuntimeError('Created group count needs inspection; do not replay apply')
        expected={m['path'][-1]:m['height_mm'] for m in matches};checks=[]
        for child in children:
            detail=tool('get_entity_info',**ids,instance_path=child['instance_path'],child_limit=1)['data']['item']
            source_id=child['name'].split(' | ')[-1]
            check=dict(id=child['persistent_id'],solid=detail.get('manifold'),height_mm=detail['model_bounds']['size'][2],expected_mm=expected.get(source_id));checks.append(check)
            if not check['solid'] or check['expected_mm'] is None or abs(check['height_mm']-check['expected_mm'])>.01:raise RuntimeError('Created mass needs inspection; do not replay apply')
        write(output/'geometry-checks.json',checks)
        print('Completed one new group. Original geometry preserved. Undo once removes the massing.',flush=True)
    except Exception as e:
        write(output/'stopped.json',dict(error=str(e),jobs=jobs));raise
    finally:client.close()

if __name__=='__main__':main()
