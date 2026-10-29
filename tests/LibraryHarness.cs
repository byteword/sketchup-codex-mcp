using System;
using System.IO;
using System.Threading.Tasks;
using SketchUpPipeProbe;
static class LibraryHarness
{
    static int Main(string[] args) {
        if(LibraryWorker.TryMain(args))return 0;
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
