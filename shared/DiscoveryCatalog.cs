using System;
using System.Collections;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace SketchUpPipeProbe
{
    public static class DiscoveryCatalog
    {
        public static bool Contains(string name)
        { return name == "sketchup_find_entities" || name == "sketchup_get_children" || name == "sketchup_get_entity_info"; }

        static Dictionary<string, object> Fields(string name)
        {
            var fields = new Dictionary<string, object> {
                { "session_id", new { type = "string", format = "uuid" } },
                { "model_id", new { type = "string", format = "uuid" } },
                { "limit", new { type = "integer", minimum = 1, maximum = 25, @default = 10 } },
                { "cursor", new { type = "string", minLength = 1, maxLength = 8192, description = "Opaque next_cursor from the same query. Omit on first page. Pages read live data; restart after model edits." } }
            };
            if (name == "sketchup_get_entity_info")
                return new Dictionary<string, object> { { "session_id", fields["session_id"] }, { "model_id", fields["model_id"] },
                    { "child_offset", new { type = "integer", minimum = 0, maximum = 1000000, @default = 0 } }, { "child_limit", new { type = "integer", minimum = 1, maximum = 25, @default = 25 } },
                    { "instance_path", new { type = "array", minItems = 1, maxItems = 32, items = new { type = "string", pattern = "^[1-9][0-9]{0,18}$" } } } };
            if (name == "sketchup_get_children")
                fields["parent_path"] = new { type = "array", maxItems = 31, items = new { type = "string", pattern = "^[1-9][0-9]{0,18}$" }, description = "Full instance_path of the parent from discovery; [] means model root. Does not open its edit context." };
            else
            {
                fields["scope"] = new Dictionary<string, object> { { "type", "string" }, { "enum", new[] { "current", "model" } }, { "default", "current" } };
                fields["name"] = new { type = "string", minLength = 1, maxLength = 256, description = "Case-insensitive literal substring of instance OR definition name, not a regular expression." };
                fields["tag"] = new { type = "string", minLength = 1, maxLength = 256, description = "Exact internal name of the directly assigned tag; includes hidden/locked objects." };
                fields["entity_type"] = new Dictionary<string, object> { { "type", "string" }, { "enum", new[] { "Group", "ComponentInstance" } } };
                fields["max_depth"] = new { type = "integer", minimum = 1, maximum = 32, @default = 8, description = "Search depth relative to scope; 1 means direct children. Absolute instance paths are limited to 32 levels." };
            }
            return fields;
        }

        public static object[] List()
        {
            var result = new List<object>();
            foreach (string name in new[] { "sketchup_find_entities", "sketchup_get_children", "sketchup_get_entity_info" })
            {
                string detail = name == "sketchup_get_entity_info" ? "Read one group/component/face/edge by its full instance_path without selecting it. Includes model-axis bounds, bounded direct geometry lengths in mm/areas in mm2, and up to 25 direct child paths. Does not report volume. " : name == "sketchup_find_entities" ?
                    "Find group/component occurrences by name, exact direct tag or type. Default scope is the current edit context, or request the whole model. Includes hidden/locked objects and repeated shared definitions by distinct instance_path." :
                    "Read group/component direct children at a full parent_path; [] is model root. Raw geometry is not listed, but child_entity_count includes all direct entity types.";
                result.Add(new { name = name,
                    description = detail + (name == "sketchup_get_entity_info" ? " Read only, no permission required. Direct geometry aggregation is limited to 5000 entities/0.15 seconds; inspect direct_geometry.complete. Follow next_child_offset using child_offset/child_limit for raw child paths. Live pages, not snapshots. Full paths are checked against actual parent membership." : " Read only, no permission grant, model/selection/camera changes, or automatic edit-path changes. Requires exact current session_id/model_id. Bounded by 20000 examined entities or 0.25 seconds per page, 25 results and a byte budget. Follow next_cursor with unchanged filters until null; inspect complete and omitted for depth/cycle limits. Live pages are not snapshots. For commands refresh edit context; only in_current_context items can be passed directly with parent_path as expected_context."),
                    inputSchema = new { type = "object", properties = Fields(name), required = name == "sketchup_get_entity_info" ? new[] { "session_id", "model_id", "instance_path" } : name == "sketchup_get_children" ? new[] { "session_id", "model_id", "parent_path" } : new[] { "session_id", "model_id" }, additionalProperties = false },
                    annotations = new { readOnlyHint = true, destructiveHint = false, idempotentHint = true, openWorldHint = false } });
            }
            return result.ToArray();
        }

        static void Text(object value, int maximum)
        {
            string text = value as string;
            if (String.IsNullOrEmpty(text)) throw new ArgumentException("Invalid discovery string");
            int count = 0;
            for (int i = 0; i < text.Length; ++i)
            {
                if (text[i] == '\0' || Char.IsLowSurrogate(text[i])) throw new ArgumentException("Invalid discovery Unicode string");
                if (Char.IsHighSurrogate(text[i]))
                {
                    if (i + 1 >= text.Length || !Char.IsLowSurrogate(text[i + 1])) throw new ArgumentException("Invalid discovery Unicode string");
                    ++i;
                }
                ++count;
            }
            if (count > maximum) throw new ArgumentException("Discovery string is too long");
        }

        public static void Validate(string name, Dictionary<string, object> args)
        {
            if (args == null) throw new ArgumentException("arguments must be an object");
            var fields = Fields(name);
            foreach (string key in name == "sketchup_get_entity_info" ? new[] { "session_id", "model_id", "instance_path" } : name == "sketchup_get_children" ? new[] { "session_id", "model_id", "parent_path" } : new[] { "session_id", "model_id" })
                if (!args.ContainsKey(key)) throw new ArgumentException("Missing argument: " + key);
            foreach (var pair in args)
            {
                if (!fields.ContainsKey(pair.Key)) throw new ArgumentException("Unexpected argument: " + pair.Key);
                switch (pair.Key)
                {
                    case "session_id": case "model_id":
                        Guid ignored;
                        if (!(pair.Value is string) || !Guid.TryParseExact((string)pair.Value, "D", out ignored)) throw new ArgumentException("Invalid UUID");
                        break;
                    case "limit": case "max_depth": case "child_offset": case "child_limit":
                        if (!(pair.Value is int) && !(pair.Value is long)) throw new ArgumentException("Expected an integer");
                        long number = Convert.ToInt64(pair.Value);
                        long maximum = pair.Key == "child_offset" ? 1000000 : pair.Key == "max_depth" ? 32 : 25;
                        if (number < (pair.Key == "child_offset" ? 0 : 1) || number > maximum) throw new ArgumentException("Discovery integer out of range");
                        break;
                    case "scope":
                        if (!(pair.Value is string) || ((string)pair.Value != "current" && (string)pair.Value != "model")) throw new ArgumentException("Invalid scope");
                        break;
                    case "entity_type":
                        if (!(pair.Value is string) || ((string)pair.Value != "Group" && (string)pair.Value != "ComponentInstance")) throw new ArgumentException("Invalid type");
                        break;
                    case "instance_path": case "parent_path":
                        var path = pair.Value as IList;
                        if (path == null || path.Count > (pair.Key == "instance_path" ? 32 : 31) || (pair.Key == "instance_path" && path.Count == 0)) throw new ArgumentException("Invalid instance path");
                        foreach (object item in path)
                            if (!(item is string) || !Regex.IsMatch((string)item, "\\A[1-9][0-9]{0,18}\\z")) throw new ArgumentException("Invalid persistent ID in path");
                        break;
                    default: Text(pair.Value, pair.Key == "cursor" ? 8192 : 256); break;
                }
            }
        }
    }
}
