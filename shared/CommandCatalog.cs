using System;
using System.Collections;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace SketchUpPipeProbe
{
    public static class CommandCatalog
    {
        static readonly string[] Names = { "sketchup_set_selection", "sketchup_set_view", "sketchup_zoom", "sketchup_update_entity_properties", "sketchup_move_entities", "sketchup_create_box", "sketchup_duplicate_entities", "sketchup_create_rectangle", "sketchup_create_circle", "sketchup_create_polyline", "sketchup_rotate_entities", "sketchup_scale_entities", "sketchup_erase_entities", "sketchup_group_entities", "sketchup_make_unique", "sketchup_push_pull", "sketchup_run_self_test", "sketchup_get_command_result" };
        public static bool Contains(string name) { return Array.IndexOf(Names, name) >= 0 || ToolkitCatalog.Contains(name); }
        public static bool IsWrite(string name) { return ToolkitCatalog.Contains(name) ? ToolkitCatalog.IsWrite(name) : Contains(name) && name != "sketchup_get_command_result"; }
        public static string Method(string name) { return name.Substring("sketchup_".Length); }
        static object Text(int maximum, int minimum = 1) { return new { type = "string", minLength = minimum, maxLength = maximum }; }
        static object Ids(int maximum) { return new { type = "array", maxItems = maximum, uniqueItems = true, items = new { type = "string", pattern = "^[1-9][0-9]{0,18}$" } }; }
        static object Choice(params string[] choices) { return new Dictionary<string, object> { { "type", "string" }, { "enum", choices } }; }
        static object Vector(int count, double minimum, double maximum) { return new { type = "array", minItems = count, maxItems = count, items = new { type = "number", minimum = minimum, maximum = maximum } }; }

        static Dictionary<string, object> Fields(string name)
        {
            var fields = new Dictionary<string, object> {
                { "session_id", Text(36) }, { "model_id", Text(36) },
                { "command_id", new { type = "string", maxLength = 48, description = "Use next_command_id from a fresh get_instance response. Each new command, including dry_run, needs a new ID. Query its result after a timeout; never automatically resend.", pattern = "^[0-9a-fA-F-]{36}:[1-9][0-9]{0,9}$" } }
            };
            if (!IsWrite(name)) return fields;
            fields["expected_context"] = Ids(32);
            fields["dry_run"] = new { type = "boolean", @default = false, description = "Validate and preview only; consumes this command ID. Execution requires a fresh next_command_id." };
            switch (name)
            {
                case "sketchup_set_selection": fields["entity_ids"] = Ids(25); fields["mode"] = Choice("replace", "add", "remove", "clear"); break;
                case "sketchup_set_view": fields["preset"] = Choice("top", "front", "right", "isometric"); break;
                case "sketchup_zoom": fields["scope"] = Choice("model", "entities"); fields["entity_ids"] = Ids(25); break;
                case "sketchup_duplicate_entities":
                case "sketchup_move_entities":
                    fields["entity_ids"] = Ids(25);
                    fields["delta_mm"] = new { type = "array", minItems = 3, maxItems = 3, items = new { type = "number", minimum = -1000000000, maximum = 1000000000 } };
                    break;
                case "sketchup_create_box":
                    fields["name"] = Text(256);
                    fields["origin_mm"] = new { type = "array", minItems = 3, maxItems = 3, items = new { type = "number", minimum = -1000000000, maximum = 1000000000 } };
                    fields["size_mm"] = new { type = "array", minItems = 3, maxItems = 3, items = new { type = "number", minimum = 1, maximum = 1000000 } };
                    break;
                case "sketchup_create_rectangle": case "sketchup_create_circle":
                    fields["name"] = Text(256); fields["origin_mm"] = Vector(3,-1000000000,1000000000); fields["plane"] = Choice("XY","XZ","YZ");
                    if (name == "sketchup_create_rectangle") fields["size_mm"] = Vector(2,1,1000000);
                    else { fields["radius_mm"] = new { type = "number", minimum = 1, maximum = 1000000 }; fields["segments"] = new { type = "integer", minimum = 8, maximum = 128, @default = 24 }; }
                    break;
                case "sketchup_create_polyline":
                    fields["name"] = Text(256); fields["points_mm"] = new { type = "array", minItems = 2, maxItems = 64, items = Vector(3,-1000000000,1000000000) }; break;
                case "sketchup_rotate_entities": case "sketchup_scale_entities":
                    fields["entity_ids"] = Ids(25); fields["pivot_mm"] = Vector(3,-1000000000,1000000000);
                    if (name == "sketchup_rotate_entities") { fields["axis"] = Vector(3,-1000000,1000000); fields["angle_degrees"] = new { type = "number", minimum = -360, maximum = 360 }; }
                    else fields["factors"] = Vector(3,0.001,1000);
                    break;
                case "sketchup_group_entities": case "sketchup_make_unique": case "sketchup_erase_entities": fields["entity_ids"] = Ids(25); break;
                case "sketchup_push_pull": fields["entity_ids"] = Ids(1); fields["distance_mm"] = new { type = "number", minimum = -1000000, maximum = 1000000 }; break;
                case "sketchup_run_self_test": fields["suite"] = Choice("core","extended","all"); fields["confirm_test_model"] = new { type = "boolean", @const = true, description = "Explicitly confirm this is a test model. Root context only. Temporary geometry is rolled back. Does not test individual Undo or file switching." }; break;
                case "sketchup_update_entity_properties":
                    fields["entity_ids"] = Ids(25);
                    fields["properties"] = new { type = "object", minProperties = 1, additionalProperties = false,
                        properties = new Dictionary<string, object> {
                            { "name", Text(256, 0) }, { "hidden", new { type = "boolean" } }, { "locked", new { type = "boolean" } },
                            { "tag", Text(256) }, { "material", new { type = new[] { "string", "null" }, minLength = 1, maxLength = 256 } }
                        } };
                    break;
            }
            return fields;
        }

        public static object[] List()
        {
            var result = new List<object>();
            foreach (string name in Names)
            {
                var fields = Fields(name);
                var required = new List<string>(fields.Keys);
                required.Remove("dry_run");
                required.Remove("segments");
                required.Remove("suite");
                string detail = name == "sketchup_get_command_result" ? "Read a cached command result without execution permission. Results retain their original model_id. Evicted IDs are expired and cannot execute again." :
                    "Requires local permission in the SketchUp panel and current session/model/edit context. Existing targets require returned persistent IDs, at most 25 groups/components in the current context. A command ID is consumed once. No automatic retries. dry_run previews without changes. Selection/camera changes have no model Undo; property/move/create/duplicate edits use one Undo operation. Shared edit ancestors and unsupported camera modes are rejected.";
                switch (name)
                {
                    case "sketchup_set_selection": detail = "Replace, add, remove or clear selection. clear requires empty entity_ids. " + detail; break;
                    case "sketchup_set_view": detail = "Set an orthographic top/front/right/isometric view and fit the model. " + detail; break;
                    case "sketchup_zoom": detail = "Fit the whole model (empty entity_ids) or explicit objects; never infer targets from a changing selection. " + detail; break;
                    case "sketchup_update_entity_properties": detail = "Change only specified name/hidden/locked/tag/material properties. Tag/material names must already exist. material=null clears direct assignment. Unlock a locked object in a separate command. " + detail; break;
                    case "sketchup_create_box": detail = "Create one independent box group with model-axis origin_mm and positive size_mm=[X,Y,Z], 1 to 1000000 mm per edge. Name is required. Uses Untagged/Layer0 for group and raw geometry. Returns new IDs only on execution. " + detail; break;
                    case "sketchup_duplicate_entities": detail = "Copy each source once and translate by model-axis delta_mm. Groups become independent definitions; components share their source definition. Preserves instance properties and bounded component attributes. Glued and locked sources are rejected. Zero displacement creates overlapping copies. " + detail; break;
                    case "sketchup_move_entities": detail = "Translate instances by delta_mm=[dx,dy,dz] along MODEL axes, including through rotated/scaled edit ancestors. Maximum +/-1e9 mm per axis. " + detail; break;
                    case "sketchup_create_rectangle": detail = "Create an isolated rectangular face group: model-axis origin_mm, plane XY/XZ/YZ, size_mm=[width,height] (1..1000000 mm). " + detail; break;
                    case "sketchup_create_circle": detail = "Create an isolated filled polygonal circle group: origin_mm is center, plane XY/XZ/YZ, radius_mm and optional segments (8..128, default24). " + detail; break;
                    case "sketchup_create_polyline": detail = "Create an isolated open polyline group from 2..64 distinct model-axis points_mm. Minimum segment 1 mm. Self-intersecting topology may be rejected and rolled back. " + detail; break;
                    case "sketchup_rotate_entities": detail = "Rotate groups/components around model-axis pivot_mm and nonzero axis, angle_degrees -360..360. " + detail; break;
                    case "sketchup_scale_entities": detail = "Scale groups/components along MODEL axes about pivot_mm. Positive factors 0.001..1000; no reflection. " + detail; break;
                    case "sketchup_erase_entities": detail = "Erase only explicitly named groups/components, at most25, with one Undo operation. No raw geometry deletion. " + detail; break;
                    case "sketchup_group_entities": detail = "Group explicit current children: groups/components, faces/edges/construction points. Up to25 targets. Raw surfaces require all boundary edges and adjacent faces included; partial connected geometry is rejected. Preserves model-space positions. Returns new parent/child paths; old paths are stale. Requires panel permission, fresh model/context/command ID; one Undo operation, no retries; dry_run supported."; break;
                    case "sketchup_make_unique": detail = "Separate each selected group's/component's outer definition while preserving instance transforms. Inner component definitions can remain shared. " + detail; break;
                    case "sketchup_push_pull": detail = "Extrude a unique single-face group along its normal by signed distance_mm, absolute1..1000000. Requires orthogonal uniform world scale. " + detail; break;
                    case "sketchup_run_self_test": detail = "Run a fixed fast native geometry/query/edit smoke suite with one local permission grant and one command ID. confirm_test_model=true and expected_context=[] required. Only temporary test geometry is changed, within one operation that is aborted; restores selection/camera. Read data.passed, checks, cleanup_verified, duration_ms. Individual Undo and model lifecycle are not tested. Cooperative4s budget, stops on first failure. No retries; after timeout query command result. dry_run lists checks without running."; break;
                }
                result.Add(new { name = name, description = name + ": " + detail,
                    inputSchema = new { type = "object", properties = fields, required = required.ToArray(), additionalProperties = false },
                    annotations = new { readOnlyHint = !IsWrite(name), destructiveHint = name == "sketchup_erase_entities", idempotentHint = true, openWorldHint = false } });
            }
            return result.ToArray();
        }

        static IList ArrayField(object value, int maximum)
        {
            var array = value as IList;
            if (array == null || array.Count > maximum) throw new ArgumentException("Invalid array or item limit");
            return array;
        }
        static void ValidateIds(object value, int maximum)
        {
            var unique = new HashSet<string>();
            foreach (object item in ArrayField(value, maximum))
            {
                string id = item as string;
                if (id == null || !Regex.IsMatch(id, "\\A[1-9][0-9]{0,18}\\z") || !unique.Add(id))
                    throw new ArgumentException("Invalid or duplicate persistent ID");
            }
        }
        static void ValidateChoice(object value, params string[] choices)
        { if (!(value is string) || Array.IndexOf(choices, (string)value) < 0) throw new ArgumentException("Invalid command choice"); }
        static double Number(object value, double minimum, double maximum)
        {
            if (!(value is int || value is long || value is double || value is decimal)) throw new ArgumentException("Expected a number");
            double number = Convert.ToDouble(value);
            if (Double.IsNaN(number) || Double.IsInfinity(number) || number < minimum || number > maximum) throw new ArgumentException("Number outside range");
            return number;
        }
        static void Numbers(object value, int count, double minimum, double maximum)
        {
            var numbers = ArrayField(value,count);
            if (numbers.Count != count) throw new ArgumentException("Wrong vector length");
            foreach (object number in numbers) Number(number,minimum,maximum);
        }
        static int UnicodeLength(string value)
        {
            int length = 0;
            for (int i = 0; i < value.Length; ++i)
            {
                if (value[i] == '\0' || Char.IsLowSurrogate(value[i])) throw new ArgumentException("Invalid Unicode property string");
                if (Char.IsHighSurrogate(value[i]))
                {
                    if (i + 1 >= value.Length || !Char.IsLowSurrogate(value[i + 1])) throw new ArgumentException("Invalid Unicode property string");
                    ++i;
                }
                ++length;
            }
            return length;
        }

        public static void Validate(string name, Dictionary<string, object> args)
        {
            if (ToolkitCatalog.Contains(name)) { ToolkitCatalog.Validate(name,args); return; }
            if (args == null) throw new ArgumentException("arguments must be an object");
            var fields = Fields(name);
            foreach (string key in fields.Keys)
                if (key != "dry_run" && key != "segments" && key != "suite" && !args.ContainsKey(key)) throw new ArgumentException("Missing argument: " + key);
            foreach (var pair in args)
            {
                if (!fields.ContainsKey(pair.Key)) throw new ArgumentException("Unexpected argument: " + pair.Key);
                switch (pair.Key)
                {
                    case "session_id": case "model_id":
                        Guid ignored;
                        if (!(pair.Value is string) || !Guid.TryParseExact((string)pair.Value, "D", out ignored)) throw new ArgumentException("Invalid UUID");
                        break;
                    case "command_id":
                        if (!(pair.Value is string) || !Regex.IsMatch((string)pair.Value, "\\A[0-9a-fA-F-]{36}:[1-9][0-9]{0,9}\\z")) throw new ArgumentException("Invalid command ID");
                        break;
                    case "expected_context": ValidateIds(pair.Value, 32); break;
                    case "entity_ids": ValidateIds(pair.Value, 25); break;
                    case "dry_run": if (!(pair.Value is bool)) throw new ArgumentException("dry_run must be boolean"); break;
                    case "mode": ValidateChoice(pair.Value, "replace", "add", "remove", "clear"); break;
                    case "preset": ValidateChoice(pair.Value, "top", "front", "right", "isometric"); break;
                    case "scope": ValidateChoice(pair.Value, "model", "entities"); break;
                    case "plane": ValidateChoice(pair.Value,"XY","XZ","YZ"); break;
                    case "suite": ValidateChoice(pair.Value,"core","extended","all"); break;
                    case "origin_mm": case "delta_mm": case "pivot_mm": Numbers(pair.Value,3,-1000000000,1000000000); break;
                    case "size_mm": Numbers(pair.Value,name == "sketchup_create_rectangle" ? 2 : 3,1,1000000); break;
                    case "factors": Numbers(pair.Value,3,0.001,1000); break;
                    case "axis":
                        Numbers(pair.Value,3,-1000000,1000000);
                        double norm = 0; foreach (object v in (IList)pair.Value) norm += Math.Pow(Convert.ToDouble(v),2);
                        if (norm < 1e-24) throw new ArgumentException("Axis must be nonzero"); break;
                    case "angle_degrees": Number(pair.Value,-360,360); break;
                    case "radius_mm": Number(pair.Value,1,1000000); break;
                    case "distance_mm": if (Math.Abs(Number(pair.Value,-1000000,1000000)) < 1) throw new ArgumentException("Distance too small"); break;
                    case "segments": if (!(pair.Value is int || pair.Value is long) || Convert.ToInt64(pair.Value) < 8 || Convert.ToInt64(pair.Value) > 128) throw new ArgumentException("Invalid segment count"); break;
                    case "points_mm":
                        var points = ArrayField(pair.Value,64); if (points.Count < 2) throw new ArgumentException("Too few points");
                        foreach (object p in points) Numbers(p,3,-1000000000,1000000000); break;
                    case "confirm_test_model": if (!(pair.Value is bool) || !(bool)pair.Value) throw new ArgumentException("Test model confirmation required"); break;
                    case "name":
                        string boxName = pair.Value as string;
                        if (boxName == null || UnicodeLength(boxName) < 1 || UnicodeLength(boxName) > 256) throw new ArgumentException("Invalid box name");
                        break;
                    case "properties":
                        var properties = pair.Value as Dictionary<string, object>;
                        if (properties == null || properties.Count < 1 || properties.Count > 5) throw new ArgumentException("Invalid properties");
                        foreach (var property in properties)
                        {
                            if (property.Key == "locked" || property.Key == "hidden")
                            { if (!(property.Value is bool)) throw new ArgumentException("Property must be boolean"); }
                            else if (property.Key == "material" && property.Value == null) { }
                            else if (property.Key == "name" || property.Key == "tag" || property.Key == "material")
                            {
                                string value = property.Value as string;
                                if (value == null || UnicodeLength(value) > 256 || (property.Key != "name" && value.Length == 0)) throw new ArgumentException("Invalid property string");
                            }
                            else throw new ArgumentException("Unsupported property: " + property.Key);
                        }
                        break;
                }
            }
            if (args.ContainsKey("entity_ids"))
            {
                int count = ((IList)args["entity_ids"]).Count;
                bool empty = name == "sketchup_set_selection" && (string)args["mode"] == "clear" || name == "sketchup_zoom" && (string)args["scope"] == "model";
                if ((empty && count != 0) || (!empty && count == 0)) throw new ArgumentException("Invalid target count for command mode");
                if (name == "sketchup_push_pull" && count != 1) throw new ArgumentException("Push/pull needs one group");
            }
            if (name == "sketchup_run_self_test" && ((IList)args["expected_context"]).Count != 0) throw new ArgumentException("Self-test requires model root");
        }
    }
}
