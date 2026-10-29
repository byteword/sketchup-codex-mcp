using System;
using System.IO;
using SketchUpPipeProbe;
static class LibraryHarness
{
    static int Main(string[] args) {
        if(LibraryWorker.TryMain(args))return 0;
        Console.InputEncoding=new System.Text.UTF8Encoding(false,true);Console.OutputEncoding=new System.Text.UTF8Encoding(false);
        try {
            using(var service=new LibraryService(args[0])) {
                string line;while((line=Console.ReadLine())!=null) {
                    try {var request=Lib.Parse(line);var output=service.HandleAsync(Lib.Str(request,"tool"),Lib.Obj(request["arguments"])).GetAwaiter().GetResult();Console.WriteLine(Lib.Json(output));}
                    catch(Exception e){Console.WriteLine(Lib.Json(Lib.Error(e)));}
                }
            }return 0;
        }catch(Exception e){Console.Error.WriteLine(e);return 1;}
    }
}
