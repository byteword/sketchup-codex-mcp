using System;
using System.IO;
using System.Threading.Tasks;
using SketchUpPipeProbe;
static class LibraryHarness
{
    static int Main(string[] args) {
        if(LibraryWorker.TryMain(args))return 0;
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
}
