using System;
using System.IO;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace SketchUpPipeProbe
{
    public sealed partial class LibraryService : IDisposable
    {
        readonly object gate=new object();
        readonly string root;
        Dictionary<string,object> state;
        long sequence;
        readonly Dictionary<string,CancellationTokenSource> cancellations=new Dictionary<string,CancellationTokenSource>();
        readonly CancellationTokenSource lifetime=new CancellationTokenSource();
        public delegate Task<Dictionary<string,object>> NativeCall(string method,Dictionary<string,object> fields,CancellationToken token);
        public LibraryService(string folder=null) {
#if PROBE_TEST
            folder=folder??Environment.GetEnvironmentVariable("SUPIPE_LIBRARY_ROOT")??Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"test-library-"+System.Diagnostics.Process.GetCurrentProcess().Id);
#endif
            root=Path.GetFullPath(folder??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"SketchUpCodexMcp","Library"));
            foreach(string d in new[]{"commits","revisions","receipts","jobs","plans","transfers"})Directory.CreateDirectory(Path.Combine(root,d));
            var commits=Directory.GetFiles(Path.Combine(root,"commits"),"*.json").OrderByDescending(x=>x,StringComparer.Ordinal);
            foreach(string path in commits)try {
                var candidate=Lib.Obj(Lib.Read(path));state=Lib.Obj(candidate["state"]);sequence=Convert.ToInt64(candidate["sequence"]);break;
            }catch(Exception){ }
            if(state==null) {
                state=Lib.Map("catalog",0,"libraries",Lib.Map("user",Lib.Map("title","내 기법 라이브러리","read_only",false,"techniques",Lib.Map())));
                Commit();
            }
            foreach(string path in Directory.GetFiles(Path.Combine(root,"jobs"),"*.json")) {
                var job=Lib.Obj(Lib.Read(path));
                if(new[]{"queued","running"}.Contains(Lib.Str(job,"state"))) {
                    bool submitted=Lib.Bool(job,"submitted");
                    job["state"]=submitted?"outcome_unknown":"failed";
                    job["error"]=Lib.Map("code",submitted?"outcome_unknown":"interrupted_before_submit","message","Probe restarted; inspect saved job/native command mapping");
                    job["effect"]=submitted?"unknown":"none";WriteRecord("jobs",Lib.Str(job,"job_id"),job);
                }
            }
            InitWorkspaces();
        }
        string RecordPath(string dir,string id) {
            Guid guid;if(!Guid.TryParseExact(id,"D",out guid))throw new LibraryFault("input_invalid","Expected UUID");
            return Path.Combine(root,dir,id+".json");
        }
        void WriteRecord(string dir,string id,object value) {Lib.Atomic(RecordPath(dir,id),value);}
        Dictionary<string,object> Record(string dir,string id) {
            string p=RecordPath(dir,id);if(!File.Exists(p))throw new LibraryFault(dir=="jobs"?"job_not_found":"record_not_found","Unknown "+dir+" record");
            return Lib.Obj(Lib.Read(p));
        }
        void ChangeState(Action change,bool catalog=false) {
            var before=Lib.Obj(Lib.Clone(state));
            try {change();if(catalog)state["catalog"]=Convert.ToInt64(state["catalog"])+1;Commit();}
            catch {state=before;throw;}
        }
        void Commit() {
            long next=sequence+1;
            var record=Lib.Map("sequence",next,"state",state);
            Lib.Atomic(Path.Combine(root,"commits",next.ToString("D20")+"-"+Guid.NewGuid().ToString("N")+".json"),record);
            sequence=next;
        }
        Dictionary<string,object> Libraries {get {return Lib.Obj(state["libraries"]);}}
        Dictionary<string,object> Library(string id) {
            object v;if(!Libraries.TryGetValue(id,out v))throw new LibraryFault("library_not_found","Unknown library_id");
            return Lib.Obj(v);
        }
        Dictionary<string,object> Techniques(string id) {return Lib.Obj(Library(id)["techniques"]);}
        Dictionary<string,object> Technique(string library,string id) {
            object v;if(!Techniques(library).TryGetValue(id,out v))throw new LibraryFault("technique_not_found","Technique is not registered");
            return Lib.Obj(v);
        }
        void Writable(string id) {if(Lib.Bool(Library(id),"read_only"))throw new LibraryFault("library_read_only","Library is read-only");}
        string LibraryId(Dictionary<string,object> a) {return Lib.Str(a,"library_id","user");}
        string TechniqueId(Dictionary<string,object> a) {return Lib.Id(a,"technique_id",Lib.TechniquePattern);}
        Dictionary<string,object> Ref(string library,string id,string revision) {return Lib.Map("library_id",library,"technique_id",id,"revision",revision);}
        string PickRevision(Dictionary<string,object> a,Dictionary<string,object> tech) {
            string rev=Lib.Str(a,"revision",Lib.Str(tech,"active",Lib.Str(tech,"head","")));
            if(rev=="")rev=Lib.Str(tech,"head");
            if(!Lib.Obj(tech["revisions"]).ContainsKey(rev))throw new LibraryFault("revision_not_found","Unknown pinned revision");
            return rev;
        }
        string RevisionDir(string rev) {
            if(!System.Text.RegularExpressions.Regex.IsMatch(rev,"\\A"+Lib.RevisionPattern+"\\z"))throw new LibraryFault("input_invalid","Invalid revision");
            return Path.Combine(root,"revisions",rev.Substring(7));
        }
        Dictionary<string,string> ReadFiles(string rev) {
            string dir=RevisionDir(rev);if(!Directory.Exists(dir))throw new LibraryFault("revision_missing","Revision files are missing");
            var files=new Dictionary<string,string>(StringComparer.Ordinal);
            var directories=new Stack<string>();directories.Push(dir);
            while(directories.Count>0) {
                string current=directories.Pop();
                if((File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0)throw new LibraryFault("revision_corrupt","Linked revision directories are not allowed");
                foreach(string child in Directory.GetDirectories(current))directories.Push(child);
                foreach(string file in Directory.GetFiles(current)) {
                    if((File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0||new FileInfo(file).Length>65536||files.Count>=32)throw new LibraryFault("revision_corrupt","Stored file is linked or exceeds its budget");
                    string name=FileName(file.Substring(dir.Length+1).Replace('\\','/'));
                    files.Add(name,File.ReadAllText(file,Lib.Utf8));
                }
            }
            if(Lib.Revision(files)!=rev)throw new LibraryFault("revision_corrupt","Stored revision content has changed");
            return files;
        }
        static string FileName(string p) {
            if(!new[]{"manifest.json","inputs.schema.json","technique.js","tests.json","presets.json"}.Contains(p)&&
               !System.Text.RegularExpressions.Regex.IsMatch(p,"\\Ahelpers/[a-z][a-z0-9_-]{0,47}\\.js\\z"))
                throw new LibraryFault("package_path_invalid","Unsupported package file: "+p);
            return p;
        }
        Dictionary<string,string> ParseFiles(object raw) {
            var files=new Dictionary<string,string>(StringComparer.Ordinal);int bytes=0;
            foreach(var p in Lib.Obj(raw)) {
                string name=FileName(p.Key);string text=p.Value as string;
                if(text==null||(text.Length>0&&text[0]=='\ufeff'))throw new LibraryFault("input_invalid","Expected UTF-8 text without BOM");
                text=text.Replace("\r\n","\n");
                int size=Lib.Utf8.GetByteCount(text);bytes+=size;
                if(size>65536||bytes>1048576||files.Count>=32)throw new LibraryFault("budget_exceeded","Technique file/size budget exceeded");
                files.Add(name,text);
            }return files;
        }
        Dictionary<string,object> ValidateFiles(Dictionary<string,string> files) {
            foreach(string f in new[]{"manifest.json","inputs.schema.json","technique.js","tests.json"})
                if(!files.ContainsKey(f))throw new LibraryFault("package_invalid","Missing "+f);
            var manifest=Lib.Parse(files["manifest.json"]);
            LibrarySchema.Validate(LibrarySchema.Bundled("manifest"),manifest);
            string kind=Lib.Str(manifest,"kind");
            if((kind=="generator")!=(Lib.Str(manifest,"output")=="sketchup-plan/1"))throw new LibraryFault("manifest_invalid","Kind/output contract mismatch");
            var inputs=Lib.Parse(files["inputs.schema.json"]);LibrarySchema.CheckInput(inputs);
            var tests=Lib.Parse(files["tests.json"]);LibrarySchema.Validate(LibrarySchema.Bundled("tests"),tests);
            var helperNames=new HashSet<string>();var helperPaths=new HashSet<string>();
            foreach(object raw in Lib.Arr(Lib.Get(manifest,"helpers",new object[0]))) {
                var h=Lib.Obj(raw);if(!helperNames.Add(Lib.Str(h,"alias"))||!helperPaths.Add(Lib.Str(h,"path"))||!files.ContainsKey(Lib.Str(h,"path")))throw new LibraryFault("manifest_invalid","Duplicate or missing helper");
            }
            foreach(string p in files.Keys.Where(p=>p.StartsWith("helpers/")))if(!helperPaths.Contains(p))throw new LibraryFault("manifest_invalid","Undeclared helper: "+p);
            if(Lib.Arr(manifest["dependencies"]).Cast<object>().Select(x=>Lib.Str(Lib.Obj(x),"alias")).Distinct().Count()!=Lib.Arr(manifest["dependencies"]).Count)throw new LibraryFault("dependency_invalid","Duplicate dependency alias");
            if(files.ContainsKey("presets.json")) {
                foreach(var p in Lib.Parse(files["presets.json"])) {
                    if(p.Key.Length>64)throw new LibraryFault("preset_invalid","Preset name too long");
                    LibrarySchema.Validate(inputs,LibrarySchema.Normalize(inputs,p.Value));
                }
            }
            return manifest;
        }
        void StoreFiles(string revision,Dictionary<string,string> files) {
            string dir=RevisionDir(revision);
            if(Directory.Exists(dir)) {ReadFiles(revision);return;}
            string tmp=Path.Combine(root,"revisions",".tmp-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(tmp);
            foreach(var p in files) {
                string path=Path.Combine(tmp,p.Key.Replace('/',Path.DirectorySeparatorChar));Directory.CreateDirectory(Path.GetDirectoryName(path));
                byte[] b=Lib.Utf8.GetBytes(p.Value);using(var f=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)){f.Write(b,0,b.Length);f.Flush(true);}
            }
            Directory.Move(tmp,dir);
        }
        object Receipt(string id,string signature) {
            string path=RecordPath("receipts",id);
            Dictionary<string,object> receipt=null;
            if(File.Exists(path))receipt=Lib.Obj(Lib.Read(path));
            else foreach(string c in Directory.GetFiles(Path.Combine(root,"commits"),"*.json").OrderByDescending(x=>x,StringComparer.Ordinal)) {
                var image=Lib.Obj(Lib.Read(c));var s=Lib.Obj(image["state"]);var r=Lib.Get(s,"last_receipt") as Dictionary<string,object>;
                if(r!=null&&Lib.Str(r,"request_id")==id){receipt=r;break;}
            }
            if(receipt==null)return null;
            if(Lib.Str(receipt,"signature")!=signature)throw new LibraryFault("request_id_conflict","Same request_id with different arguments");
            return Lib.Clone(receipt["result"]);
        }
        object Mutate(string tool,Dictionary<string,object> a,Func<object> change,bool catalog=true) {
            string id=Lib.Str(a,"request_id");RecordPath("receipts",id);
            string signature=Lib.Digest(Lib.Map("tool",tool,"arguments",a));var previous=Receipt(id,signature);if(previous!=null)return previous;
            var before=Lib.Obj(Lib.Clone(state));
            try {
                var result=change();if(catalog)state["catalog"]=Convert.ToInt64(state["catalog"])+1;
                var receipt=Lib.Map("request_id",id,"signature",signature,"result",result,"created_at",DateTime.UtcNow.ToString("o"));
                state["last_receipt"]=receipt;Commit();
                try {WriteRecord("receipts",id,receipt);}catch(Exception){ /* Optional receipt cache; the committed journal remains authoritative. */ }
                return result;
            }catch {state=before;throw;}
        }
        static object Success(object data,string effect="none") {return Lib.Map("ok",true,"effect",effect,"data",data,"warnings",new object[0]);}
        object Save(Dictionary<string,object> a) {
            var saved=Mutate("save",a,()=>{
                string library=LibraryId(a),id=TechniqueId(a);Writable(library);
                var files=ParseFiles(a["files"]);var m=ValidateFiles(files);
                if(Lib.Str(m,"id")!=id)throw new LibraryFault("manifest_invalid","Manifest id differs from technique_id");
                var ts=Techniques(library);object v;var exists=ts.TryGetValue(id,out v);var tech=exists?Lib.Obj(v):null;
                object expected=a["base_revision"];string head=tech==null?"":Lib.Str(tech,"head");
                if(expected==null?exists:!(expected is string)||head!=(string)expected)throw new LibraryFault(exists?"revision_conflict":"revision_not_found","Read the current head before saving");
                string revision=Lib.Revision(files);bool noChange=exists&&head==revision;
                CheckQuota(library,revision,files.Values.Sum(x=>Lib.Utf8.GetByteCount(x)));
                StoreFiles(revision,files);
                if(!exists)ts[id]=tech=Lib.Map("head","","active","","archived",false,"revisions",Lib.Map(),"tags",Lib.Map());
                var revisions=Lib.Obj(tech["revisions"]);
                if(!revisions.ContainsKey(revision))revisions[revision]=Lib.Map("manifest",m,"change_summary",Lib.Str(a,"change_summary"),"parent_revision",head,"created_at",DateTime.UtcNow.ToString("o"),"byte_count",files.Values.Sum(x=>Lib.Utf8.GetByteCount(x)),"derived_from",Lib.Get(a,"derived_from"),"validation",Lib.Map("offline","not_run","native","not_run"));
                tech["head"]=revision;
                return Success(Lib.Map("technique_ref",Ref(library,id,revision),"head",revision,"active",tech["active"],"no_change",noChange),"library_changed");
            });
            var data=Lib.Obj(Lib.Obj(saved)["data"]);var reference=Lib.Obj(data["technique_ref"]);
            string lib=Lib.Str(reference,"library_id"),techniqueName=Lib.Str(reference,"technique_id"),revisionId=Lib.Str(reference,"revision");
            if(Lib.Str(Technique(lib,techniqueName),"head")==revisionId)try {SyncWorkspace(lib,techniqueName,revisionId,a["base_revision"]);}catch(Exception error){try {WorkspaceStatus(lib,techniqueName,Lib.Map("state","error","error",Lib.Obj(Lib.Error(error))["error"]));}catch(Exception){} }
            return saved;
        }
        object Manage(Dictionary<string,object> a) {
            return Mutate("manage",a,()=>{
                string action=Lib.Str(a,"action"),library=LibraryId(a);Writable(library);
                if(action=="create_library") {
                    if(Lib.Str(a,"scope","user")!="user")throw new LibraryFault("scope_unavailable","Only the configured user root is available");
                    string created="lib-"+Guid.NewGuid().ToString("N");
                    Libraries[created]=Lib.Map("title",Lib.Str(a,"title"),"summary",Lib.Str(a,"summary",""),"read_only",false,"techniques",Lib.Map());
                    return Success(Lib.Map("library_id",created,"read_only",false),"library_changed");
                }
                if(action=="configure_library") {Library(library)["update_policy"]=Lib.Str(a,"update_policy");return Success(Lib.Map("library_id",library,"update_policy",a["update_policy"]),"library_changed");}
                string id=TechniqueId(a);var t=Technique(library,id);
                if(!a.ContainsKey("expected_active_revision")||!Object.Equals(a["expected_active_revision"],Lib.Str(t,"active")==""?null:t["active"]))throw new LibraryFault("active_conflict","Active revision changed");
                if(action=="archive"||action=="restore"){t["archived"]=action=="archive";return Success(Lib.Map("technique_id",id,"archived",t["archived"],"head",t["head"],"active",t["active"]),"library_changed");}
                if(Lib.Bool(t,"archived"))throw new LibraryFault("technique_archived","Restore the technique first");
                string rev=PickRevision(a,t);
                if(action=="tag") {
                    string label=Lib.Id(a,"label","[0-9]+\\.[0-9]+\\.[0-9]+");var tags=Lib.Obj(t["tags"]);
                    if(tags.ContainsKey(label)&&!tags[label].Equals(rev))throw new LibraryFault("label_conflict","Release label already refers to another revision");
                    tags[label]=rev;
                }else {
                    var validation=Lib.Obj(Lib.Obj(Lib.Obj(t["revisions"])[rev])["validation"]);
                    if(Lib.Str(validation,"offline")!="passed")throw new LibraryFault("verification_required","Run offline verify for this revision first");
                    t["active"]=rev;
                }
                return Success(Lib.Map("technique_ref",Ref(library,id,rev),"active",t["active"]),"library_changed");
            });
        }
        Dictionary<string,object> Summary(string library,string id,Dictionary<string,object> t) {
            string rev=Lib.Str(t,"active");if(rev=="")rev=Lib.Str(t,"head");
            if(rev=="")rev=Lib.Obj(t["revisions"]).Keys.OrderBy(x=>x,StringComparer.Ordinal).First();
            var r=Lib.Obj(Lib.Obj(t["revisions"])[rev]);var m=Lib.Obj(r["manifest"]);
            return Lib.Map("technique_ref",Ref(library,id,rev),"title",m["title"],"summary",m["summary"],"kind",m["kind"],
                "keywords",Lib.Get(m,"keywords",new object[0]),"active",t["active"],"head",t["head"],"archived",t["archived"],
                "draft_available",!Object.Equals(t["head"],t["active"]),"validation",r["validation"],
                "compatibility","not_checked","requires",m["requires"]);
        }
        object List(Dictionary<string,object> a,string[] supported=null) {
            var entries=new List<object>();string kind=Lib.Str(a,"kind","techniques");
            if(kind=="libraries")foreach(var p in Libraries.OrderBy(p=>p.Key,StringComparer.Ordinal))
                entries.Add(Lib.Map("library_id",p.Key,"title",Lib.Obj(p.Value)["title"],"read_only",Lib.Obj(p.Value)["read_only"],"update_policy",Lib.Str(Lib.Obj(p.Value),"update_policy","draft_only")));
            else {
                string query=Lib.Str(a,"query","");string filter=Lib.Str(a,"state","active");
                foreach(var l in Libraries.OrderBy(p=>p.Key,StringComparer.Ordinal)) {
                    if(a.ContainsKey("library_id")&&l.Key!=LibraryId(a))continue;
                    foreach(var p in Techniques(l.Key).OrderBy(p=>p.Key,StringComparer.Ordinal)) {
                        var t=Lib.Obj(p.Value);if(filter=="active"&&(Lib.Bool(t,"archived")||Lib.Str(t,"active")==""))continue;
                        var item=Summary(l.Key,p.Key,t);
                        if(supported!=null) {
                            var missing=Lib.Arr(item["requires"]).Cast<string>().Where(c=>!supported.Contains(c)).ToArray();
                            item["compatibility"]=Lib.Map("supported",missing.Length==0,"missing",missing);
                            if(missing.Length>0)continue;
                        }
                        if(query!=""&&(p.Key+" "+Lib.Json(item)).IndexOf(query,StringComparison.OrdinalIgnoreCase)<0)continue;
                        if(a.ContainsKey("keywords")&&!Lib.Arr(a["keywords"]).Cast<string>().All(k=>Lib.Json(item).IndexOf(k,StringComparison.OrdinalIgnoreCase)>=0))continue;
                        entries.Add(item);
                    }
                }
            }
            long catalog=Convert.ToInt64(state["catalog"]);int offset=0;
            var filterArgs=new Dictionary<string,object>(a);filterArgs.Remove("cursor");filterArgs.Remove("limit");string filterHash=Lib.Digest(filterArgs);
            if(a.ContainsKey("cursor")) {
                Dictionary<string,object> c;try {c=Lib.Parse(Lib.Utf8.GetString(Convert.FromBase64String(Lib.Str(a,"cursor"))));}catch(Exception){throw new LibraryFault("input_invalid","Invalid cursor");}
                if(Convert.ToInt64(c["catalog"])!=catalog||Lib.Str(c,"filter")!=filterHash)throw new LibraryFault("catalog_changed","Restart list with the same filter");
                offset=Lib.Int(c,"offset",0,0,1000000);
            }
            int limit=Lib.Int(a,"limit",10,1,25);var page=new List<object>();
            while(offset<entries.Count&&page.Count<limit) {
                page.Add(entries[offset]);if(Lib.Utf8.GetByteCount(Lib.Json(page))>24000){page.RemoveAt(page.Count-1);break;}++offset;
            }
            string next=offset<entries.Count?Convert.ToBase64String(Lib.Utf8.GetBytes(Lib.Json(Lib.Map("catalog",catalog,"offset",offset,"filter",filterHash)))):null;
            return Success(Lib.Map("items",page,"catalog_revision",catalog,"next_cursor",next,"truncated",next!=null,"engine","Jint 3.1.6 / probe-js/1"));
        }
        object Get(Dictionary<string,object> a) {
            if(Lib.Str(a,"kind","technique")=="authoring") {
                var authoringSections=Lib.Arr(Lib.Get(a,"sections",new object[]{"profile","example"})).Cast<string>().ToArray();var data=Lib.Map("format_version","probe-technique/1");
                if(authoringSections.Contains("profile"))data["profile"]=Lib.Map(
                    "entrypoint","function build(ctx) returns a closed geometry plan or bounded report",
                    "context",new[]{"ctx.params (normalized/frozen)","ctx.inputs (declared snapshots)","ctx.call(alias, params) (pinned dependencies)","ctx.helper(alias, params)"},
                    "files",new[]{"manifest.json","inputs.schema.json","technique.js","tests.json"},
                    "units","mm; X width, Y depth, Z height; origin/materials/current model are separate bindings",
                    "schema_profile","Closed objects, bounded arrays/text, numeric/boolean types, enums/constants/defaults and nonrecursive local $defs references. No remote schema resolution or unsupported keywords.",
                    "restrictions","Pure synchronous JS, no CLR/files/network/clock/random; one worker budget shared by dependencies. build result checked by Probe and native kernel.",
                    "workflow",new[]{"save with base_revision=null","run verify; optional activate_if_passed + expected_active_revision=null","run plan with pinned revision, params and optional model bindings","run apply with plan_id/hash and fresh command_id; poll library_job"},
                    "capabilities",Capabilities);
                if(authoringSections.Contains("example"))data["files"]=new[]{"manifest.json","inputs.schema.json","technique.js","tests.json"}.ToDictionary(name=>name,name=>(object)Lib.Resource("example."+name));
                if(authoringSections.Contains("window_example"))data["window_files"]=new[]{"manifest.json","inputs.schema.json","technique.js","tests.json"}.ToDictionary(name=>name,name=>(object)Lib.Resource("window."+name));
                foreach(string name in new[]{"manifest","plan","report","tests","package"})if(authoringSections.Contains(name+"_schema"))data[name+"_schema"]=LibrarySchema.Bundled(name);
                Lib.TextBudget(data,32768);return Success(data);
            }
            string library=LibraryId(a),id=TechniqueId(a);var t=Technique(library,id);string rev=PickRevision(a,t);var files=ReadFiles(rev);
            var sections=Lib.Arr(Lib.Get(a,"sections",new object[]{"contract","examples"})).Cast<string>().ToArray();
            var result=Lib.Map("technique_ref",Ref(library,id,rev),"head",t["head"],"active",t["active"],"archived",t["archived"],"workspace_path",Workspace(library,id),"workspace_revision",t["head"],"workspace_status",ReadWorkspaceStatus(library,id));
            if(sections.Contains("contract")) {result["manifest"]=Lib.Parse(files["manifest.json"]);result["inputs_schema"]=Lib.Parse(files["inputs.schema.json"]);}
            if(sections.Contains("examples"))result["examples"]=Lib.Arr(Lib.Parse(files["tests.json"])["cases"]).Cast<object>().Take(3).ToArray();
            if(sections.Contains("tests"))result["tests"]=Lib.Parse(files["tests.json"]);
            if(sections.Contains("history")) {
                int offset=Lib.Int(a,"history_offset",0,0,1000000),count=Lib.Int(a,"history_limit",25,1,25);
                var history=Lib.Obj(t["revisions"]).OrderByDescending(p=>Lib.Str(Lib.Obj(p.Value),"created_at")).ToArray();
                result["history"]=Lib.Map("items",history.Skip(offset).Take(count).Select(p=>Lib.Map("revision",p.Key,"change_summary",Lib.Obj(p.Value)["change_summary"],"validation",Lib.Obj(p.Value)["validation"])).ToArray(),
                    "next_offset",offset+count<history.Length?(object)(offset+count):null);
            }
            if(sections.Contains("source")) {
                var page=Lib.Obj(Lib.Get(a,"source_page",Lib.Map("file","technique.js","start_line",1,"line_count",50)));
                string file=FileName(Lib.Str(page,"file"));if(!files.ContainsKey(file))throw new LibraryFault("file_not_found","Unknown technique file");
                int start=Lib.Int(page,"start_line",1,1,100000),count=Lib.Int(page,"line_count",50,1,100);
                var lines=files[file].Split('\n');var selected=lines.Skip(start-1).Take(count).ToArray();byte[] bytes=Lib.Utf8.GetBytes(files[file]);
                if(page.ContainsKey("byte_offset")||Lib.Utf8.GetByteCount(Lib.Json(selected))>16000) {
                    int fallback=Math.Min(bytes.Length,Lib.Utf8.GetByteCount(String.Join("\n",lines.Take(start-1)))+(start>1?1:0));
                    int offset=Lib.Int(page,"byte_offset",fallback,0,bytes.Length),take=Math.Min(Lib.Int(page,"max_bytes",8192,1,8192),bytes.Length-offset);
                    result["source"]=Lib.Map("file",file,"file_hash",Lib.Hash(bytes),"format","utf8-base64","byte_offset",offset,"data_base64",Convert.ToBase64String(bytes,offset,take),"next_byte_offset",offset+take<bytes.Length?(object)(offset+take):null);
                }else
                    result["source"]=Lib.Map("file",file,"file_hash",Lib.Hash(bytes),"format","lines","start_line",start,"lines",selected,"next_line",start-1+selected.Length<lines.Length?(object)(start+selected.Length):null);
            }
            if(sections.Contains("diff")) {
                string before=Lib.Str(a,"base_revision"),after=Lib.Str(a,"target_revision");
                if(!Lib.Obj(t["revisions"]).ContainsKey(before)||!Lib.Obj(t["revisions"]).ContainsKey(after))throw new LibraryFault("revision_not_found","Diff revisions must belong to the requested technique");
                var left=ReadFiles(before);var right=ReadFiles(after);
                result["diff"]=left.Keys.Union(right.Keys).Where(k=>!left.ContainsKey(k)||!right.ContainsKey(k)||left[k]!=right[k]).Select(k=>Lib.Map("file",k,"before_hash",left.ContainsKey(k)?Lib.Hash(Lib.Utf8.GetBytes(left[k])):null,"after_hash",right.ContainsKey(k)?Lib.Hash(Lib.Utf8.GetBytes(right[k])):null)).ToArray();
            }
            Lib.TextBudget(result,32768);return Success(result);
        }
        public async Task<object> HandleAsync(string tool,Dictionary<string,object> args,NativeCall native=null) {
            try {
                LibraryCatalog.Validate(tool,args);
                if(tool=="sketchup_library_list"&&args.ContainsKey("compatible_with")) {
                    if(native==null)throw new LibraryFault("instance_not_found","Connected model required for compatibility filter");
                    var target=Lib.Obj(args["compatible_with"]);var reply=await native("get_state",target,lifetime.Token).ConfigureAwait(false);
                    if(!Lib.Bool(reply,"ok"))throw new LibraryFault("instance_not_found","Could not read target state");
                    var current=Lib.Obj(reply["state"]);if(Lib.Str(current,"model_id")!=Lib.Str(target,"model_id"))throw new LibraryFault("model_mismatch","Refresh model identity");
                    var supported=Lib.Arr(Lib.Get(current,"library_capabilities",new object[0])).Cast<string>().ToArray();
                    lock(gate)return List(args,supported);
                }
                if(tool=="sketchup_library_run")return await StartRun(args,native).ConfigureAwait(false);
                if(tool=="sketchup_library_job")return await Job(args,native).ConfigureAwait(false);
                lock(gate) {
                    switch(tool) {
                        case "sketchup_library_list":return List(args);
                        case "sketchup_library_get":return Get(args);
                        case "sketchup_library_save":return Save(args);
                        case "sketchup_library_manage":return Manage(args);
                        case "sketchup_library_transfer":return Transfer(args);
                        default:throw new LibraryFault("unknown_tool","Unknown library tool");
                    }
                }
            }catch(Exception error){return Lib.Error(error);}
        }
        public void Dispose() {if(watcher!=null)watcher.Dispose();lifetime.Cancel();lock(gate)foreach(var c in cancellations.Values)c.Cancel();}
    }
}
