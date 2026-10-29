using System;
using System.IO;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace SketchUpPipeProbe
{
    public sealed partial class LibraryService
    {
        readonly SemaphoreSlim workers=new SemaphoreSlim(2,2);
        static readonly string[] Capabilities={"group/1","mesh/1","material-existing/1","verify/1","cleanup/1","target-summary/1","target-subtree/1"};
        void Graph(string id,string rev,Dictionary<string,object> packages,HashSet<string> visiting,int depth=0,bool checkCapabilities=true) {
            string key=id+"@"+rev;
            if(visiting.Contains(key))throw new LibraryFault("dependency_cycle","Cyclic pinned dependency");
            if(packages.ContainsKey(key))return;
            if(depth>8||packages.Count>=16)throw new LibraryFault("budget_exceeded","Dependency graph exceeds budget");
            if(!Libraries.Any(l=>Techniques(l.Key).ContainsKey(id)&&Lib.Obj(Lib.Obj(Techniques(l.Key)[id])["revisions"]).ContainsKey(rev)))throw new LibraryFault("dependency_missing","Unregistered dependency: "+key);
            var files=ReadFiles(rev);var m=ValidateFiles(files);
            if(Lib.Str(m,"id")!=id)throw new LibraryFault("dependency_missing","Revision does not belong to requested technique");
            foreach(string cap in Lib.Arr(m["requires"]))if(checkCapabilities&&!Capabilities.Contains(cap))throw new LibraryFault("capability_missing","Unsupported capability: "+cap);
            visiting.Add(key);
            var dependencies=Lib.Map();var helpers=Lib.Map();
            foreach(object raw in Lib.Arr(m["dependencies"])) {
                var d=Lib.Obj(raw);string childId=Lib.Str(d,"technique_id"),childRev=Lib.Str(d,"revision");
                Graph(childId,childRev,packages,visiting,depth+1,checkCapabilities);dependencies[Lib.Str(d,"alias")]=childId+"@"+childRev;
            }
            foreach(object raw in Lib.Arr(Lib.Get(m,"helpers",new object[0]))) {var h=Lib.Obj(raw);helpers[Lib.Str(h,"alias")]=files[Lib.Str(h,"path")];}
            visiting.Remove(key);
            if(packages.Count>=16)throw new LibraryFault("budget_exceeded","Dependency graph exceeds16 revisions");
            packages[key]=Lib.Map("source",files["technique.js"],"dependencies",dependencies,"helpers",helpers,"schema",Lib.Parse(files["inputs.schema.json"]));
        }
        async Task<Dictionary<string,object>> Compute(string library,string id,string rev,Dictionary<string,object> parameters,object inputs,CancellationToken token) {
            Dictionary<string,string> files;Dictionary<string,object> manifest,packages=Lib.Map();
            lock(gate) {files=ReadFiles(rev);manifest=ValidateFiles(files);Graph(id,rev,packages,new HashSet<string>());}
            var schema=Lib.Parse(files["inputs.schema.json"]);var normalized=Lib.Obj(LibrarySchema.Normalize(schema,parameters));LibrarySchema.Validate(schema,normalized);
            var budget=Lib.Obj(manifest["budgets"]);
            var request=Lib.Map("root",id+"@"+rev,"packages",packages,"input",Lib.Map("params",normalized,"inputs",inputs??Lib.Map()),
                "timeout_ms",budget["plan_ms"],"memory_mib",budget["memory_mib"]);
            object result;
            await workers.WaitAsync(token).ConfigureAwait(false);
            try {result=await LibraryWorker.RunAsync(request,token).ConfigureAwait(false);}finally {workers.Release();}
            LibrarySchema.Validate(LibrarySchema.Bundled(Lib.Str(manifest,"output")=="sketchup-plan/1"?"plan":"report"),result);
            Lib.TextBudget(result,Lib.Int(budget,"max_plan_bytes",48000,1024,48000));
            if(Lib.Str(manifest,"output")=="sketchup-plan/1")ValidatePlan(Lib.Obj(result),manifest);
            return Lib.Map("output",result,"normalized_params",normalized,"dependencies",packages.Keys.ToArray(),"manifest",manifest);
        }
        static double[] Vec(object raw) {return Lib.Arr(raw).Cast<object>().Select(Convert.ToDouble).ToArray();}
        static double Dot(double[] a,double[] b) {return a.Zip(b,(x,y)=>x*y).Sum();}
        static double[] Sub(double[] a,double[] b) {return a.Zip(b,(x,y)=>x-y).ToArray();}
        static double[] Cross(double[] a,double[] b) {return new[]{a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]};}
        static void ValidatePlan(Dictionary<string,object> plan,Dictionary<string,object> manifest) {
            var budget=Lib.Obj(manifest["budgets"]);var groups=new HashSet<string>();var ids=new HashSet<string>();int points=0,faces=0;
            var roles=Lib.Arr(manifest["material_roles"]).Cast<string>().ToArray();
            var declared=Lib.Arr(manifest["requires"]).Cast<string>().ToArray();
            foreach(string capability in new[]{"group/1","mesh/1","verify/1","material-existing/1"})
                if(!declared.Contains(capability))throw new LibraryFault("manifest_invalid","Generator must declare "+capability);
            var nodes=Lib.Arr(plan["nodes"]);if(nodes.Count>Convert.ToInt32(budget["max_nodes"]))throw new LibraryFault("budget_exceeded","Too many nodes");
            foreach(object raw in nodes) {
                var n=Lib.Obj(raw);string id=Lib.Str(n,"id"),kind=Lib.Str(n,"kind");
                if(!ids.Add(id))throw new LibraryFault("plan_invalid","Duplicate node id");
                if(id==Lib.Str(plan,"root")) {if(groups.Count!=0||kind!="group"||n.ContainsKey("parent"))throw new LibraryFault("plan_invalid","Root must be first parentless group");}
                else if(!groups.Contains(Lib.Str(n,"parent")))throw new LibraryFault("plan_invalid","Parent must be an earlier group");
                if(n.ContainsKey("transform")) {
                    var m=Vec(n["transform"]);
                    double det=m[0]*(m[5]*m[10]-m[6]*m[9])-m[4]*(m[1]*m[10]-m[2]*m[9])+m[8]*(m[1]*m[6]-m[2]*m[5]);
                    if(Math.Abs(m[3])+Math.Abs(m[7])+Math.Abs(m[11])+Math.Abs(m[15]-1)>1e-10||Math.Abs(det)<1e-12)throw new LibraryFault("plan_invalid","Transform must be invertible affine");
                }
                if(kind=="group"){groups.Add(id);continue;}
                if(Lib.Str(n,"cleanup")=="material_safe"&&!declared.Contains("cleanup/1"))throw new LibraryFault("manifest_invalid","Declare cleanup/1 for material_safe");
                var vertices=Lib.Arr(n["points_mm"]).Cast<object>().Select(Vec).ToArray();var polygons=Lib.Arr(n["faces"]);
                points+=vertices.Length;faces+=polygons.Count;
                var faceRoles=Lib.Arr(n["face_roles"]);
                if(faceRoles.Count!=polygons.Count||faceRoles.Cast<string>().Any(x=>!roles.Contains(x)))throw new LibraryFault("plan_invalid","Face material roles do not match manifest");
                var edges=new Dictionary<string,List<int[]>>();double volume=0;double[] reference=vertices[0];
                foreach(object polygon in polygons) {
                    var f=Lib.Arr(polygon).Cast<object>().Select(Convert.ToInt32).ToArray();
                    if(f.Any(i=>i>=vertices.Length))throw new LibraryFault("plan_invalid","Mesh index out of range");
                    double[] normal=null;
                    for(int j=1;j<f.Length-1;j++) {var cross=Cross(Sub(vertices[f[j]],vertices[f[0]]),Sub(vertices[f[j+1]],vertices[f[0]]));if(Dot(cross,cross)>1e-12){normal=cross;break;}}
                    if(normal==null)throw new LibraryFault("plan_invalid","Degenerate face");
                    double length=Math.Sqrt(Dot(normal,normal));
                    if(f.Any(i=>Math.Abs(Dot(Sub(vertices[i],vertices[f[0]]),normal))/length>0.001))throw new LibraryFault("plan_invalid","Nonplanar face");
                    for(int j=0;j<f.Length;j++) {
                        int a=f[j],b=f[(j+1)%f.Length];if(Math.Sqrt(Dot(Sub(vertices[a],vertices[b]),Sub(vertices[a],vertices[b])))<0.01)throw new LibraryFault("plan_invalid","Edge too short");
                        string key=Math.Min(a,b)+":"+Math.Max(a,b);if(!edges.ContainsKey(key))edges[key]=new List<int[]>();edges[key].Add(new[]{a,b});
                    }
                    for(int j=1;j<f.Length-1;j++)volume+=Dot(Sub(vertices[f[0]],reference),Cross(Sub(vertices[f[j]],reference),Sub(vertices[f[j+1]],reference)))/6;
                }
                if(volume<=0.001||edges.Values.Any(e=>e.Count!=2||e[0][0]!=e[1][1]||e[0][1]!=e[1][0]))throw new LibraryFault("plan_invalid","Mesh must be consistently closed and outward oriented");
            }
            if(!ids.Contains(Lib.Str(plan,"root")))throw new LibraryFault("plan_invalid","Root missing");
            if(points==0||faces==0||points>Convert.ToInt32(budget["max_points"])||faces>Convert.ToInt32(budget["max_faces"]))throw new LibraryFault("budget_exceeded","Geometry count budget exceeded");
            foreach(object raw in Lib.Arr(plan["assertions"]))if(!ids.Contains(Lib.Str(Lib.Obj(raw),"node")))throw new LibraryFault("plan_invalid","Assertion node missing");
        }
        object OutputSummary(Dictionary<string,object> output) {
            if(Lib.Str(output,"format_version")!="sketchup-plan/1")return output;
            return Lib.Map("root",output["root"],"group_count",Lib.Arr(output["nodes"]).Count,"mesh_face_count",Lib.Arr(output["nodes"]).Cast<object>().Select(Lib.Obj).Where(n=>Lib.Str(n,"kind")=="mesh").Sum(n=>Lib.Arr(n["faces"]).Count),"assertions",output["assertions"]);
        }
        async Task<object> StartRun(Dictionary<string,object> a,NativeCall native) {
            bool created=false;object response;string jobId="";
            lock(gate) {
                response=Mutate("run",a,()=>{
                    if(cancellations.Count>=32)throw new LibraryFault("library_busy","Library job queue is full");
                    jobId=Guid.NewGuid().ToString();string mode=Lib.Str(a,"mode");
                    if(mode=="apply") {
                        var plan=Record("plans",Lib.Str(a,"plan_id"));
                        if(Lib.Str(plan,"plan_hash")!=Lib.Str(a,"plan_hash"))throw new LibraryFault("plan_hash_mismatch","Plan hash mismatch");
                        var hashed=Lib.Obj(Lib.Clone(plan));hashed.Remove("plan_hash");
                        if(Lib.Digest(hashed)!=Lib.Str(plan,"plan_hash"))throw new LibraryFault("plan_corrupt","Stored plan content no longer matches its digest");
                        if(DateTime.Parse(Lib.Str(plan,"expires_at"),null,System.Globalization.DateTimeStyles.RoundtripKind)<DateTime.UtcNow)throw new LibraryFault("plan_expired","Create a new plan");
                        var binding=Lib.Obj(plan["bindings"]);
                        foreach(string key in new[]{"session_id","model_id","expected_context"})if(!binding.ContainsKey(key)||Lib.Json(Lib.Canon(binding[key]))!=Lib.Json(Lib.Canon(a[key])))throw new LibraryFault("plan_binding_mismatch","Plan must match current session/model/edit context");
                        var t=Technique(Lib.Str(plan,"library_id"),Lib.Str(plan,"technique_id"));if(Lib.Bool(t,"archived"))throw new LibraryFault("technique_archived","Restore technique first");
                        var claims=Lib.Obj(Lib.Get(state,"plan_claims",Lib.Map()));state["plan_claims"]=claims;
                        if(claims.ContainsKey(Lib.Str(a,"plan_id")))throw new LibraryFault("plan_in_use","This plan is consumed by job "+claims[Lib.Str(a,"plan_id")]);
                        claims[Lib.Str(a,"plan_id")]=jobId;
                    }else {
                        var t=Technique(LibraryId(a),TechniqueId(a));PickRevision(a,t);
                        if(Lib.Bool(t,"archived"))throw new LibraryFault("technique_archived","Restore technique first");
                    }
                    var job=Lib.Map("job_id",jobId,"request_id",a["request_id"],"state","queued","stage","load","effect","none","submitted",false,
                        "arguments",a,"created_at",DateTime.UtcNow.ToString("o"),"events",new object[0]);
                    WriteRecord("jobs",jobId,job);created=true;
                    return Success(Lib.Map("job_id",jobId,"state","queued"));
                },false);
                if(created) {
                    var c=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);cancellations[jobId]=c;
                    string running=jobId;
                    Wire.Observe(Task.Run(()=>Work(running,a,native,c.Token)),error=>{});
                }
            }
            await Task.FromResult(0);return response;
        }
        void UpdateJob(string id,string stateName,string stage,string effect,object result=null,object error=null) {
            lock(gate) {
                var job=Record("jobs",id);job["state"]=stateName;job["stage"]=stage;job["effect"]=effect;
                if(result!=null)job["result"]=result;if(error!=null)job["error"]=error;
                var events=Lib.Arr(job["events"]).Cast<object>().ToList();
                events.Add(Lib.Map("index",events.Count+1,"state",stateName,"stage",stage,"at",DateTime.UtcNow.ToString("o")));
                job["events"]=events;job["updated_at"]=DateTime.UtcNow.ToString("o");WriteRecord("jobs",id,job);
            }
        }
        async Task Work(string jobId,Dictionary<string,object> a,NativeCall native,CancellationToken token) {
            try {
                UpdateJob(jobId,"running","validate","none");string mode=Lib.Str(a,"mode");token.ThrowIfCancellationRequested();
                if(mode=="apply") {await Apply(jobId,a,native,token).ConfigureAwait(false);return;}
                string library=LibraryId(a),id=TechniqueId(a),rev=Lib.Str(a,"revision");
                if(mode=="verify") {
                    var verification=await Verify(library,id,rev,a,native,jobId,token).ConfigureAwait(false);
                    var v=Lib.Obj(verification);
                    UpdateJob(jobId,Lib.Bool(v,"passed")?"succeeded":"failed","test",Lib.Bool(v,"passed")&&Lib.Bool(a,"activate_if_passed")?"library_changed":"none",verification,
                        Lib.Bool(v,"passed")?null:Lib.Map("code","verification_failed","message","Inspect the named case results"));return;
                }
                var files=ReadFiles(rev);var parameters=Lib.Obj(Lib.Clone(a["params"]));
                if(a.ContainsKey("preset")) {
                    if(!files.ContainsKey("presets.json"))throw new LibraryFault("preset_not_found","No presets file");
                    var presets=Lib.Parse(files["presets.json"]);object preset;if(!presets.TryGetValue(Lib.Str(a,"preset"),out preset))throw new LibraryFault("preset_not_found","Unknown preset");
                    var merged=Lib.Obj(Lib.Clone(preset));foreach(var p in parameters)merged[p.Key]=p.Value;parameters=merged;
                }
                var manifest=Lib.Parse(files["manifest.json"]);var bindings=Lib.Obj(Lib.Get(a,"bindings",Lib.Map()));var inputs=Lib.Map();var fingerprints=new List<object>();
                if(bindings.Count>0) {
                    string[] allowed={"session_id","model_id","expected_context","origin_mm","materials","replace_entity_id","targets","name"};
                    if(bindings.Keys.Any(k=>!allowed.Contains(k)))throw new LibraryFault("input_invalid","Unknown binding");
                }
                await CheckBindings(bindings,manifest,native,token).ConfigureAwait(false);
                foreach(object raw in Lib.Arr(manifest["reads"])) {
                    if(native==null)throw new LibraryFault("bindings_required","Connected model required by declared reads");
                    var read=Lib.Obj(raw);var targets=Lib.Obj(Lib.Get(bindings,"targets",Lib.Map()));object target;
                    if(!targets.TryGetValue(Lib.Str(read,"binding"),out target))throw new LibraryFault("bindings_required","Missing declared target binding");
                    var query=Lib.Map("session_id",Lib.Str(bindings,"session_id"),"model_id",Lib.Str(bindings,"model_id"),
                        "query",read["query"],"instance_path",target,"max_entities",read["max_entities"]);
                    string fingerprint=null;var entities=new List<object>();object targetData=null;
                    do {
                        var response=await native("get_plan_snapshot",query,token).ConfigureAwait(false);
                        if(!Lib.Bool(response,"ok"))throw new LibraryFault("snapshot_failed",Lib.Json(response));
                        var data=Lib.Obj(response["data"]);
                        if(fingerprint!=null&&fingerprint!=Lib.Str(data,"fingerprint"))throw new LibraryFault("model_stale","Model changed during snapshot paging");
                        fingerprint=Lib.Str(data,"fingerprint");var snapshot=Lib.Obj(data["snapshot"]);targetData=snapshot["target"];
                        entities.AddRange(Lib.Arr(snapshot["entities"]).Cast<object>());
                        if(Lib.Get(data,"next_offset")==null)break;query["offset"]=data["next_offset"];
                    }while(true);
                    inputs[Lib.Str(read,"name")]=Lib.Map("target",targetData,"entities",entities);
                    fingerprints.Add(Lib.Map("query",read["query"],"instance_path",target,"fingerprint",fingerprint,"max_entities",read["max_entities"]));
                }
                if(bindings.ContainsKey("replace_entity_id")) {
                    var path=Lib.Arr(bindings["expected_context"]).Cast<object>().Concat(new object[]{bindings["replace_entity_id"]}).ToArray();
                    var query=Lib.Map("session_id",bindings["session_id"],"model_id",bindings["model_id"],"query","target-summary/1","instance_path",path,"max_entities",2048);
                    var response=await native("get_plan_snapshot",query,token).ConfigureAwait(false);
                    if(!Lib.Bool(response,"ok"))throw new LibraryFault("snapshot_failed","Could not fingerprint replacement target");
                    fingerprints.Add(Lib.Map("query","target-summary/1","instance_path",path,"fingerprint",Lib.Obj(response["data"])["fingerprint"],"max_entities",2048));
                }
                UpdateJob(jobId,"running","plan","none");
                var computed=await Compute(library,id,rev,parameters,inputs,token).ConfigureAwait(false);
                var output=Lib.Obj(computed["output"]);
                if(Lib.Str(output,"format_version")=="probe-report/1"){UpdateJob(jobId,"succeeded","plan","none",Lib.Map("result_type","report_ready","report",output,"technique_ref",Ref(library,id,rev)));return;}
                string planId=Guid.NewGuid().ToString();
                var record=Lib.Map("plan_id",planId,"library_id",library,"technique_id",id,"revision",rev,"normalized_params",computed["normalized_params"],
                    "bindings",bindings,"fingerprints",fingerprints,"dependencies",computed["dependencies"],"plan",output,"created_at",DateTime.UtcNow.ToString("o"),"expires_at",DateTime.UtcNow.AddMinutes(10).ToString("o"));
                record["plan_hash"]=Lib.Digest(record);WriteRecord("plans",planId,record);
                UpdateJob(jobId,"succeeded","plan","none",Lib.Map("result_type","plan_ready","plan_id",planId,"plan_hash",record["plan_hash"],"expires_at",record["expires_at"],
                    "technique_ref",Ref(library,id,rev),"normalized_params",computed["normalized_params"],"summary",OutputSummary(output)));
            }catch(OperationCanceledException){UpdateJob(jobId,"canceled","cancel","none");}
            catch(Exception error) {
                var j=Record("jobs",jobId);if(new[]{"failed","outcome_unknown"}.Contains(Lib.Str(j,"state")))return;bool submitted=Lib.Bool(j,"submitted");
                UpdateJob(jobId,submitted?"outcome_unknown":"failed",submitted?"reconcile":"validate",submitted?"unknown":"none",null,Lib.Obj(Lib.Error(error,submitted?"unknown":"none"))["error"]);
            }finally {lock(gate){CancellationTokenSource c;if(cancellations.TryGetValue(jobId,out c)){cancellations.Remove(jobId);c.Dispose();}}}
        }
        async Task CheckBindings(Dictionary<string,object> bindings,Dictionary<string,object> manifest,NativeCall native,CancellationToken token) {
            string[] allowed={"session_id","model_id","expected_context","origin_mm","materials","replace_entity_id","targets","name"};
            if(bindings.Keys.Any(k=>!allowed.Contains(k)))throw new LibraryFault("input_invalid","Unknown binding");
            if(bindings.Count==0)return;
            foreach(string key in new[]{"session_id","model_id"}) {
                Guid parsed;if(!Guid.TryParseExact(Lib.Str(bindings,key),"D",out parsed))throw new LibraryFault("bindings_required","Bindings require exact current session/model IDs");
            }
            if(!bindings.ContainsKey("expected_context"))throw new LibraryFault("bindings_required","Bindings require an explicit current edit context");
            var context=Lib.Arr(bindings["expected_context"]);
            if(context.Count>32||context.Cast<object>().Any(x=>!(x is string)||!System.Text.RegularExpressions.Regex.IsMatch((string)x,"\\A[1-9][0-9]{0,18}\\z")))
                throw new LibraryFault("input_invalid","Invalid edit context");
            if(bindings.ContainsKey("origin_mm")) {
                var p=Lib.Arr(bindings["origin_mm"]);if(p.Count!=3||p.Cast<object>().Any(x=>!Lib.Numeric(x)||Math.Abs(Convert.ToDouble(x))>1e9))throw new LibraryFault("input_invalid","origin_mm requires three bounded mm numbers");
            }
            var materials=Lib.Obj(Lib.Get(bindings,"materials",Lib.Map()));
            if(materials.Count>16)throw new LibraryFault("input_invalid","At most16 material roles");
            if(bindings.ContainsKey("replace_entity_id"))Lib.Id(bindings,"replace_entity_id","[1-9][0-9]{0,18}");
            if(bindings.ContainsKey("name")&&Lib.Str(bindings,"name").Length>128)throw new LibraryFault("input_invalid","Name too long");
            foreach(string role in Lib.Arr(manifest["material_roles"]))if(!materials.ContainsKey(role))throw new LibraryFault("bindings_required","Choose an existing material for role "+role);
            foreach(var p in materials)if(!(p.Value is string)||((string)p.Value).Length<1||((string)p.Value).Length>256)throw new LibraryFault("input_invalid","Material names must be exact existing text");
            if(native==null)throw new LibraryFault("instance_not_found","Connected model required for bound plans");
            var response=await native("get_state",Lib.Map("session_id",bindings["session_id"]),token).ConfigureAwait(false);
            if(!Lib.Bool(response,"ok"))throw new LibraryFault("instance_not_found","Could not read current model state");
            var current=Lib.Obj(response["state"]);
            if(Lib.Str(current,"model_id")!=Lib.Str(bindings,"model_id"))throw new LibraryFault("model_mismatch","Refresh current model ID");
            var caps=Lib.Arr(Lib.Get(current,"library_capabilities",new object[0])).Cast<string>().ToArray();
            foreach(string capability in Lib.Arr(manifest["requires"]))if(!caps.Contains(capability))throw new LibraryFault("capability_missing","Update SketchUp extension; missing "+capability);
            if(materials.Count>0) {
                var palette=await native("get_plan_materials",Lib.Map("session_id",bindings["session_id"],"model_id",bindings["model_id"],"materials",materials),token).ConfigureAwait(false);
                if(!Lib.Bool(palette,"ok"))throw new LibraryFault("material_not_found","Material lookup failed: "+Lib.Json(palette));
            }
        }
        async Task<object> Verify(string library,string id,string rev,Dictionary<string,object>a,NativeCall native,string jobId,CancellationToken token) {
            var files=ReadFiles(rev);var cases=Lib.Arr(Lib.Parse(files["tests.json"])["cases"]).Cast<object>().Select(Lib.Obj).ToArray();
            if(a.ContainsKey("tests"))cases=cases.Where(c=>Lib.Arr(a["tests"]).Contains(c["id"])).ToArray();
            if(cases.Length==0)throw new LibraryFault("test_not_found","No selected cases");
            var results=new List<object>();var plans=new List<object>();bool passed=true;
            foreach(var c in cases) {
                token.ThrowIfCancellationRequested();bool ok=true;object diagnostic=null;
                var expected=Lib.Obj(c["expect"]);bool expectedOk=Lib.Bool(expected,"ok");
                try {
                    var computed=await Compute(library,id,rev,Lib.Obj(c["params"]),Lib.Get(c,"inputs",Lib.Map()),token).ConfigureAwait(false);
                    if(!expectedOk)throw new LibraryFault("test_failed","Expected input rejection");
                    var output=Lib.Obj(computed["output"]);
                    if(expected.ContainsKey("metrics")) {
                        var metrics=Lib.Obj(output["metrics"]);
                        foreach(var p in Lib.Obj(expected["metrics"]))if(!metrics.ContainsKey(p.Key)||Lib.Json(Lib.Canon(metrics[p.Key]))!=Lib.Json(Lib.Canon(p.Value)))throw new LibraryFault("test_failed","Metric mismatch: "+p.Key);
                    }
                    if(Lib.Str(output,"format_version")=="sketchup-plan/1") {
                        var nodes=Lib.Arr(output["nodes"]).Cast<object>().Select(Lib.Obj).ToArray();
                        if(expected.ContainsKey("groups")&&nodes.Length!=Convert.ToInt32(expected["groups"]))throw new LibraryFault("test_failed","Group count mismatch");
                        if(expected.ContainsKey("mesh_faces")&&nodes.Where(n=>Lib.Str(n,"kind")=="mesh").Sum(n=>Lib.Arr(n["faces"]).Count)!=Convert.ToInt32(expected["mesh_faces"]))throw new LibraryFault("test_failed","Face count mismatch");
                        if(expected.ContainsKey("bounds_mm"))CheckBounds(output,Lib.Obj(expected["bounds_mm"]));
                        plans.Add(output);
                    }
                }catch(LibraryFault error) {
                    if(expectedOk||error.Code!=Lib.Str(expected,"code")||error.Path!=Lib.Str(expected,"path")){ok=false;diagnostic=Lib.Obj(Lib.Error(error))["error"];}
                }
                passed&=ok;results.Add(Lib.Map("id",c["id"],"passed",ok,"diagnostic",diagnostic));
            }
            bool full=cases.Length==Lib.Arr(Lib.Parse(files["tests.json"])["cases"]).Count;
            lock(gate) {
                ChangeState(()=>{
                    var t=Technique(library,id);var validation=Lib.Obj(Lib.Obj(Lib.Obj(t["revisions"])[rev])["validation"]);
                    if(full)validation["offline"]=passed?"passed":"failed";
                    validation["engine"]="Jint 3.1.6";validation["checked_at"]=DateTime.UtcNow.ToString("o");
                },true);
            }
            if(Lib.Str(a,"environment","offline")=="native") {
                if(!passed||plans.Count==0)throw new LibraryFault("verification_required","Native tests require valid geometry cases");
                if(native==null)throw new LibraryFault("bindings_required","Native verification requires a test model");
                var bindings=Lib.Obj(Lib.Get(a,"bindings",Lib.Map()));
                if(bindings.Count==0)throw new LibraryFault("bindings_required","Native verification requires bound test model/materials");
                await CheckBindings(bindings,Lib.Parse(files["manifest.json"]),native,token).ConfigureAwait(false);
                var fields=Lib.Map("session_id",Lib.Str(bindings,"session_id"),"model_id",Lib.Str(bindings,"model_id"),
                    "expected_context",bindings["expected_context"],"command_id",Lib.Str(a,"command_id"),"plans",plans,"bindings",bindings,"verify_only",true);
                MarkSubmitted(jobId,fields);
                var result=await native("apply_library_plan",fields,CancellationToken.None).ConfigureAwait(false);
                if(!NativeResult(jobId,result))throw new LibraryFault("native_failed","Native verification failed");
                lock(gate){ChangeState(()=>{var validation=Lib.Obj(Lib.Obj(Lib.Obj(Technique(library,id)["revisions"])[rev])["validation"]);validation["native"]="passed";},true);}
            }
            if(!passed)return Lib.Map("result_type","verified","passed",false,"full_suite",full,"cases",results,"technique_ref",Ref(library,id,rev));
            if(Lib.Bool(a,"activate_if_passed"))lock(gate) {
                var t=Technique(library,id);
                if(Lib.Bool(t,"archived")||!full||!a.ContainsKey("expected_active_revision")||!Object.Equals(a["expected_active_revision"],Lib.Str(t,"active")==""?null:t["active"])||Lib.Str(t,"head")!=rev)
                    throw new LibraryFault("active_conflict","Head/active changed during verification");
                ChangeState(()=>{Technique(library,id)["active"]=rev;},true);
            }
            return Lib.Map("result_type","verified","passed",passed,"full_suite",full,"cases",results,"technique_ref",Ref(library,id,rev));
        }
        static void CheckBounds(Dictionary<string,object> plan,Dictionary<string,object> expected) {
            // Independent numeric traversal; SDK bounds will be checked again on apply.
            var matrices=new Dictionary<string,double[]>();var all=new List<double[]>();
            double[] identity={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
            foreach(object raw in Lib.Arr(plan["nodes"])) {
                var n=Lib.Obj(raw);var local=n.ContainsKey("transform")?Vec(n["transform"]):identity;
                var parent=n.ContainsKey("parent")?matrices[Lib.Str(n,"parent")]:identity;var world=new double[16];
                for(int c=0;c<4;c++)for(int r=0;r<4;r++)for(int k=0;k<4;k++)world[c*4+r]+=parent[k*4+r]*local[c*4+k];
                matrices[Lib.Str(n,"id")]=world;
                if(Lib.Str(n,"kind")=="mesh")foreach(object point in Lib.Arr(n["points_mm"])) {
                    var p=Vec(point);all.Add(new[]{world[0]*p[0]+world[4]*p[1]+world[8]*p[2]+world[12],world[1]*p[0]+world[5]*p[1]+world[9]*p[2]+world[13],world[2]*p[0]+world[6]*p[1]+world[10]*p[2]+world[14]});
                }
            }
            if(all.Count==0)throw new LibraryFault("test_failed","Empty geometry");
            foreach(string key in new[]{"min","max"}) {
                var value=Vec(expected[key]);for(int i=0;i<3;i++){double actual=key=="min"?all.Min(p=>p[i]):all.Max(p=>p[i]);if(Math.Abs(actual-value[i])>0.001)throw new LibraryFault("test_failed","Independent bounds mismatch");}
            }
        }
        void MarkSubmitted(string jobId,Dictionary<string,object> fields) {
            fields["library_job_id"]=jobId;
            lock(gate){var j=Record("jobs",jobId);j["submitted"]=true;j["native_request"]=fields;WriteRecord("jobs",jobId,j);}
            UpdateJob(jobId,"running","native_wait","unknown");
        }
        bool NativeResult(string jobId,Dictionary<string,object> response) {
            var result=Lib.Get(response,"result") as Dictionary<string,object>;
            if(result!=null&&Lib.Str(result,"library_job_id")!=jobId) {
                UpdateJob(jobId,"outcome_unknown","reconcile","unknown",null,Lib.Map("code","native_correlation_mismatch","message","Command history belongs to another library job; never reapply automatically"));return false;
            }
            if(result==null&&new[]{"authority_or_model_mismatch","model_mismatch","command_id_conflict","command_out_of_order","invalid_command_id","controller_busy","busy","request_expired","command_unavailable","unknown_method"}.Contains(Lib.Str(response,"status"))) {
                UpdateJob(jobId,"failed","submit","none",null,response);return false;
            }
            if(result!=null&&new[]{"completed","preview"}.Contains(Lib.Str(result,"state"))) {
                var data=Lib.Get(result,"data");bool verifying=Lib.Bool(Lib.Obj(Record("jobs",jobId)["native_request"]),"verify_only");UpdateJob(jobId,"succeeded","native_wait",verifying?"none":"model_applied",data);return true;
            }
            bool unknown=result==null||Lib.Str(result,"state")=="unknown";
            UpdateJob(jobId,unknown?"outcome_unknown":"failed",unknown?"reconcile":"native_wait",unknown?"unknown":"model_rollback_verified",null,response);return false;
        }
        async Task Apply(string jobId,Dictionary<string,object> a,NativeCall native,CancellationToken token) {
            if(native==null)throw new LibraryFault("instance_not_found","No connected model");
            Dictionary<string,object> record;lock(gate)record=Record("plans",Lib.Str(a,"plan_id"));
            token.ThrowIfCancellationRequested();var bindings=Lib.Obj(record["bindings"]);
            var fields=Lib.Map("session_id",a["session_id"],"model_id",a["model_id"],"expected_context",a["expected_context"],"command_id",a["command_id"],
                "plans",new object[]{record["plan"]},"bindings",bindings,"fingerprints",record["fingerprints"],"verify_only",false);
            MarkSubmitted(jobId,fields);
            var result=await native("apply_library_plan",fields,CancellationToken.None).ConfigureAwait(false);
            NativeResult(jobId,result);
        }
        async Task<object> Job(Dictionary<string,object> a,NativeCall native) {
            string id=Lib.Str(a,"job_id");var mode=Lib.Str(a,"action");Dictionary<string,object> j;
            lock(gate) {
                j=Record("jobs",id);
                if(mode=="cancel") {CancellationTokenSource c;if(!Lib.Bool(j,"submitted")&&cancellations.TryGetValue(id,out c))c.Cancel();return Success(Lib.Map("job_id",id,"cancel_requested",!Lib.Bool(j,"submitted"),"submitted",j["submitted"]));}
            }
            if(Lib.Str(j,"state")=="outcome_unknown"&&native!=null&&j.ContainsKey("native_request")) {
                var fields=Lib.Obj(j["native_request"]);
                try {var response=await native("get_command_result",Lib.Map("session_id",fields["session_id"],"model_id",fields["model_id"],"command_id",fields["command_id"]),CancellationToken.None).ConfigureAwait(false);NativeResult(id,response);}catch(Exception){ }
            }
            int wait=Lib.Int(a,"wait_ms",0,0,30000);var watch=System.Diagnostics.Stopwatch.StartNew();
            while(wait>0&&watch.ElapsedMilliseconds<wait) {
                lock(gate){j=Record("jobs",id);}if(!new[]{"running","queued"}.Contains(Lib.Str(j,"state")))break;
                await Task.Delay(50).ConfigureAwait(false);
            }
            lock(gate) {
                j=Record("jobs",id);j.Remove("arguments");j.Remove("native_request");
                int cursor=Lib.Int(a,"cursor",0,0,1000000);var events=Lib.Arr(j["events"]);j["events"]=events.Cast<object>().Skip(cursor).ToArray();j["next_cursor"]=events.Count;
                return Success(j,Lib.Str(j,"effect"));
            }
        }
    }
}
