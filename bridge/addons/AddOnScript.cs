using System;
using System.Collections.Generic;
using Jint;

namespace SketchUpPipeProbe
{
    // Runs only inside the existing bounded worker. No CLR, IO or credentials.
    static class AddOnScript
    {
        public static object Execute(Dictionary<string,object> request)
        {
            string stage=Lib.Str(request,"stage");
            if(stage!="prepare" && stage!="parse")throw new ArgumentException("Unknown add-on stage");
            var engine=new Jint.Engine(o=>o.Strict().LimitRecursion(48).LimitMemory(32*1024L*1024L)
                .MaxStatements(200000).TimeoutInterval(TimeSpan.FromMilliseconds(1000)));
            engine.SetValue("INPUT_JSON",Lib.Json(request["input"]));
            engine.Execute("Date=undefined; Math.random=undefined;");
            engine.Execute(Lib.Str(request,"source"));
            string output=engine.Evaluate("JSON.stringify("+stage+"(JSON.parse(INPUT_JSON)))").AsString();
            if(Lib.Utf8.GetByteCount(output)>128*1024)throw new ArgumentException("Add-on output limit");
            return Lib.Parse(output);
        }
    }
}
