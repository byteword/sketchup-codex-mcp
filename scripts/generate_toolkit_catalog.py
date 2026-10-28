"""Generate the bounded toolkit schema embedded in the .NET 4.8 adapter."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def number(lo=-1e9, hi=1e9): return dict(type="number", minimum=lo, maximum=hi)
def integer(lo, hi): return dict(type="integer", minimum=lo, maximum=hi)
def text(): return dict(type="string", minLength=1, maxLength=256)
def choice(*values): return dict(type="string", enum=list(values))
def array(item, lo, hi): return dict(type="array", items=item, minItems=lo, maxItems=hi)
def obj(fields, required=()): return dict(type="object", properties=fields, required=list(required), additionalProperties=False)
vector = array(number(), 3, 3)
points = array(vector, 1, 256)
pid = dict(type="string", pattern="^[1-9][0-9]{0,18}$", maxLength=19)
definition_id = dict(type="string", pattern="^definition:[1-9][0-9]{0,18}$",maxLength=30)
ids = array(pid, 1, 128)
boolean = dict(type="boolean")
specs = {}
def tool(name, description, fields, required, read=False):
    common = dict(session_id=dict(type="string", format="uuid"), model_id=dict(type="string", format="uuid"))
    needed = ["session_id", "model_id"]
    if not read:
        common.update(command_id=dict(type="string", pattern="^[0-9a-fA-F-]{36}:[1-9][0-9]{0,9}$", maxLength=48), expected_context=array(pid,0,32), dry_run=boolean)
        needed += ["command_id", "expected_context"]
    common.update(fields)
    specs["sketchup_"+name] = dict(description=description, read=read, schema=obj(common,needed+required))

tool("get_resources", "Read paged materials, tags, component definitions or camera scenes. Exact names/IDs; no permission required. Pages are live; restart after edits. No texture file contents.",
     dict(kind=choice("materials","tags","definitions","scenes"),offset=integer(0,1000000),limit=integer(1,25)), ["kind"], True)
tool("manage_resource", "Create/update/delete solid-color materials or tags, or purge unused definitions/materials/tags. Tag deletion preserves geometry and reassigns it to Layer0. Layer0 and active tag cannot be deleted. Purge is model-wide and requires confirm_model_wide=true. No texture file access.",
     dict(kind=choice("materials","tags","definitions"),action=choice("create","update","delete","purge_unused"),options=obj(dict(name=text(),new_name=text(),color_rgb=array(integer(0,255),3,3),alpha=number(0,1),visible=boolean,confirm_model_wide=boolean))),["kind","action","options"])
tool("component", "Convert groups to components, explode explicit groups/components, replace component definitions, create instances of an existing definition, or update definition name/description. Definition metadata affects all occurrences. Recursive definitions and glued targets are rejected; shared edits require explicit affect_all_instances=true.",
     dict(action=choice("convert","explode","replace","instantiate","metadata"),options=obj(dict(entity_ids=array(pid,1,25),definition_id=definition_id,name=text(),description=dict(type="string",maxLength=1024),origin_mm=vector,affect_all_instances=boolean))),["action","options"])
tool("create_geometry", "Create isolated geometry in a new group using model-axis mm: construction points, planar face, regular polygon, center/two-point(ends+signed bulge)/three-point arc, Bezier or freehand curve, closed oriented indexed polyhedron, convex planar polygon offset, revolution or Follow Me sweep. Precision is segments (3..128); no holes or self-intersecting profiles. See options required by each kind in docs/EXTENDED_TOOLKIT.md.",
     dict(kind=choice("points","face","polygon","arc_center","arc_two_point","arc_three_point","bezier","freehand","polyhedron","offset","revolve","sweep"),name=text(),options=obj(dict(points_mm=points,faces=array(array(integer(0,255),3,64),4,256),origin_mm=vector,plane=choice("XY","XZ","YZ"),radius_mm=number(1,1000000),sides=integer(3,128),segments=integer(3,128),start_degrees=number(-360,360),sweep_degrees=number(-360,360),bulge_mm=number(-1000000,1000000),distance_mm=number(-1000000,1000000),pivot_mm=vector,axis=vector,path_mm=array(vector,2,64)))),["kind","name","options"])
tool("edit_geometry", "Edit explicit raw children of one direct group/component. Unique definition required (use make_unique first). Add points/lines/faces, erase raw items, move construction points or edge endpoints, regenerate bounded faces, reverse faces, assign front/back materials, soften/smooth or unsoften edges, dissolve only coplanar internal edges. Edge deletion can remove adjacent faces. IDs/paths become stale after topology edits. No implicit edit-context changes.",
     dict(container_id=pid,affect_all_instances=boolean,action=choice("add_points","add_lines","add_face","erase","move_points","move_vertices","rebuild_faces","reverse_faces","properties","soften","unsoften","simplify"),options=obj(dict(entity_ids=ids,points_mm=points,delta_mm=vector,vertex_moves=array(obj(dict(edge_id=pid,endpoint=choice("start","end"),position_mm=vector),["edge_id","endpoint","position_mm"]),1,64),material=dict(type=["string","null"],minLength=1,maxLength=256),back_material=dict(type=["string","null"],minLength=1,maxLength=256),hidden=boolean,angle_degrees=number(0,180)))),["container_id","action","options"])
tool("mirror_entities", "Reflect up to25 explicit groups/components about a model-axis plane through pivot_mm. Preserves component sharing. One Undo operation; mirrored normals/handedness are inherent to reflection.",dict(entity_ids=array(pid,1,25),pivot_mm=vector,axis=choice("X","Y","Z")),["entity_ids","pivot_mm","axis"])
tool("configure_camera", "Set eye/target/up in model coordinates, perspective and FOV (degrees) or orthographic height (mm). Camera change has no model Undo and restores the previous camera on failure. Requires normal camera mode.",dict(eye_mm=vector,target_mm=vector,up=vector,perspective=boolean,fov_degrees=number(1,120),height_mm=number(1,1e9)),["eye_mm","target_mm","up","perspective"])
tool("scene", "Create/update/rename/delete camera-only scenes, or apply a saved scene's camera immediately without animation or applying its other flags. Existing scenes with other saved properties cannot be updated/deleted. Scene changes are not reliably model-Undoable in SketchUp2019; no automated destructive retry.",dict(action=choice("create","update","apply","delete"),name=text(),options=obj(dict(new_name=text(),description=dict(type="string",maxLength=1024)))),["action","name","options"])

specs['sketchup_create_geometry']['description'] += ' Required options: points/face/freehand: points_mm; polygon: origin_mm,plane,radius_mm,sides; arc_center: origin_mm,plane,radius_mm,start_degrees,sweep_degrees; arc_two_point: points_mm=[start,end],plane,bulge_mm; arc_three_point: points_mm=[start,through,end]; bezier: points_mm(2..16 controls); polyhedron: points_mm,faces(index loops); offset: points_mm,distance_mm(positive outward); revolve: points_mm(closed profile),pivot_mm,axis,sweep_degrees; sweep: points_mm(closed profile),path_mm(start on profile plane, first segment normal). Optional segments for arcs/Bezier/revolve, default24. Mesh budget256 faces/2048 indexed corners.'
specs['sketchup_edit_geometry']['description'] = specs['sketchup_edit_geometry']['description'].replace('Unique definition required (use make_unique first).','Unique definition required, or explicit affect_all_instances=true for shared components; this edits their definition for all occurrences. Shared groups still require make_unique.') + ' Required options: add_points/add_lines/add_face: points_mm; move_vertices: vertex_moves(edge_id,endpoint=start/end,position_mm); others: entity_ids. move_points also delta_mm. properties: material/back_material(null clears),hidden. soften: optional angle_degrees default30, only two-face edges within angle. simplify: only untextured matching coplanar face pairs; verifies total area.'
specs['sketchup_component']['description'] += ' Required options: convert/explode: entity_ids; replace: entity_ids,definition_id; instantiate: definition_id,origin_mm; metadata: definition_id,affect_all_instances=true plus name/description. definition_id is a model-session-local definition:<entityID> returned by get_resources/get_entity_info, not a drawing persistent ID. Query fresh after model switching.'
target=ROOT/'shared/ToolkitSchemas.json'
target.write_text(json.dumps(specs,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
source=json.dumps(specs,ensure_ascii=True,separators=(',',':')).replace('"','""')
template=(ROOT/'scripts/ToolkitCatalog.template').read_text(encoding='utf-8')
(ROOT/'shared/ToolkitCatalog.cs').write_text(template.replace('SCHEMAS_JSON',source),encoding='utf-8')
