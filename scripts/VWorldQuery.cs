// Read-only helper for the source workflow. Keys are handled solely by AddOnService.
using System;
using System.IO;
using System.Net;
using System.Threading;
using SketchUpPipeProbe;
class VWorldQuery {
    static int Main(string[] args) {
        if(LibraryWorker.TryMain(args))return 0;
        try {
            if(args.Length!=3)return 2;
            ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
            var service=new AddOnService(Path.Combine(args[0],"AddOns"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"SketchUpCodexMcp","AddOns"));
            var result=service.QueryAsync("vworld",Lib.Parse(File.ReadAllText(args[1])),CancellationToken.None).GetAwaiter().GetResult();
            // Host has already removed reflected credentials; never log request URLs/exceptions.
            File.WriteAllText(args[2],Lib.Json(result),Lib.Utf8);return 0;
        }catch(Exception){Console.Error.WriteLine("VWorld query helper failed. Check local activation and runtime files.");return 1;}
    }
}
