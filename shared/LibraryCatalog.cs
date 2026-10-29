using System;
using System.Linq;
using System.Collections.Generic;
namespace SketchUpPipeProbe
{
    public static class LibraryCatalog
    {
        static Dictionary<string,object> specs;
        static Dictionary<string,object> Specs {get {return specs??(specs=Lib.Parse(Lib.Resource("library-tools.json")));}}
        public static bool Contains(string name) {return name!=null&&Specs.ContainsKey(name);}
        public static void Validate(string name,Dictionary<string,object> args) {
            if(!Contains(name))throw new ArgumentException("Unknown library tool");
            Lib.TextBudget(args,196608);
            LibrarySchema.Validate(Lib.Obj(Specs[name])["schema"],args);
        }
        public static object[] List() {
            return Specs.Select(p=>{
                var s=Lib.Obj(p.Value);bool read=p.Key.EndsWith("_list")||p.Key.EndsWith("_get");
                return (object)new {name=p.Key,description=Lib.Str(s,"description"),inputSchema=s["schema"],
                    annotations=new {readOnlyHint=read,destructiveHint=false,idempotentHint=true,openWorldHint=false}};
            }).ToArray();
        }
    }
}
