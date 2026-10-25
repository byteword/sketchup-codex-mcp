using System;
using System.Collections.Generic;

namespace SketchUpPipeProbe
{
    public static class ToolCatalog
    {
        static Dictionary<string, object> StringField(string description)
        { return new Dictionary<string, object> { { "type", "string" }, { "description", description }, { "minLength", 1 }, { "maxLength", 4096 } }; }

        static object Tool(string name, string description, string[] required, bool readOnly, bool text = false, bool page = false)
        {
            var properties = new Dictionary<string, object>();
            foreach (string key in required) properties[key] = StringField(key + ": use the exact ID returned by the bridge; never guess.");
            if (text) properties["text"] = StringField("Optional UTF-8 echo text, at most 4096 characters.");
            if (page)
            {
                properties["offset"] = new { type = "integer", minimum = 0, maximum = 1000000, @default = 0, description = "Zero-based offset into the current live selection." };
                properties["limit"] = new { type = "integer", minimum = 1, maximum = 25, @default = 10, description = "Maximum items. A byte limit may shorten the page; follow next_offset." };
            }
            return new Dictionary<string, object> {
                { "name", name }, { "description", description },
                { "inputSchema", new Dictionary<string, object> {
                    { "type", "object" }, { "properties", properties }, { "required", required }, { "additionalProperties", false }
                } },
                { "annotations", new { readOnlyHint = readOnly, destructiveHint = false, idempotentHint = readOnly || name == "sketchup_cancel_job", openWorldHint = false } }
            };
        }

        public static object[] List()
        {
            var result = new List<object> {
                Tool("sketchup_bridge_status", "Read local GUI bridge/MCP connection status. No SketchUp model edits.", new string[0], true),
                Tool("sketchup_list_instances", "List connected SketchUp processes with session_id, model_id, PID, model path, authority and heartbeat age. Cached state; do not select a target by title alone.", new string[0], true),
                Tool("sketchup_get_instance", "Get fresh state from one SketchUp instance. May time out while SketchUp is in a modal dialog.", new[] { "session_id" }, true),
                Tool("sketchup_get_model_summary", "Read the current model title/path, saved/modified state, units, model-axis bounds, bounded root-only entity counts, collection counts and edit context. All numeric lengths are mm. Requires the exact current session_id and model_id from list_instances; refresh after model_mismatch. No control grant needed, no model edits.", new[] { "session_id", "model_id" }, true),
                Tool("sketchup_get_selection_info", "Read the current selection: IDs, names, tags, direct materials, hidden/locked flags, model-axis bounding boxes, unscaled definition bounds and scaled instance-axis lengths in mm. Bounds may overestimate geometry. Pages read the live selection; follow next_offset only while selection is unchanged. No control grant needed, no model edits.", new[] { "session_id", "model_id" }, true, false, true),
                Tool("sketchup_ping", "Round-trip a UTF-8 message through GUI and the selected SketchUp Ruby plugin.", new[] { "session_id" }, true, true),
                Tool("sketchup_start_demo", "Start a 20-second connection test without geometry changes. Requires explicit local MCP permission in this SketchUp panel and the current model_id. Returns job_id immediately; poll get_job. Never automatically retry a timed-out start.", new[] { "session_id", "model_id" }, false),
                Tool("sketchup_get_job", "Get progress or terminal state of a demo job. The last 32 finished jobs are retained in this SketchUp session.", new[] { "session_id", "job_id" }, true),
                Tool("sketchup_cancel_job", "Cooperatively cancel exactly this job. Does not cancel a newer job and does not grant authority.", new[] { "session_id", "job_id" }, false)
            };
            result.AddRange(CommandCatalog.List());
            return result.ToArray();
        }

        public static void Validate(string name, Dictionary<string, object> args)
        {
            if (CommandCatalog.Contains(name)) { CommandCatalog.Validate(name, args); return; }
            string[] required;
            switch (name)
            {
                case "sketchup_bridge_status": case "sketchup_list_instances": required = new string[0]; break;
                case "sketchup_ping": case "sketchup_get_instance": required = new[] { "session_id" }; break;
                case "sketchup_start_demo": case "sketchup_get_model_summary": case "sketchup_get_selection_info": required = new[] { "session_id", "model_id" }; break;
                case "sketchup_get_job": case "sketchup_cancel_job": required = new[] { "session_id", "job_id" }; break;
                default: throw new ArgumentException("Unknown tool: " + name);
            }
            if (args == null) throw new ArgumentException("arguments must be an object");
            foreach (string key in required)
                if (!args.ContainsKey(key)) throw new ArgumentException("Missing argument: " + key);
            foreach (var pair in args)
            {
                if (name == "sketchup_get_selection_info" && (pair.Key == "offset" || pair.Key == "limit"))
                {
                    // The JSON parser represents integer tokens as Int32 or Int64; reject strings, booleans and fractions.
                    if (!(pair.Value is int) && !(pair.Value is long)) throw new ArgumentException("Invalid integer: " + pair.Key);
                    long number = Convert.ToInt64(pair.Value);
                    long minimum = pair.Key == "offset" ? 0 : 1;
                    long maximum = pair.Key == "offset" ? 1000000 : 25;
                    if (number < minimum || number > maximum) throw new ArgumentException("Out of range: " + pair.Key);
                    continue;
                }
                if (Array.IndexOf(required, pair.Key) < 0 && !(name == "sketchup_ping" && pair.Key == "text"))
                    throw new ArgumentException("Unexpected argument: " + pair.Key);
                string value = pair.Value as string;
                if (String.IsNullOrEmpty(value) || value.Length > 4096) throw new ArgumentException("Invalid string: " + pair.Key);
                if (pair.Key.EndsWith("_id"))
                {
                    Guid ignored;
                    if (!Guid.TryParseExact(value, "D", out ignored)) throw new ArgumentException("Invalid UUID: " + pair.Key);
                }
            }
        }

        public static object Result(object value, bool error = false)
        { return new { content = new[] { new { type = "text", text = JsonLines.Serialize(value) } }, isError = error }; }
        public static object Error(string code, string message)
        { return Result(new { error = code, message = message }, true); }
    }
}
