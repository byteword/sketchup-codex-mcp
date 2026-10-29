using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.ExceptionServices;

namespace SketchUpPipeProbe
{
    public interface IBridge : IDisposable
    {
        void Start(string name, string version, string protocol);
        Task<object> CallAsync(string name, Dictionary<string, object> args, CancellationToken token);
    }

    public sealed class McpServer
    {
        readonly JsonLines channel;
        readonly IBridge bridge;
        readonly ConcurrentDictionary<string, CancellationTokenSource> pending = new ConcurrentDictionary<string, CancellationTokenSource>();
        readonly CancellationTokenSource lifetime = new CancellationTokenSource();
        readonly List<Task> tasks = new List<Task>();
        bool initialized, ready;
        string clientName, clientVersion, protocol;

        public McpServer(JsonLines transport, IBridge connection) { channel = transport; bridge = connection; }

        public async Task RunAsync()
        {
            Exception failure = null;
            try
            {
                string line;
                while ((line = await channel.ReadAsync().ConfigureAwait(false)) != null)
                {
                    Dictionary<string, object> message = null;
                    bool parseFailed = false;
                    try { message = JsonLines.Parse(line); }
                    catch (ArgumentException) { parseFailed = true; }
                    catch (InvalidOperationException) { parseFailed = true; }
                    if (parseFailed) { await ErrorAsync(null, -32700, "Parse error").ConfigureAwait(false); continue; }
                    if (message == null || JsonLines.Text(message, "jsonrpc") != "2.0")
                    { await ErrorAsync(null, -32600, "Invalid Request").ConfigureAwait(false); continue; }
                    // This server never originates JSON-RPC requests; ignore unsolicited responses.
                    if (!message.ContainsKey("method") && (message.ContainsKey("result") || message.ContainsKey("error"))) continue;
                    object rawMethod;
                    if (!message.TryGetValue("method", out rawMethod) || !(rawMethod is string))
                    { await ErrorAsync(null, -32600, "Invalid Request").ConfigureAwait(false); continue; }
                    string method = (string)rawMethod;
                    object id;
                    bool hasId = message.TryGetValue("id", out id);
                    if (hasId && !(id is string || id is int || id is long))
                    { await ErrorAsync(null, -32600, "Invalid request ID").ConfigureAwait(false); continue; }
                    var parameters = JsonLines.Object(message, "params");
                    if (!hasId)
                    {
                        if (method == "notifications/initialized" && initialized && !ready)
                        {
                            ready = true;
                            bridge.Start(clientName, clientVersion, protocol);
                        }
                        else if (method == "notifications/cancelled" && parameters != null)
                        {
                            object requestId;
                            if (parameters.TryGetValue("requestId", out requestId) && requestId != null)
                            {
                                lock (pending)
                                {
                                    CancellationTokenSource cancellation;
                                    if (pending.TryGetValue(Key(requestId), out cancellation)) cancellation.Cancel();
                                }
                            }
                        }
                        continue;
                    }
                    if (method == "ping") { await ResultAsync(id, new { }).ConfigureAwait(false); continue; }
                    if (method == "initialize")
                    {
                        if (initialized) { await ErrorAsync(id, -32600, "Already initialized").ConfigureAwait(false); continue; }
                        var info = JsonLines.Object(parameters, "clientInfo");
                        string requested = JsonLines.Text(parameters, "protocolVersion");
                        if (info == null || String.IsNullOrEmpty(JsonLines.Text(info, "name")) ||
                            JsonLines.Text(info, "name").Length > 128 || JsonLines.Text(info, "version").Length > 64 ||
                            requested.Length == 0 || JsonLines.Object(parameters, "capabilities") == null)
                        { await ErrorAsync(id, -32602, "Invalid initialize params").ConfigureAwait(false); continue; }
                        protocol = requested == "2025-06-18" || requested == "2025-03-26" ? requested : "2025-11-25";
                        clientName = JsonLines.Text(info, "name");
                        clientVersion = JsonLines.Text(info, "version");
                        initialized = true;
                        await ResultAsync(id, new {
                            protocolVersion = protocol,
                            capabilities = new { tools = new { listChanged = false } },
                            serverInfo = new { name = "sketchup-local", version = BuildInfo.Version },
                            instructions = "Use list_instances first and exact current session/model IDs. Find objects with find_entities/get_children; get_entity_info reads full instance paths including faces/edges without selection. Mutations require local panel permission, the current ordered edit_context.path persistent IDs as expected_context, and next_command_id from fresh get_instance. Each new execution/preview consumes a fresh ID. After timeout query get_command_result; never automatically retry. Normal geometry/property edits use one Undo operation; selection/camera do not. Grouping and make_unique can invalidate child paths; refresh after edits. run_self_test is a fixed fast batch for an explicitly confirmed small test model at root; temporary edits are aborted, inspect passed/checks/cleanup_verified. It does not certify individual Undo or file lifecycle."
                        }).ConfigureAwait(false);
                        continue;
                    }
                    if (!ready) { await ErrorAsync(id, -32002, "Initialize and send notifications/initialized first").ConfigureAwait(false); continue; }
                    if (method == "tools/list") { await ResultAsync(id, new { tools = ToolCatalog.List() }).ConfigureAwait(false); continue; }
                    if (method != "tools/call") { await ErrorAsync(id, -32601, "Method not found").ConfigureAwait(false); continue; }
                    string name = JsonLines.Text(parameters, "name");
                    var args = JsonLines.Object(parameters, "arguments");
                    if (parameters != null && !parameters.ContainsKey("arguments")) args = new Dictionary<string, object>();
                    string validationError = null;
                    try { ToolCatalog.Validate(name, args); }
                    catch (ArgumentException error) { validationError = error.Message; }
                    if (validationError != null) { await ErrorAsync(id, -32602, validationError).ConfigureAwait(false); continue; }
                    if (pending.Count >= 16) { await ErrorAsync(id, -32000, "Too many concurrent requests").ConfigureAwait(false); continue; }
                    var source = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
                    if (!pending.TryAdd(Key(id), source))
                    { source.Dispose(); throw new InvalidOperationException("Duplicate active JSON-RPC ID"); }
                    tasks.RemoveAll(t => t.IsCompleted);
                    tasks.Add(CallAsync(id, name, args, source));
                }
            }
            catch (Exception error) { failure = error; }
            finally
            {
                lifetime.Cancel();
                bridge.Dispose();
            }
            try { await Task.WhenAll(tasks).ConfigureAwait(false); }
            finally { lifetime.Dispose(); }
            if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
        }

        static string Key(object id) { return (id is string ? "s:" : "n:") + JsonLines.Serialize(id); }
        Task ResultAsync(object id, object result) { return channel.SendAsync(new { jsonrpc = "2.0", id = id, result = result }); }
        Task ErrorAsync(object id, int code, string message) { return channel.SendAsync(new { jsonrpc = "2.0", id = id, error = new { code = code, message = message } }); }

        async Task CallAsync(object id, string name, Dictionary<string, object> args, CancellationTokenSource source)
        {
            try
            {
                object result;
                try { result = await bridge.CallAsync(name, args, source.Token).ConfigureAwait(false); }
                catch (OperationCanceledException) { result = LibraryCatalog.Contains(name) ? ToolCatalog.Error("library_outcome_unknown","Query library_job with its job_id or replay the exact request_id; do not reapply model changes.") : ToolCatalog.Error(CommandCatalog.IsWrite(name) ? "outcome_unknown" : "canceled", CommandCatalog.IsWrite(name) ? "Query sketchup_get_command_result; a submitted command may have completed. Do not automatically retry." : "Request canceled."); }
                catch (Exception error) { result = LibraryCatalog.Contains(name) ? ToolCatalog.Error("library_unavailable","Probe unavailable. Query prior library job or replay the exact request_id; never repeat an apply with a fresh ID.") : ToolCatalog.Error(CommandCatalog.IsWrite(name) ? "outcome_unknown" : "bridge_unavailable", error.Message + (CommandCatalog.IsWrite(name) ? " Query sketchup_get_command_result; do not automatically retry." : "")); }
                await ResultAsync(id, result).ConfigureAwait(false);
            }
            catch (Exception error) { Console.Error.WriteLine("MCP output: " + error.Message); }
            finally
            {
                lock (pending)
                {
                    CancellationTokenSource removed;
                    pending.TryRemove(Key(id), out removed);
                    source.Dispose();
                }
            }
        }
    }
}
