using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace SketchUpPipeProbe
{
    public sealed class McpClientState
    {
        public string Id, Name, Version, Protocol;
        public uint Pid;
        public volatile string LastTool = "";
        public int Active;
    }

    public sealed class ControlHub : IDisposable
    {
#if PROBE_TEST
        public const string PipeName = "SketchUpCodexMcp.Test.Control.v1";
#else
        public const string PipeName = "SketchUpCodexMcp.Control.v1";
#endif
        public readonly ConcurrentDictionary<string, McpClientState> Clients = new ConcurrentDictionary<string, McpClientState>();
        readonly ConcurrentDictionary<string, NamedPipeServerStream> streams = new ConcurrentDictionary<string, NamedPipeServerStream>();
        readonly PipeHub hub;
        readonly Action<string> log;
        readonly object sync = new object();
        NamedPipeServerStream listener;
        volatile bool stopping;
        public volatile string Status = "Starting";
        public volatile string LastError = "";

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint pid);

        public ControlHub(PipeHub pipeHub, Action<string> logger) { hub = pipeHub; log = logger; }

        public async Task RunAsync()
        {
            while (!stopping)
            {
                NamedPipeServerStream stream = null;
                try
                {
                    lock (sync)
                    {
                        if (stopping) return;
                        listener = stream = PipeHub.CreateListener(PipeName);
                    }
                    Status = "Listening";
                    await Task.Factory.FromAsync(stream.BeginWaitForConnection, stream.EndWaitForConnection, null).ConfigureAwait(false);
                    lock (sync)
                    {
                        if (stopping) { stream.Dispose(); return; }
                        listener = null;
                        string id = Guid.NewGuid().ToString();
                        streams[id] = stream;
                        Wire.Observe(ServeAsync(id, stream), error => log("MCP control: " + error.Message));
                        stream = null;
                    }
                    continue;
                }
                catch (Exception error)
                {
                    if (stream != null) stream.Dispose();
                    if (stopping) return;
                    Status = "Error";
                    LastError = error.Message;
                    log("MCP listener: " + error.Message);
                }
                await Task.Delay(1500).ConfigureAwait(false);
            }
        }

        async Task ServeAsync(string owner, NamedPipeServerStream stream)
        {
            var calls = new ConcurrentDictionary<string, CancellationTokenSource>();
            var tasks = new List<Task>();
            var client = new McpClientState { Id = owner };
            using (var channel = new JsonLines(stream, stream))
            using (var lifetime = new CancellationTokenSource())
            {
                try
                {
                    Task<string> greeting = channel.ReadAsync();
                    if (await Task.WhenAny(greeting, Task.Delay(10000)).ConfigureAwait(false) != greeting)
                    {
                        Wire.Observe(greeting, error => { });
                        throw new IOException("MCP control handshake timeout");
                    }
                    var hello = JsonLines.Parse(await greeting.ConfigureAwait(false));
                    if (JsonLines.Text(hello, "type") != "hello" || JsonLines.Text(hello, "v") != "1")
                        throw new IOException("Invalid MCP control hello");
                    uint pid;
                    if (!GetNamedPipeClientProcessId(stream.SafePipeHandle.DangerousGetHandle(), out pid))
                        throw new IOException("Cannot verify MCP adapter PID");
                    client.Pid = pid;
                    client.Name = JsonLines.Text(hello, "name");
                    client.Version = JsonLines.Text(hello, "version");
                    client.Protocol = JsonLines.Text(hello, "protocol");
                    if (client.Name.Length < 1 || client.Name.Length > 128 || client.Version.Length > 64 || client.Protocol.Length > 32)
                        throw new IOException("Invalid MCP client information");
                    Clients[owner] = client;
                    log("MCP connected: " + client.Name + " / PID " + pid);
                    await channel.SendAsync(new { type = "welcome", v = 1, client_id = owner }).ConfigureAwait(false);
                    string line;
                    while ((line = await channel.ReadAsync().ConfigureAwait(false)) != null)
                    {
                        var message = JsonLines.Parse(line);
                        string id = JsonLines.Text(message, "id");
                        if (id.Length < 1 || id.Length > 128) throw new IOException("Invalid control request ID");
                        string type = JsonLines.Text(message, "type");
                        if (type == "cancel")
                        {
                            lock (calls)
                            {
                                CancellationTokenSource active;
                                if (calls.TryGetValue(id, out active)) active.Cancel();
                            }
                            continue;
                        }
                        if (type != "request") throw new IOException("Invalid control request");
                        if (calls.Count >= 16) throw new IOException("Too many concurrent calls");
                        var cancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
                        if (!calls.TryAdd(id, cancellation)) { cancellation.Dispose(); throw new IOException("Duplicate control request ID"); }
                        tasks.RemoveAll(t => t.IsCompleted);
                        tasks.Add(HandleAsync(channel, client, id, message, cancellation, calls));
                    }
                }
                catch (Exception error)
                {
                    if (!stopping) { LastError = error.Message; log("MCP disconnected: " + error.Message); }
                }
                finally
                {
                    lifetime.Cancel();
                    channel.Dispose();
                }
                // C# 5 cannot await in finally. Cleanup still runs after every caught exit.
                // Drain dispatch before release: a delayed start cannot follow release_owner.
                try { await Task.WhenAll(tasks).ConfigureAwait(false); } catch (Exception) { }
                foreach (Peer peer in hub.Peers.Values)
                    Wire.Observe(peer.RequestAsync("release_owner", new Dictionary<string, object> { { "owner_id", owner } }, CancellationToken.None),
                        error => log("MCP owner cleanup: " + error.Message));
                McpClientState ignored;
                Clients.TryRemove(owner, out ignored);
                NamedPipeServerStream removed;
                streams.TryRemove(owner, out removed);
                log("MCP closed: " + client.Name + " / PID " + client.Pid);
            }
        }

        async Task HandleAsync(JsonLines channel, McpClientState client, string id, Dictionary<string, object> message,
            CancellationTokenSource cancellation, ConcurrentDictionary<string, CancellationTokenSource> calls)
        {
            Interlocked.Increment(ref client.Active);
            string tool = JsonLines.Text(message, "tool");
            client.LastTool = tool;
            try
            {
                object result;
                try
                {
                    result = await ExecuteAsync(client, tool, JsonLines.Object(message, "arguments"), cancellation.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) { result = ToolCatalog.Error("canceled", "Request canceled; any accepted demo is being stopped."); }
                catch (Exception error)
                {
                    LastError = error.Message;
                    log("MCP tool error: " + error.Message);
                    result = ToolCatalog.Error("bridge_error", error.Message);
                }
                await channel.SendAsync(new { type = "result", id = id, result = result }).ConfigureAwait(false);
            }
            catch (Exception error) { log("MCP response: " + error.Message); }
            finally
            {
                lock (calls)
                {
                    CancellationTokenSource ignored;
                    calls.TryRemove(id, out ignored);
                    cancellation.Dispose();
                }
                Interlocked.Decrement(ref client.Active);
            }
        }

        async Task<object> ExecuteAsync(McpClientState client, string name, Dictionary<string, object> args, CancellationToken token)
        {
            ToolCatalog.Validate(name, args);
            token.ThrowIfCancellationRequested();
            if (name == "sketchup_bridge_status")
                return ToolCatalog.Result(new { version = BuildInfo.Version, sketchup_listener = hub.Status, mcp_listener = Status,
                    instances = hub.Peers.Count, clients = Clients.Values.Select(c => new { name = c.Name, version = c.Version, pid = c.Pid, protocol = c.Protocol }).ToArray(), last_error = LastError });
            if (name == "sketchup_list_instances")
                return ToolCatalog.Result(new { instances = hub.Peers.Values.OrderBy(p => p.ClientPid).Select(Snapshot).ToArray() });
            Peer peer;
            if (!hub.Peers.TryGetValue(JsonLines.Text(args, "session_id"), out peer))
                return ToolCatalog.Error("instance_not_found", "Refresh sketchup_list_instances and choose an explicit target.");
            var fields = new Dictionary<string, object>(args);
            fields["owner_id"] = client.Id;
            string method;
            switch (name)
            {
                case "sketchup_get_instance": method = "get_state"; break;
                case "sketchup_get_model_summary": method = "get_model_summary"; break;
                case "sketchup_get_selection_info": method = "get_selection_info"; break;
                case "sketchup_ping": method = "ping"; if (!fields.ContainsKey("text")) fields["text"] = "ChatGPT → SketchUp: 한글 왕복 / 日本語 / 🙂"; break;
                case "sketchup_start_demo": method = "demo"; break;
                case "sketchup_get_job": method = "get_job"; break;
                case "sketchup_cancel_job": method = "cancel"; break;
                default: throw new ArgumentException("Unknown tool");
            }
            var response = await peer.RequestAsync(method, fields, token).ConfigureAwait(false);
            return ToolCatalog.Result(response, JsonLines.Text(response, "ok") != "True");
        }

        static object Snapshot(Peer peer)
        {
            var state = new Dictionary<string, object>(peer.State);
            state.Remove("lease");
            state.Remove("type");
            state["session_id"] = peer.SessionId;
            state["pid"] = peer.ClientPid;
            state["cached"] = true;
            state["heartbeat_age_seconds"] = Math.Round((DateTime.UtcNow - peer.LastSeenUtc).TotalSeconds, 1);
            return state;
        }

        public void Dispose()
        {
            lock (sync)
            {
                stopping = true;
                Status = "Stopped";
                if (listener != null) listener.Dispose();
                foreach (var stream in streams.Values) stream.Dispose();
            }
        }
    }
}
