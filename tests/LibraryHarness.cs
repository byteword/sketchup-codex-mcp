using System;
using System.IO;
using System.Threading.Tasks;
using System.Threading;
using System.Collections.Generic;
using SketchUpPipeProbe;
static class LibraryHarness
{
    static int Main(string[] args) {
        if(LibraryWorker.TryMain(args))return 0;
        if(args.Length==2 && args[0]=="--activity-tests")return ActivityTests(args[1]);
        if(args.Length==1 && args[0]=="--worker-monitor-tests")return WorkerMonitorTests();
        Console.InputEncoding=new System.Text.UTF8Encoding(false,true);Console.OutputEncoding=new System.Text.UTF8Encoding(false);
        try {
            using(var service=new LibraryService(args[0])) {
                string line;while((line=Console.ReadLine())!=null) {
                    try {
                        var request=Lib.Parse(line);var arguments=Lib.Obj(request["arguments"]);
                        LibraryService.NativeCall native=null;
                        if(request.ContainsKey("native_snapshot")) {
                            var snapshot=Lib.Obj(request["native_snapshot"]);var bindings=Lib.Obj(arguments["bindings"]);
                            native=(method,fields,token)=> {
                                if(method=="get_state")return Task.FromResult(Lib.Map("ok",true,"state",Lib.Map("model_id",bindings["model_id"],"library_capabilities",new[]{"commands/1","face-texture/1","verify/1"})));
                                if(method=="get_plan_snapshot" && Lib.Str(fields,"query")=="face-texture/1" && Lib.Json(fields["instance_path"])==Lib.Json(snapshot["instance_path"]))
                                    return Task.FromResult(Lib.Map("ok",true,"data",Lib.Map("snapshot",Lib.Map("target",snapshot,"entities",new[]{snapshot}),"fingerprint",Lib.Digest(snapshot),"next_offset",null)));
                                throw new Exception("Unexpected native fixture request: "+method);
                            };
                        }
                        var output=service.HandleAsync(Lib.Str(request,"tool"),arguments,native).GetAwaiter().GetResult();Console.WriteLine(Lib.Json(output));
                    }
                    catch(Exception e){Console.WriteLine(Lib.Json(Lib.Error(e)));}
                }
            }return 0;
        }catch(Exception e){Console.Error.WriteLine(e);return 1;}
    }
    static Dictionary<string,object> Data(object result) {
        var value=Lib.Obj(result);
        if(!Lib.Bool(value,"ok"))throw new Exception(Lib.Json(value));
        return Lib.Obj(value["data"]);
    }
    static int ActivityTests(string root) {
        int checks=0;
        Action<bool> check=ok=>{if(!ok)throw new Exception("Activity test failed at "+checks);checks++;};
        using(var service=new LibraryService(root)) {
            var files=Lib.Map();
            foreach(string path in Directory.GetFiles("docs/library-spec/example/solid-panel"))files[Path.GetFileName(path)]=File.ReadAllText(path);
            var saved=Data(service.HandleAsync("sketchup_library_save",Lib.Map("request_id",Guid.NewGuid().ToString(),
                "technique_id","demo.solid-panel","base_revision",null,"files",files,"change_summary","test"),null).GetAwaiter().GetResult());
            var reference=Lib.Obj(saved["technique_ref"]);
            string session=Guid.NewGuid().ToString(),model=Guid.NewGuid().ToString();
            var bindings=Lib.Map("session_id",session,"model_id",model,"expected_context",new object[0],"materials",Lib.Map("panel","Gray"));
            for(int scenario=0;scenario<2;scenario++) {
                bool beforeSubmit=scenario==0;
                using(var entered=new ManualResetEventSlim()) {
                    var barrier=new TaskCompletionSource<Dictionary<string,object>>();
                    Dictionary<string,object> submitted=null;int calls=0;
                    var state=Lib.Map("ok",true,"state",Lib.Map("model_id",model,"library_capabilities",new[]{"group/1","mesh/1","material-existing/1","verify/1"}));
                    LibraryService.NativeCall native=(method,fields,token)=>{
                        if(method=="get_state") {
                            if(beforeSubmit){entered.Set();return barrier.Task;}
                            return Task.FromResult(state);
                        }
                        if(method=="get_plan_materials")return Task.FromResult(Lib.Map("ok",true));
                        if(method=="apply_library_plan") {
                            Interlocked.Increment(ref calls);submitted=fields;entered.Set();return barrier.Task;
                        }
                        throw new Exception("Unexpected method: "+method);
                    };
                    var args=Lib.Obj(Lib.Clone(reference));args["mode"]="verify";args["environment"]="native";
                    args["tests"]=new[]{"default"};args["request_id"]=Guid.NewGuid().ToString();args["command_id"]=session+":1";args["bindings"]=bindings;
                    var started=Data(service.HandleAsync("sketchup_library_run",args,native).GetAwaiter().GetResult());
                    string id=Lib.Str(started,"job_id");
                    check(entered.Wait(10000));
                    var activity=Lib.Arr(service.ModelActivity(session,model));
                    check(activity.Count==1 && Lib.Str(Lib.Obj(activity[0]),"job_id")==id);
                    check(Lib.Arr(service.ModelActivity(session,Guid.NewGuid().ToString())).Count==0);
                    check(service.StopModelJobs(Guid.NewGuid().ToString(),model)==0);
                    check(service.StopModelJobs(session,model)==(beforeSubmit?1:0));
                    check(Lib.Bool(Lib.Obj(activity[0]),"submitted")==!beforeSubmit);
                    // The blocked read deliberately ignores cancellation, exercising the
                    // final cancellation check at the native submission boundary.
                    barrier.SetResult(beforeSubmit?state:Lib.Map("ok",true,"result",Lib.Map(
                        "state","completed","library_job_id",submitted["library_job_id"],"data",Lib.Map("verified",true))));
                    var job=Data(service.HandleAsync("sketchup_library_job",Lib.Map("action","get","job_id",id,"wait_ms",5000),null).GetAwaiter().GetResult());
                    check(Lib.Str(job,"state")== (beforeSubmit?"canceled":"succeeded"));
                    check(Lib.Str(job,"effect")=="none");
                    check(calls==(beforeSubmit?0:1));
                    check(Lib.Arr(service.ModelActivity(session,model)).Count==0);
                }
            }
        }
        Console.WriteLine(Lib.Json(Lib.Map("ok",true,"checks",checks)));return 0;
    }
    static int WorkerMonitorTests() {
        int checks=0,kills=0;bool done=false;
        Action kill=()=>{kills++;done=true;};
        Action<bool> check=ok=>{if(!ok)throw new Exception("Worker monitor assertion failed");checks++;};
        check(!LibraryWorker.WorkerFinished(()=>false,()=>5,kill,1,100,10));
        check(kills==0);
        check(LibraryWorker.WorkerFinished(()=>true,()=>{throw new Exception("Must not sample exited worker");},kill,1,100,10));
        check(LibraryWorker.WorkerFinished(()=>done,()=>{done=true;throw new InvalidOperationException("Exited during sample");},kill,1,100,10));
        done=false;
        check(LibraryWorker.WorkerFinished(()=>done,()=>{done=true;throw new System.ComponentModel.Win32Exception(6);},kill,1,100,10));
        foreach(var error in new Exception[]{new InvalidOperationException("live"),new System.ComponentModel.Win32Exception(5)}) {
            try {LibraryWorker.WorkerFinished(()=>false,()=>{throw error;},kill,1,100,10);throw new Exception("Live sampling error was swallowed");}
            catch(Exception actual) {check(Object.ReferenceEquals(error,actual));}
        }
        foreach(bool time in new[]{false,true}) {
            done=false;
            try {LibraryWorker.WorkerFinished(()=>done,()=>time ? 5 : 11,kill,time ? 101 : 1,100,10);throw new Exception("Limit ignored");}
            catch(LibraryFault error) {check(error.Code=="budget_exceeded");}
        }
        check(kills==2);
        foreach(var error in new Exception[]{new InvalidOperationException("exit"),new System.ComponentModel.Win32Exception(6)}) {
            done=false;LibraryWorker.StopWorker(()=>done,()=>{done=true;throw error;});check(done);
            try {LibraryWorker.StopWorker(()=>false,()=>{throw error;});throw new Exception("Live kill error swallowed");}
            catch(Exception actual) {check(Object.ReferenceEquals(error,actual));}
        }
        done=false;
        try {LibraryWorker.WorkerFinished(()=>done,()=>11,()=>{done=true;throw new InvalidOperationException("exit during kill");},1,100,10);throw new Exception("Observed limit was lost");}
        catch(LibraryFault error) {check(error.Code=="budget_exceeded");}
        Console.WriteLine(Lib.Json(Lib.Map("ok",true,"checks",checks)));return 0;
    }
}
