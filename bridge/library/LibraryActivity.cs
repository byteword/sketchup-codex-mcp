using System;
using System.Collections.Generic;
using System.Linq;
namespace SketchUpPipeProbe
{
    public sealed partial class LibraryService
    {
        // The native peer supplies its own verified session/model. Never include
        // another document or unbound offline work in its toolbar activity.
        IEnumerable<Dictionary<string,object>> ModelJobs(string session,string model) {
            if(String.IsNullOrEmpty(session)||String.IsNullOrEmpty(model))yield break;
            foreach(string id in cancellations.Keys.ToArray()) {
                var job=Record("jobs",id);
                if(!new[]{"queued","running"}.Contains(Lib.Str(job,"state")))continue;
                var a=Lib.Obj(job["arguments"]);
                var binding=Lib.Str(a,"mode")=="apply" ? a : Lib.Obj(Lib.Get(a,"bindings",Lib.Map()));
                if(Lib.Str(binding,"session_id")==session&&Lib.Str(binding,"model_id")==model)yield return job;
            }
        }
        public object ModelActivity(string session,string model) {
            lock(gate)return ModelJobs(session,model).Select(j=>Lib.Map("job_id",j["job_id"],
                "model_id",model,"stage",j["stage"],"submitted",j["submitted"])).ToArray();
        }
        public int StopModelJobs(string session,string model) {
            int count=0;
            lock(gate)foreach(var job in ModelJobs(session,model)) {
                // Submitted native calls retain their true result/unknown state.
                // Revoking the local lease blocks native work not yet authorized.
                if(Lib.Bool(job,"submitted"))continue;
                cancellations[Lib.Str(job,"job_id")].Cancel();count++;
            }
            return count;
        }
    }
}
