using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;

namespace SketchUpPipeProbe
{
    public sealed partial class LibraryService
    {
        FileSystemWatcher watcher;
        readonly ConcurrentDictionary<string,long> workspaceEvents=new ConcurrentDictionary<string,long>();
        public string DirectoryPath {get {return root;}}
        string Workspace(string library,string id) {
            Library(library);Technique(library,id);
            return Path.Combine(root,"workspaces",library,id);
        }
        void InitWorkspaces() {
            string folder=Path.Combine(root,"workspaces");Directory.CreateDirectory(folder);
            Directory.CreateDirectory(Path.Combine(root,"workspace-status"));
            watcher=new FileSystemWatcher(folder) {IncludeSubdirectories=true,NotifyFilter=NotifyFilters.FileName|NotifyFilters.LastWrite};
            FileSystemEventHandler changed=(sender,e)=>WorkspaceChanged(e.FullPath);
            watcher.Changed+=changed;watcher.Created+=changed;watcher.Deleted+=changed;
            watcher.Renamed+=(sender,e)=>WorkspaceChanged(e.FullPath);
            watcher.EnableRaisingEvents=true;
        }
        void WorkspaceChanged(string path) {
            string folder=Path.Combine(root,"workspaces")+Path.DirectorySeparatorChar;
            if(!path.StartsWith(folder,StringComparison.OrdinalIgnoreCase))return;
            var parts=path.Substring(folder.Length).Split(Path.DirectorySeparatorChar);
            if(parts.Length<3||parts[parts.Length-1].StartsWith(".")||parts[parts.Length-1].EndsWith(".tmp"))return;
            string key=parts[0]+"/"+parts[1];long serial=workspaceEvents.AddOrUpdate(key,1,(k,n)=>n+1);
            Wire.Observe(Task.Run(async ()=>{
                await Task.Delay(600,lifetime.Token).ConfigureAwait(false);
                long current;if(!workspaceEvents.TryGetValue(key,out current)||current!=serial)return;
                ReloadWorkspace(parts[0],parts[1]);
            }),error=>{});
        }
        Dictionary<string,string> WorkspaceFiles(string folder) {
            var files=new Dictionary<string,object>();var dirs=new Stack<string>();dirs.Push(folder);
            while(dirs.Count>0) {
                string dir=dirs.Pop();if((File.GetAttributes(dir)&FileAttributes.ReparsePoint)!=0)throw new LibraryFault("workspace_invalid","Linked workspace paths are not allowed");
                foreach(string child in Directory.GetDirectories(dir))dirs.Push(child);
                foreach(string path in Directory.GetFiles(dir)) {
                    string rel=path.Substring(folder.Length+1).Replace('\\','/');
                    if(rel.StartsWith(".")||rel.EndsWith(".tmp"))continue;
                    if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0||new FileInfo(path).Length>65536)throw new LibraryFault("workspace_invalid","Workspace file is linked or too large");
                    files[FileName(rel)]=File.ReadAllText(path,Lib.Utf8);
                }
            }return ParseFiles(files);
        }
        static void AtomicText(string path,string text) {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";byte[] bytes=Lib.Utf8.GetBytes(text);
            using(var f=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){f.Write(bytes,0,bytes.Length);f.Flush(true);}
            if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);
        }
        void WorkspaceStatus(string library,string id,object value) {
            string folder=Path.Combine(root,"workspace-status",library);Directory.CreateDirectory(folder);
            Lib.Atomic(Path.Combine(folder,id+".json"),value);
        }
        object ReadWorkspaceStatus(string library,string id) {
            string p=Path.Combine(root,"workspace-status",library,id+".json");
            return File.Exists(p)?Lib.Read(p):null;
        }
        void SyncWorkspace(string library,string id,string revision,object baseRevision) {
            string folder=Workspace(library,id);string marker=Path.Combine(folder,".workspace.json");
            Directory.CreateDirectory(folder);
            var files=ReadFiles(revision);
            if(File.Exists(marker)) {
                var stamp=Lib.Obj(Lib.Read(marker));var current=WorkspaceFiles(folder);string digest=Lib.Revision(current);
                if(digest!=revision&&digest!=(baseRevision as string)&&digest!=Lib.Str(stamp,"revision")) {
                    WorkspaceStatus(library,id,Lib.Map("state","conflict","message","Working files have local edits; save did not overwrite them","head",revision));return;
                }
                if(digest==revision) {Lib.Atomic(marker,Lib.Map("revision",revision,"updating",false));return;}
            }
            Lib.Atomic(marker,Lib.Map("revision",baseRevision,"updating",true));
            foreach(var p in files)AtomicText(Path.Combine(folder,p.Key.Replace('/',Path.DirectorySeparatorChar)),p.Value);
            // Remove only clean, known package files from the prior snapshot.
            foreach(string path in Directory.GetFiles(folder,"*",SearchOption.AllDirectories)) {
                string rel=path.Substring(folder.Length+1).Replace('\\','/');
                if(rel.StartsWith(".")||rel.EndsWith(".tmp"))continue;
                if(!files.ContainsKey(rel)){FileName(rel);File.Delete(path);}
            }
            Lib.Atomic(marker,Lib.Map("revision",revision,"updating",false));
            WorkspaceStatus(library,id,Lib.Map("state","clean","revision",revision));
        }
        void ReloadWorkspace(string library,string id) {
            Dictionary<string,object> run=null;
            lock(gate) {
                try {
                    var t=Technique(library,id);string folder=Workspace(library,id);var marker=Lib.Obj(Lib.Read(Path.Combine(folder,".workspace.json")));
                    if(Lib.Bool(marker,"updating"))return;
                    string basis=Lib.Str(marker,"revision");
                    if(Lib.Str(t,"head")!=basis)throw new LibraryFault("workspace_conflict","Head changed since these working files were loaded");
                    var files=WorkspaceFiles(folder);if(Lib.Revision(files)==basis)return;
                    string oldActive=Lib.Str(t,"active");
                    var a=Lib.Map("request_id",Guid.NewGuid().ToString(),"library_id",library,"technique_id",id,"base_revision",basis,
                        "files",files.ToDictionary(p=>p.Key,p=>(object)p.Value),"change_summary","Working files updated");
                    var saved=Lib.Obj(Save(a));var data=Lib.Obj(saved["data"]);var reference=Lib.Obj(data["technique_ref"]);
                    WorkspaceStatus(library,id,Lib.Map("state","draft_saved","revision",reference["revision"]));
                    if(Lib.Str(Library(library),"update_policy","draft_only")=="after_checks") {
                        run=new Dictionary<string,object>(reference);run["mode"]="verify";run["request_id"]=Guid.NewGuid().ToString();
                        run["activate_if_passed"]=true;run["expected_active_revision"]=oldActive==""?null:oldActive;
                    }
                }catch(Exception error){try {WorkspaceStatus(library,id,Lib.Map("state","error","error",Lib.Obj(Lib.Error(error))["error"]));}catch(Exception){}}
            }
            if(run!=null)Wire.Observe(StartRun(run,null),error=>{});
        }
        void CheckQuota(string library,string revision,int extraBytes) {
            var revisions=new Dictionary<string,long>();
            foreach(var raw in Techniques(library).Values)
                foreach(var p in Lib.Obj(Lib.Obj(raw)["revisions"])) {
                    if(revisions.ContainsKey(p.Key))continue;
                    var record=Lib.Obj(p.Value);revisions[p.Key]=record.ContainsKey("byte_count")?Convert.ToInt64(record["byte_count"]):ReadFiles(p.Key).Values.Sum(x=>(long)Lib.Utf8.GetByteCount(x));
                }
            if(!revisions.ContainsKey(revision))revisions[revision]=extraBytes;
            if(revisions.Values.Sum()>256L*1024*1024)throw new LibraryFault("library_quota_exceeded","Library source quota256 MiB exceeded");
        }
    }
}
