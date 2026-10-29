using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Collections;
using System.Collections.Generic;

namespace SketchUpPipeProbe
{
    public sealed partial class LibraryService
    {
        string TransferBytes(string id,string suffix) {RecordPath("transfers",id);return Path.Combine(root,"transfers",id+suffix);}
        string Key(string id,string revision) {return id+"@"+revision;}
        Dictionary<string,object> Package(byte[] bytes) {
            if(bytes.Length>1048576)throw new LibraryFault("package_too_large","Archive exceeds 1 MiB");
            var content=new Dictionary<string,byte[]>(StringComparer.Ordinal);long expanded=0;
            using(var memory=new MemoryStream(bytes))
            using(var zip=new ZipArchive(memory,ZipArchiveMode.Read)) {
                if(zip.Entries.Count>2048)throw new LibraryFault("package_too_large","Too many archive entries");
                foreach(var e in zip.Entries) {
                    string path=e.FullName;
                    if(path.Length>256||path.IndexOf('\\')>=0||path.StartsWith("/")||path.Split('/').Any(s=>s==".."||s=="."||s=="")||
                       ((e.ExternalAttributes>>16)&0xf000)==0xa000||content.ContainsKey(path))throw new LibraryFault("package_path_invalid","Invalid/duplicate archive path");
                    expanded+=e.Length;if(expanded>4194304||e.Length>1048576)throw new LibraryFault("package_too_large","Expanded archive budget exceeded");
                    using(var stream=e.Open())using(var m=new MemoryStream()) {
                        byte[] buffer=new byte[8192];int n;while((n=stream.Read(buffer,0,buffer.Length))>0){m.Write(buffer,0,n);if(m.Length>e.Length||m.Length>1048576)throw new LibraryFault("package_too_large","Unbounded archive entry");}
                        content.Add(path,m.ToArray());
                    }
                }
            }
            if(!content.ContainsKey("package.json"))throw new LibraryFault("package_invalid","Missing package.json");
            var index=Lib.Parse(Lib.Utf8.GetString(content["package.json"]));
            if(Lib.Str(index,"format_version")!="probe-techpack/1")throw new LibraryFault("package_invalid","Unsupported package format");
            LibrarySchema.Validate(LibrarySchema.Bundled("package"),index);
            var entries=Lib.Arr(index["entries"]);var roots=Lib.Arr(index["roots"]);
            if(entries.Count<1||entries.Count>64||roots.Count<1||roots.Count>32)throw new LibraryFault("package_invalid","Invalid package entry count");
            var packs=Lib.Map();var used=new HashSet<string>(StringComparer.Ordinal){"package.json"};
            foreach(object raw in entries) {
                var e=Lib.Obj(raw);string id=Lib.Id(e,"technique_id",Lib.TechniquePattern),rev=Lib.Id(e,"revision",Lib.RevisionPattern);
                string key=Key(id,rev);if(packs.ContainsKey(key))throw new LibraryFault("package_invalid","Duplicate technique revision");
                string prefix="techniques/"+id+"/"+rev.Substring(7)+"/";
                if(Lib.Str(e,"path")!=prefix)throw new LibraryFault("package_path_invalid","Entry prefix does not match ID/revision");
                var files=new Dictionary<string,string>();
                foreach(var f in Lib.Obj(e["files"])) {
                    string file=FileName(f.Key),path=prefix+file;byte[] data;
                    if(!content.TryGetValue(path,out data))throw new LibraryFault("package_invalid","Missing declared file");
                    var meta=Lib.Obj(f.Value);
                    if(Convert.ToInt32(meta["bytes"])!=data.Length||Lib.Str(meta,"sha256")!=Lib.Hash(data))throw new LibraryFault("package_digest_mismatch","File digest mismatch");
                    files.Add(file,Lib.Utf8.GetString(data));used.Add(path);
                }
                files=ParseFiles(files.ToDictionary(p=>p.Key,p=>(object)p.Value));
                var manifest=ValidateFiles(files);
                if(Lib.Str(manifest,"id")!=id||Lib.Revision(files)!=rev)throw new LibraryFault("package_digest_mismatch","Technique revision mismatch");
                packs[key]=Lib.Map("entry",e,"manifest",manifest,"files",files);
            }
            if(used.Count!=content.Count)throw new LibraryFault("package_invalid","Undeclared archive file");
            var rootIds=new HashSet<string>();var rootKeys=new HashSet<string>();
            foreach(object raw in roots) {
                var r=Lib.Obj(raw);string id=Lib.Id(r,"technique_id",Lib.TechniquePattern),rev=Lib.Id(r,"revision",Lib.RevisionPattern);
                if(!rootIds.Add(id)||!rootKeys.Add(Key(id,rev))||!packs.ContainsKey(Key(id,rev)))throw new LibraryFault("package_invalid","Invalid representative selection");
            }
            var external=new HashSet<string>();
            foreach(var raw in packs.Values)foreach(object dep in Lib.Arr(Lib.Obj(Lib.Obj(raw)["manifest"])["dependencies"])) {
                var d=Lib.Obj(dep);string key=Key(Lib.Str(d,"technique_id"),Lib.Str(d,"revision"));
                if(!packs.ContainsKey(key))external.Add(key);
            }
            if(Lib.Bool(index,"self_contained")!=(external.Count==0)||!external.SetEquals(Lib.Arr(index["external_dependencies"]).Cast<string>()))
                throw new LibraryFault("package_invalid","Dependency completeness metadata does not match contents");
            return Lib.Map("index",index,"packs",packs);
        }
        Dictionary<string,string> PackageFiles(Dictionary<string,object> pack) {
            var direct=pack["files"] as Dictionary<string,string>;return direct??Lib.Obj(pack["files"]).ToDictionary(p=>p.Key,p=>(string)p.Value);
        }
        byte[] ExportBytes(Dictionary<string,object>a) {
            var packs=Lib.Map();var roots=new List<object>();var rootIds=new Dictionary<string,string>();
            bool dependencies=Lib.Bool(a,"include_dependencies",true);
            var missing=new HashSet<string>();var visiting=new HashSet<string>();
            Action<string,string,int> add=null;
            add=(id,rev,depth)=>{
                string key=Key(id,rev);if(visiting.Contains(key))throw new LibraryFault("dependency_cycle","Cyclic dependency");
                if(packs.ContainsKey(key))return;
                if(depth>8||packs.Count>=64)throw new LibraryFault("package_too_large","Too many package revisions");
                if(!Libraries.Any(l=>Techniques(l.Key).ContainsKey(id)&&Lib.Obj(Lib.Obj(Techniques(l.Key)[id])["revisions"]).ContainsKey(rev)))throw new LibraryFault("dependency_missing","Missing pinned revision: "+key);
                var files=ReadFiles(rev);var m=ValidateFiles(files);if(Lib.Str(m,"id")!=id)throw new LibraryFault("revision_not_found","Revision identity mismatch");
                visiting.Add(key);
                foreach(object raw in Lib.Arr(m["dependencies"])) {
                    var d=Lib.Obj(raw);string childId=Lib.Str(d,"technique_id"),childRev=Lib.Str(d,"revision");
                    if(dependencies)add(childId,childRev,depth+1);else missing.Add(Key(childId,childRev));
                }
                visiting.Remove(key);if(packs.Count>=64)throw new LibraryFault("package_too_large","Too many package revisions");packs[key]=Lib.Map("id",id,"revision",rev,"files",files);
            };
            foreach(object raw in Lib.Arr(a["selections"])) {
                var selection=Lib.Obj(raw);string lib=LibraryId(selection),id=TechniqueId(selection),rev=Lib.Str(selection,"revision");
                var t=Technique(lib,id);PickRevision(selection,t);
                if(rootIds.ContainsKey(id)) {if(rootIds[id]!=rev)throw new LibraryFault("selection_conflict","Choose one representative revision per technique");continue;}
                rootIds[id]=rev;roots.Add(Lib.Map("technique_id",id,"revision",rev));add(id,rev,0);
            }
            var entries=new List<object>();var info=Lib.Obj(a["package_info"]);
            var index=Lib.Map("format_version","probe-techpack/1","package_id",Guid.NewGuid().ToString(),"title",Lib.Str(info,"title"),"summary",Lib.Str(info,"summary",""),
                "roots",roots,"entries",entries,"external_dependencies",missing.Where(k=>!packs.ContainsKey(k)).ToArray(),
                "self_contained",missing.All(k=>packs.ContainsKey(k)));
            using(var memory=new MemoryStream()) {
                long expanded=0;
                using(var zip=new ZipArchive(memory,ZipArchiveMode.Create,true)) {
                    foreach(var raw in packs.OrderBy(p=>p.Key,StringComparer.Ordinal)) {
                        var pack=Lib.Obj(raw.Value);var files=PackageFiles(pack);
                        string prefix="techniques/"+pack["id"]+"/"+((string)pack["revision"]).Substring(7)+"/";
                        var hashes=Lib.Map();
                        foreach(var p in files.OrderBy(p=>p.Key,StringComparer.Ordinal)) {
                            byte[] data=Lib.Utf8.GetBytes(p.Value);expanded+=data.Length;if(expanded>4194304)throw new LibraryFault("package_too_large","Expanded package exceeds 4 MiB");
                            hashes[p.Key]=Lib.Map("bytes",data.Length,"sha256",Lib.Hash(data));
                            var e=zip.CreateEntry(prefix+p.Key,CompressionLevel.Optimal);using(var stream=e.Open())stream.Write(data,0,data.Length);
                        }
                        entries.Add(Lib.Map("technique_id",pack["id"],"revision",pack["revision"],"path",prefix,"files",hashes));
                    }
                    byte[] meta=Lib.Utf8.GetBytes(Lib.Json(index));var entry=zip.CreateEntry("package.json",CompressionLevel.Optimal);using(var stream=entry.Open())stream.Write(meta,0,meta.Length);
                }
                byte[] result=memory.ToArray();if(result.Length>1048576)throw new LibraryFault("package_too_large","Compressed package exceeds 1 MiB");Package(result);return result;
            }
        }
        Dictionary<string,object> Uploaded(string id) {
            var meta=Record("transfers",id);
            if(Lib.Str(meta,"kind")!="upload")throw new LibraryFault("input_invalid","Not an import upload");
            if(DateTime.Parse(Lib.Str(meta,"expires_at"),null,System.Globalization.DateTimeStyles.RoundtripKind)<DateTime.UtcNow)throw new LibraryFault("upload_expired","Upload expired");
            byte[] bytes=File.ReadAllBytes(TransferBytes(id,".bin"));
            if(bytes.Length!=Convert.ToInt32(meta["total_bytes"]))throw new LibraryFault("upload_incomplete","Upload is incomplete");
            if("sha256:"+Lib.Hash(bytes)!=Lib.Str(meta,"digest"))throw new LibraryFault("package_digest_mismatch","Archive hash mismatch");
            return Package(bytes);
        }
        object Transfer(Dictionary<string,object>a) {
            string action=Lib.Str(a,"action");
            if(action=="export") {
                byte[] bytes=ExportBytes(a);string id=Guid.NewGuid().ToString();
                File.WriteAllBytes(TransferBytes(id,".probe-techpack"),bytes);
                WriteRecord("transfers",id,Lib.Map("kind","export","digest","sha256:"+Lib.Hash(bytes),"total_bytes",bytes.Length));
                return Success(Lib.Map("bundle_id",id,"digest","sha256:"+Lib.Hash(bytes),"total_bytes",bytes.Length,"file_name",id+".probe-techpack","local_path",TransferBytes(id,".probe-techpack")));
            }
            if(action=="read_export") {
                string id=Lib.Str(a,"bundle_id");var meta=Record("transfers",id);if(Lib.Str(meta,"kind")!="export")throw new LibraryFault("input_invalid","Not an export");
                byte[] bytes=File.ReadAllBytes(TransferBytes(id,".probe-techpack"));int start=Lib.Int(a,"offset",0,0,bytes.Length),count=Math.Min(Lib.Int(a,"max_bytes",16384,1,16384),bytes.Length-start);
                return Success(Lib.Map("data_base64",Convert.ToBase64String(bytes,start,count),"digest",meta["digest"],"total_bytes",bytes.Length,"next_offset",start+count<bytes.Length?(object)(start+count):null));
            }
            if(action=="open_import")return Mutate("open_import",a,()=>{
                string id=Guid.NewGuid().ToString();File.WriteAllBytes(TransferBytes(id,".bin"),new byte[0]);
                WriteRecord("transfers",id,Lib.Map("kind","upload","total_bytes",a["total_bytes"],"digest",a["digest"],"expires_at",DateTime.UtcNow.AddMinutes(10).ToString("o")));
                return Success(Lib.Map("upload_id",id,"chunk_bytes",16384,"expires_at",DateTime.UtcNow.AddMinutes(10).ToString("o")));
            },false);
            if(action=="write_chunk") {
                string id=Lib.Str(a,"upload_id");var meta=Record("transfers",id);if(Lib.Str(meta,"kind")!="upload")throw new LibraryFault("input_invalid","Not an upload");
                if(DateTime.Parse(Lib.Str(meta,"expires_at"),null,System.Globalization.DateTimeStyles.RoundtripKind)<DateTime.UtcNow)throw new LibraryFault("upload_expired","Upload expired");
                byte[] bytes;try{bytes=Convert.FromBase64String(Lib.Str(a,"data_base64"));}catch(FormatException){throw new LibraryFault("input_invalid","Invalid base64");}
                int offset=Lib.Int(a,"offset",0,0,1048576);
                if(bytes.Length==0||bytes.Length>16384||offset+bytes.Length>Convert.ToInt32(meta["total_bytes"]))throw new LibraryFault("upload_range_invalid","Chunk exceeds declared range");
                using(var stream=new FileStream(TransferBytes(id,".bin"),FileMode.Open,FileAccess.ReadWrite,FileShare.None)) {
                    if(offset>stream.Length)throw new LibraryFault("upload_range_invalid","Chunk leaves a gap");
                    stream.Position=offset;
                    if(offset<stream.Length) {
                        var existing=new byte[bytes.Length];int read=stream.Read(existing,0,existing.Length);
                        if(read!=bytes.Length||!existing.SequenceEqual(bytes))throw new LibraryFault("upload_chunk_conflict","Different data at the same offset");
                    }else {stream.Write(bytes,0,bytes.Length);stream.Flush(true);}
                    return Success(Lib.Map("upload_id",id,"received_bytes",stream.Length));
                }
            }
            if(action=="inspect_import")return Inspect(a);
            var outcome=Mutate("commit_import",a,()=>Import(a));
            var imported=Lib.Arr(Lib.Obj(Lib.Obj(outcome)["data"])["imported"]);
            foreach(object raw in imported) {
                var reference=Lib.Obj(Lib.Obj(raw)["technique_ref"]);string library=Lib.Str(reference,"library_id"),id=Lib.Str(reference,"technique_id"),rev=Lib.Str(reference,"revision");
                if(Lib.Str(Technique(library,id),"head")==rev)try {SyncWorkspace(library,id,rev,null);}catch(Exception error){try {WorkspaceStatus(library,id,Lib.Map("state","error","error",Lib.Obj(Lib.Error(error))["error"]));}catch(Exception){} }
            }
            return outcome;
        }
        object Inspect(Dictionary<string,object>a) {
            string upload=Lib.Str(a,"upload_id"),library=LibraryId(a);Writable(library);var package=Uploaded(upload);
            var index=Lib.Obj(package["index"]);var packs=Lib.Obj(package["packs"]);
            var roots=Lib.Arr(index["roots"]);var selected=Lib.Arr(Lib.Get(a,"selected_roots",roots));
            if(selected.Count==0)throw new LibraryFault("selection_invalid","Select at least one representative");
            var rootKeys=new HashSet<string>(roots.Cast<object>().Select(x=>Key(Lib.Str(Lib.Obj(x),"technique_id"),Lib.Str(Lib.Obj(x),"revision"))));
            var selectedKeys=selected.Cast<object>().Select(x=>Key(Lib.Str(Lib.Obj(x),"technique_id"),Lib.Str(Lib.Obj(x),"revision"))).Distinct().ToArray();
            if(selectedKeys.Any(k=>!rootKeys.Contains(k)))throw new LibraryFault("selection_invalid","Selection is not a package representative");
            var needed=new HashSet<string>();var visiting=new HashSet<string>();var ordered=new List<string>();
            Action<string,int> visit=null;visit=(key,depth)=>{
                if(visiting.Contains(key))throw new LibraryFault("dependency_cycle","Cyclic package dependency");
                if(needed.Contains(key))return;
                if(depth>8||needed.Count>=64)throw new LibraryFault("budget_exceeded","Package dependency graph too large");
                object raw;if(!packs.TryGetValue(key,out raw)) {
                    int at=key.LastIndexOf('@');string id=key.Substring(0,at),rev=key.Substring(at+1);
                    if(!Techniques(library).ContainsKey(id)||!Lib.Obj(Lib.Obj(Techniques(library)[id])["revisions"]).ContainsKey(rev))throw new LibraryFault("dependency_missing","External dependency unavailable: "+key);
                    ReadFiles(rev);return;
                }
                visiting.Add(key);
                foreach(object dep in Lib.Arr(Lib.Obj(Lib.Obj(raw)["manifest"])["dependencies"])) {var d=Lib.Obj(dep);visit(Key(Lib.Str(d,"technique_id"),Lib.Str(d,"revision")),depth+1);}
                visiting.Remove(key);needed.Add(key);if(needed.Count>64)throw new LibraryFault("budget_exceeded","Too many imported revisions");ordered.Add(key);
            };
            foreach(string key in selectedKeys)visit(key,0);
            string policy=Lib.Str(a,"conflict_policy","fail");var idMap=Lib.Obj(Lib.Get(a,"id_map",Lib.Map()));
            if(policy=="fork")foreach(string key in selectedKeys) {string id=key.Substring(0,key.LastIndexOf('@'));if(!idMap.ContainsKey(id))throw new LibraryFault("fork_mapping_required","Provide new IDs for selected roots");}
            if(idMap.Values.Cast<string>().Distinct().Count()!=idMap.Count)throw new LibraryFault("fork_mapping_invalid","Fork IDs must be unique");
            var expected=Lib.Map();var preview=new List<object>();
            foreach(string key in ordered) {
                var pack=Lib.Obj(packs[key]);var e=Lib.Obj(pack["entry"]);string id=Lib.Str(e,"technique_id"),rev=Lib.Str(e,"revision");string targetId=Lib.Str(idMap,id,id);
                if(!expected.ContainsKey(targetId))expected[targetId]=Techniques(library).ContainsKey(targetId)?Lib.Clone(Techniques(library)[targetId]):null;
                var existing=Techniques(library).ContainsKey(targetId)?Lib.Obj(Techniques(library)[targetId]):null;
                bool same=existing!=null&&Lib.Obj(existing["revisions"]).ContainsKey(rev)&&targetId==id;
                if(policy=="fail"&&existing!=null&&!same)throw new LibraryFault("import_conflict","Different revision exists: "+targetId);
                if(policy=="fork"&&existing!=null&&targetId!=id)throw new LibraryFault("import_conflict","Fork target exists: "+targetId);
                preview.Add(Lib.Map("technique_id",id,"revision",rev,"target_id",targetId,"selected",selectedKeys.Contains(key),"action",same?"reuse":existing==null?"create_draft":"stage_revision","summary",Lib.Obj(pack["manifest"])["summary"]));
            }
            string planId=Guid.NewGuid().ToString();
            WriteRecord("transfers",planId,Lib.Map("kind","import_plan","upload_id",upload,"library_id",library,"policy",policy,"ordered",ordered,"selected",selectedKeys,"id_map",idMap,"expected",expected,"expires_at",DateTime.UtcNow.AddMinutes(10).ToString("o")));
            return Success(Lib.Map("import_plan_id",planId,"package",Lib.Map("title",index["title"],"roots",roots,"self_contained",index["self_contained"]),
                "items",preview,"required_revision_count",ordered.Count,"model_changed",false,"code_executed",false));
        }
        object Import(Dictionary<string,object>a) {
            string library=LibraryId(a),upload=Lib.Str(a,"upload_id");Writable(library);
            var plan=Record("transfers",Lib.Str(a,"import_plan_id"));
            if(Lib.Str(plan,"kind")!="import_plan"||Lib.Str(plan,"upload_id")!=upload||Lib.Str(plan,"library_id")!=library||Lib.Str(plan,"policy")!=Lib.Str(a,"conflict_policy"))throw new LibraryFault("import_plan_mismatch","Import arguments differ from inspected selection");
            if(DateTime.Parse(Lib.Str(plan,"expires_at"),null,System.Globalization.DateTimeStyles.RoundtripKind)<DateTime.UtcNow)throw new LibraryFault("import_plan_expired","Inspect package again");
            foreach(var expected in Lib.Obj(plan["expected"])) {
                object actual;Techniques(library).TryGetValue(expected.Key,out actual);
                if(Lib.Json(Lib.Canon(actual))!=Lib.Json(Lib.Canon(expected.Value)))throw new LibraryFault("import_conflict","Target changed since inspection");
            }
            var package=Uploaded(upload);var packs=Lib.Obj(package["packs"]);var map=Lib.Obj(plan["id_map"]);var rewritten=new Dictionary<string,Dictionary<string,object>>();var results=new List<object>();
            foreach(string key in Lib.Arr(plan["ordered"])) {
                var pack=Lib.Obj(packs[key]);var source=Lib.Obj(pack["entry"]);string oldId=Lib.Str(source,"technique_id"),oldRev=Lib.Str(source,"revision"),id=Lib.Str(map,oldId,oldId);
                var files=PackageFiles(pack);var m=Lib.Parse(files["manifest.json"]);
                bool changed=id!=oldId;m["id"]=id;
                foreach(object raw in Lib.Arr(m["dependencies"])) {
                    var d=Lib.Obj(raw);string childKey=Key(Lib.Str(d,"technique_id"),Lib.Str(d,"revision"));
                    if(rewritten.ContainsKey(childKey)) {
                        var child=rewritten[childKey];
                        if(!Object.Equals(d["technique_id"],child["technique_id"])||!Object.Equals(d["revision"],child["revision"]))changed=true;
                        d["technique_id"]=child["technique_id"];d["revision"]=child["revision"];
                    }
                }
                if(changed)files["manifest.json"]=Lib.Json(m)+"\n";
                ValidateFiles(files);string rev=Lib.Revision(files);
                var ts=Techniques(library);object rawTech;bool exists=ts.TryGetValue(id,out rawTech);var t=exists?Lib.Obj(rawTech):null;
                if(Lib.Str(plan,"policy")=="fork"&&exists&&!Lib.Obj(t["revisions"]).ContainsKey(rev))throw new LibraryFault("fork_mapping_required","Map conflicting dependent ID: "+id);
                CheckQuota(library,rev,files.Values.Sum(x=>Lib.Utf8.GetByteCount(x)));
                StoreFiles(rev,files);
                if(!exists)ts[id]=t=Lib.Map("head","","active","","archived",false,"revisions",Lib.Map(),"tags",Lib.Map());
                bool noChange=Lib.Obj(t["revisions"]).ContainsKey(rev);
                if(!noChange)Lib.Obj(t["revisions"])[rev]=Lib.Map("manifest",m,"change_summary","Imported package","parent_revision",t["head"],"created_at",DateTime.UtcNow.ToString("o"),
                    "validation",Lib.Map("offline","not_run","native","not_run"),"derived_from",Lib.Map("technique_id",oldId,"revision",oldRev));
                if(!exists||Lib.Arr(plan["selected"]).Contains(key))t["head"]=rev;
                rewritten[key]=Lib.Map("technique_id",id,"revision",rev);
                results.Add(Lib.Map("technique_ref",Ref(library,id,rev),"no_change",noChange,"active",t["active"]));
            }
            foreach(var r in rewritten.Values)Graph(Lib.Str(r,"technique_id"),Lib.Str(r,"revision"),Lib.Map(),new HashSet<string>(),0,false);
            return Success(Lib.Map("imported",results,"active_changed",false,"code_executed",false,"model_changed",false),"library_changed");
        }
    }
}
