using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace SketchUpPipeProbe
{
    public static class Wire
    {
        public const int MaxFrame = 65536;
        public static readonly Encoding Utf8 = new UTF8Encoding(false, true);
        public static void Observe(Task task, Action<Exception> onError)
        {
            task.ContinueWith(t => onError(t.Exception.GetBaseException()),
                CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.Default);
        }
        public static string Text(IDictionary<string, object> data, string key)
        {
            object value;
            return data.TryGetValue(key, out value) && value != null ? Convert.ToString(value) : "";
        }
        public static Dictionary<string, object> Parse(string line)
        {
            var data = new JavaScriptSerializer { MaxJsonLength = MaxFrame, RecursionLimit = 16 }
                .DeserializeObject(line) as Dictionary<string, object>;
            if (data == null || Text(data, "v") != "1") throw new IOException("Invalid protocol envelope");
            return data;
        }
        public static byte[] Encode(object data)
        {
            byte[] bytes = Utf8.GetBytes(new JavaScriptSerializer().Serialize(data) + "\n");
            if (bytes.Length > MaxFrame + 1) throw new IOException("Frame too large");
            return bytes;
        }
    }

    // Read and write use OS-overlapped pipes, not the GUI thread.
    public sealed class Peer : IDisposable
    {
        public readonly string ConnectionId = Guid.NewGuid().ToString();
        public string SessionId { get; private set; }
        public readonly uint ClientPid;
        public Func<object> McpStateProvider;
        public Func<string,string,object> LibraryActivityProvider;
        public Action<string,string> EmergencyStopHandler;
        public DateTime LastSeenUtc { get; private set; }
        public volatile Dictionary<string, object> State = new Dictionary<string, object>();
        readonly NamedPipeServerStream pipe;
        readonly SemaphoreSlim writeGate = new SemaphoreSlim(1, 1);
        readonly Action<string> log;
        readonly ConcurrentDictionary<string, TaskCompletionSource<Dictionary<string, object>>> pending =
            new ConcurrentDictionary<string, TaskCompletionSource<Dictionary<string, object>>>();
        int disposed;

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint pid);

        public Peer(NamedPipeServerStream stream, Action<string> logger)
        {
            pipe = stream;
            log = logger;
            uint pid;
            if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out pid))
                throw new IOException("Cannot verify pipe client PID");
            ClientPid = pid;
            LastSeenUtc = DateTime.UtcNow;
        }

        public async Task SendAsync(Dictionary<string, object> data)
        {
            data["v"] = 1;
            data["session_id"] = SessionId;
            byte[] bytes = Wire.Encode(data);
            if (!await writeGate.WaitAsync(5000).ConfigureAwait(false)) throw new IOException("Write queue timeout");
            try
            {
                Task writing = pipe.WriteAsync(bytes, 0, bytes.Length);
                if (await Task.WhenAny(writing, Task.Delay(5000)).ConfigureAwait(false) != writing)
                {
                    Dispose();
                    // Observe late errors after disposal; the OS owns its buffer until completion.
                    Wire.Observe(writing, error => { });
                    throw new IOException("Pipe write timed out");
                }
                await writing.ConfigureAwait(false);
            }
            finally { writeGate.Release(); }
        }

        public Task<Dictionary<string, object>> CommandAsync(string method)
        {
            var snapshot = State;
            return RequestAsync(method, new Dictionary<string, object> {
                { "model_id", Wire.Text(snapshot, "model_id") },
                { "job_id", Wire.Text(snapshot, "job_id") },
                { "owner_id", "gui" }, { "text", "GUI → SketchUp: 한글 왕복 / 日本語 / 🙂" }
            }, CancellationToken.None);
        }

        public async Task<Dictionary<string, object>> RequestAsync(string method,
            Dictionary<string, object> args, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (SessionId == null || Volatile.Read(ref disposed) != 0) throw new IOException("SketchUp disconnected");
            string id = Guid.NewGuid().ToString();
            var completion = new TaskCompletionSource<Dictionary<string, object>>(TaskCreationOptions.RunContinuationsAsynchronously);
            pending[id] = completion;
            var request = new Dictionary<string, object>(args);
            request["type"] = "request";
            request["id"] = id;
            request["method"] = method;
            request["lease"] = Wire.Text(State, "lease");
            request["expires_at_ms"] = (long)(DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalMilliseconds + 7000;
            log("TX " + ClientPid + " / " + SessionId + " " + method + " id=" + id);
            try
            {
                await SendAsync(request).ConfigureAwait(false);
                using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(token))
                {
                    timeout.CancelAfter(8000);
                    var canceled = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                    using (timeout.Token.Register(() => canceled.TrySetResult(true)))
                    {
                        if (await Task.WhenAny(completion.Task, canceled.Task).ConfigureAwait(false) != completion.Task)
                        {
                            token.ThrowIfCancellationRequested();
                            throw new TimeoutException("SketchUp response timeout; request was not retried");
                        }
                        var response = await completion.Task.ConfigureAwait(false);
                        token.ThrowIfCancellationRequested();
                        return response;
                    }
                }
            }
            catch
            {
                if (method == "demo")
                {
                    // Same pipe preserves ordering. Cancel this request's job only, never a later job.
                    Wire.Observe(SendAsync(new Dictionary<string, object> {
                        { "type", "request" }, { "id", Guid.NewGuid().ToString() }, { "method", "cancel" },
                        { "job_id", id }
                    }), error => log("Cancel cleanup: " + error.Message));
                }
                throw;
            }
            finally
            {
                TaskCompletionSource<Dictionary<string, object>> ignored;
                pending.TryRemove(id, out ignored);
            }
        }

        public async Task ReadAsync(Action<Peer> registered)
        {
            byte[] buffer = new byte[8192];
            var frame = new List<byte>();
            while (Volatile.Read(ref disposed) == 0)
            {
                int count = await pipe.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
                if (count == 0) return;
                for (int i = 0; i < count; ++i)
                {
                    if (buffer[i] != 10)
                    {
                        if (frame.Count >= Wire.MaxFrame) throw new IOException("Incoming frame too large");
                        frame.Add(buffer[i]);
                        continue;
                    }
                    var message = Wire.Parse(Wire.Utf8.GetString(frame.ToArray()));
                    frame.Clear();
                    string type = Wire.Text(message, "type");
                    string session = Wire.Text(message, "session_id");
                    if (SessionId == null)
                    {
                        Guid parsed;
                        if (type != "hello" || !Guid.TryParse(session, out parsed) ||
                            Wire.Text(message, "pid") != ClientPid.ToString())
                            throw new IOException("Invalid hello or PID mismatch");
                        SessionId = session;
                        State = message;
                        registered(this);
                        log("Connected: PID " + ClientPid + " / " + SessionId);
                        await SendAsync(new Dictionary<string, object> { { "type", "welcome" } }).ConfigureAwait(false);
                    }
                    else if (session != SessionId) throw new IOException("Session mismatch");
                    LastSeenUtc = DateTime.UtcNow;
                    if (type == "event" && Wire.Text(message,"event")=="emergency_stop" &&
                        Wire.Text(message,"model_id")==Wire.Text(State,"model_id") && EmergencyStopHandler!=null)
                        EmergencyStopHandler(SessionId,Wire.Text(message,"model_id"));
                    if (type == "state") State = message;
                    else if (type == "request" && Wire.Text(message, "method") == "ping")
                    {
                        log("RX ping from PID " + ClientPid + ": " + Wire.Text(message, "text"));
                        await SendAsync(new Dictionary<string, object> {
                            { "type", "result" }, { "id", Wire.Text(message, "id") },
                            { "ok", true }, { "text", Wire.Text(message, "text") }
                        }).ConfigureAwait(false);
                    }
                    else if (type == "result" || type == "event")
                    {
                        TaskCompletionSource<Dictionary<string, object>> response;
                        if (type == "result" && pending.TryGetValue(Wire.Text(message, "id"), out response))
                            response.TrySetResult(message);
                        log("RX " + ClientPid + " " + new JavaScriptSerializer().Serialize(message));
                    }
                    if ((type == "hello" || type == "state") && McpStateProvider != null)
                        await SendAsync(new Dictionary<string, object> {
                            { "type", "bridge_state" }, { "mcp_clients", McpStateProvider() },
                            { "library_jobs", LibraryActivityProvider==null ? new object[0] : LibraryActivityProvider(SessionId,Wire.Text(State,"model_id")) }
                        }).ConfigureAwait(false);
                }
            }
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) != 0) return;
            pipe.Dispose();
            foreach (var completion in pending.Values)
                completion.TrySetException(new IOException("SketchUp disconnected before replying"));
        }
    }

    public sealed class PipeHub : IDisposable
    {
#if PROBE_TEST
        public const string PipeName = "SketchUpCodexMcp.Test.Probe.v1";
#else
        public const string PipeName = "SketchUpCodexMcp.Probe.v1";
#endif
        public readonly ConcurrentDictionary<string, Peer> Peers = new ConcurrentDictionary<string, Peer>();
        public Func<object> McpStateProvider;
        public Func<string,string,object> LibraryActivityProvider;
        public Action<string,string> EmergencyStopHandler;
        readonly ConcurrentDictionary<string, Peer> connections = new ConcurrentDictionary<string, Peer>();
        readonly Action<string> log;
        readonly object sync = new object();
        NamedPipeServerStream listener;
        volatile bool stopping;
        public volatile string Status = "Starting";

        public PipeHub(Action<string> logger) { log = logger; }

        public static NamedPipeServerStream CreateListener(string name)
        {
            var security = new PipeSecurity();
            security.SetAccessRuleProtection(true, false);
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null),
                PipeAccessRights.FullControl, AccessControlType.Deny));
            SecurityIdentifier user = WindowsIdentity.GetCurrent().User;
            security.SetOwner(user);
            security.AddAccessRule(new PipeAccessRule(user, PipeAccessRights.FullControl, AccessControlType.Allow));
            return new NamedPipeServerStream(name, PipeDirection.InOut, 64, PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous, 8192, 8192, security);
        }

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
                        listener = stream = CreateListener(PipeName);
                    }
                    Status = "Listening";
                    log("Listening: \\\\.\\pipe\\" + PipeName);
                    await Task.Factory.FromAsync(stream.BeginWaitForConnection, stream.EndWaitForConnection, null)
                        .ConfigureAwait(false);
                    lock (sync)
                    {
                        if (stopping) { stream.Dispose(); return; }
                        listener = null;
                        var peer = new Peer(stream, log);
                        connections[peer.ConnectionId] = peer;
                        // ServeAsync contains its own error handling and cleanup.
                        Wire.Observe(ServeAsync(peer), error => log("Peer task error: " + error.Message));
                        stream = null; // ownership transferred
                    }
                    continue;
                }
                catch (Exception error)
                {
                    if (stream != null) stream.Dispose();
                    if (stopping) return;
                    Status = "Listener error: " + error.Message;
                    log("Listener error: " + error.Message);
                }
                await Task.Delay(1500).ConfigureAwait(false);
            }
        }

        async Task ServeAsync(Peer peer)
        {
            try
            {
                Task reading = peer.ReadAsync(p => {
                    p.McpStateProvider = McpStateProvider;
                    p.LibraryActivityProvider=LibraryActivityProvider;
                    p.EmergencyStopHandler=EmergencyStopHandler;
                    if (!Peers.TryAdd(p.SessionId, p)) throw new IOException("Duplicate session ID");
                });
                if (await Task.WhenAny(reading, Task.Delay(10000)).ConfigureAwait(false) != reading && peer.SessionId == null)
                {
                    peer.Dispose();
                    log("Handshake timeout");
                }
                await reading.ConfigureAwait(false);
            }
            catch (Exception error) { if (!stopping) log("Disconnected PID " + peer.ClientPid + ": " + error.Message); }
            finally
            {
                if (peer.SessionId != null)
                {
                    // Remove only this connection; never remove a legitimate peer on duplicate hello.
                    ((ICollection<KeyValuePair<string, Peer>>)Peers).Remove(
                        new KeyValuePair<string, Peer>(peer.SessionId, peer));
                }
                Peer ignored;
                connections.TryRemove(peer.ConnectionId, out ignored);
                peer.Dispose();
                log("Closed PID " + peer.ClientPid + " / " + peer.SessionId);
            }
        }

        public void Dispose()
        {
            lock (sync)
            {
                stopping = true;
                Status = "Stopped";
                if (listener != null) listener.Dispose();
                foreach (Peer peer in connections.Values) peer.Dispose();
            }
        }
    }
}
