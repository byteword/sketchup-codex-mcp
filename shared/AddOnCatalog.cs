using System;
using System.Collections.Generic;

namespace SketchUpPipeProbe
{
    public static class AddOnCatalog
    {
        public static bool Contains(string name) {return name=="sketchup_addon_list" || name=="sketchup_addon_query";}
        public static object[] List() {
            var id=new {type="string",pattern="^[a-z][a-z0-9-]{0,39}$",maxLength=40};
            return new object[] {
                new {name="sketchup_addon_list",description="List installed source add-ons, activation/configuration status and query fields. No credentials returned. No SketchUp connection needed.",
                    inputSchema=new {type="object",properties=new {},additionalProperties=false},
                    annotations=new {readOnlyHint=true,destructiveHint=false,idempotentHint=true,openWorldHint=false}},
                new {name="sketchup_addon_query",description="Query an add-on enabled locally in Probe. Calls its declared external HTTPS service. Use inputs from addon_list; never pass API keys. No model edits. Results may be incomplete; inspect limit flags.",
                    inputSchema=new {type="object",properties=new {addon_id=id,inputs=new {type="object"}},required=new[]{"addon_id","inputs"},additionalProperties=false},
                    annotations=new {readOnlyHint=true,destructiveHint=false,idempotentHint=true,openWorldHint=true}}
            };
        }
        public static void Validate(string name,Dictionary<string,object> args) {
            if(args==null)throw new ArgumentException("Expected arguments");
            if(name=="sketchup_addon_list") {if(args.Count!=0)throw new ArgumentException("No arguments expected");return;}
            if(args.Count!=2 || !args.ContainsKey("inputs"))throw new ArgumentException("Expected addon_id and inputs");
            Lib.Id(args,"addon_id","[a-z][a-z0-9-]{0,39}");Lib.Obj(args["inputs"]);
            if(Lib.Json(args).Length>8192)throw new ArgumentException("Add-on input limit");
        }
    }
}
