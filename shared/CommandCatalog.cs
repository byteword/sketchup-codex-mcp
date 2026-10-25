using System;
using System.Collections;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace SketchUpPipeProbe
{
    public static class CommandCatalog
    {
        static readonly string[] Names = { "sketchup_set_selection", "sketchup_set_view", "sketchup_zoom", "sketchup_update_entity_properties", "sketchup_move_entities", "sketchup_get_command_result" };
        public static bool Contains(string name) { return Array.IndexOf(Names, name) >= 0; }
        public static bool IsWrite(string name) { return Contains(name) && name != "sketchup_get_command_result"; }
        public static string Method(string name) { return name.Substring("sketchup_".Length); }
        static object Text(int maximum, int minimum = 1) { return new { type = "string", minLength = minimum, maxLength = maximum }; }
        static object Ids(int maximum) { return new { type = "array", maxItems = maximum, uniqueItems = true, items = new { type = "string", pattern = "^[1-9][0-9]{0,18}$" } }; }
        static object Choice(params string[] choices) { return new Dictionary<string, object> { { "type", "string" }, { "enum", choices } }; }

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
                case "sketchup_move_entities":
                    fields["entity_ids"] = Ids(25);
                    fields["delta_mm"] = new { type = "array", minItems = 3, maxItems = 3, items = new { type = "number", minimum = -1000000000, maximum = 1000000000 } };
                    break;
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
                string detail = name == "sketchup_get_command_result" ? "Read a cached command result without execution permission. Results retain their original model_id. Evicted IDs are expired and cannot execute again." :
                    "Requires local permission in the SketchUp panel and current session/model/edit context. Use returned persistent IDs, at most 25 groups/components in the current context. A command ID is consumed once. No automatic retries. dry_run previews without changes. Selection/camera changes have no model Undo; property/move edits use one Undo operation. Shared edit ancestors and unsupported camera modes are rejected.";
                switch (name)
                {
                    case "sketchup_set_selection": detail = "Replace, add, remove or clear selection. clear requires empty entity_ids. " + detail; break;
                    case "sketchup_set_view": detail = "Set an orthographic top/front/right/isometric view and fit the model. " + detail; break;
                    case "sketchup_zoom": detail = "Fit the whole model (empty entity_ids) or explicit objects; never infer targets from a changing selection. " + detail; break;
                    case "sketchup_update_entity_properties": detail = "Change only specified name/hidden/locked/tag/material properties. Tag/material names must already exist. material=null clears direct assignment. Unlock a locked object in a separate command. " + detail; break;
                    case "sketchup_move_entities": detail = "Translate instances by delta_mm=[dx,dy,dz] along MODEL axes, including through rotated/scaled edit ancestors. Maximum +/-1e9 mm per axis. " + detail; break;
                }
                result.Add(new { name = name, description = name + ": " + detail,
                    inputSchema = new { type = "object", properties = fields, required = required.ToArray(), additionalProperties = false },
                    annotations = new { readOnlyHint = !IsWrite(name), destructiveHint = false, idempotentHint = true, openWorldHint = false } });
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
            if (args == null) throw new ArgumentException("arguments must be an object");
            var fields = Fields(name);
            foreach (string key in fields.Keys)
                if (key != "dry_run" && !args.ContainsKey(key)) throw new ArgumentException("Missing argument: " + key);
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
                    case "delta_mm":
                        var delta = ArrayField(pair.Value, 3);
                        if (delta.Count != 3) throw new ArgumentException("delta_mm must have three numbers");
                        foreach (object value in delta)
                        {
                            if (!(value is int || value is long || value is double || value is decimal)) throw new ArgumentException("Invalid delta number");
                            double number = Convert.ToDouble(value);
                            if (Double.IsNaN(number) || Double.IsInfinity(number) || Math.Abs(number) > 1000000000) throw new ArgumentException("delta_mm is out of range");
                        }
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
            }
        }
    }
}
