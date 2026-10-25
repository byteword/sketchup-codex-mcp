using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Threading;
using System.Threading.Tasks;

namespace SketchUpPipeProbe
{
    public sealed class BridgeConnection : IBridge
    {
#if PROBE_TEST
        const string PipeName = "SketchUpCodexMcp.Test.Control.v1";
#else
        const string PipeName = "SketchUpCodexMcp.Control.v1";
#endif
        readonly bool autoStart;
        readonly CancellationTokenSource lifetime = new CancellationTokenSource();
        readonly object sync = new object();
        volatile ControlLink link;
        NamedPipeClientStream connecting;
        bool started, guiAttempted;
        volatile string lastError = "GUI bridge is not connected. Run start.cmd.";

        public BridgeConnection(bool startGui) { autoStart = startGui; }

        public void Start(string name, string version, string protocol)
        {
            lock (sync)
            {
                if (started) return;
                started = true;
            }
            Task task = Task.Run(() => ConnectLoopAsync(name, version, protocol));
            Observe(task);
        }

        static void Observe(Task task)
        { task.ContinueWith(t => Console.Error.WriteLine(t.Exception.GetBaseException().Message), TaskContinuationOptions.OnlyOnFaulted); }

        async Task ConnectLoopAsync(string name, string version, string protocol)
        {
            while (!lifetime.IsCancellationRequested)
            {
                using (var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut, PipeOptions.Asynchronous))
                using (var channel = new JsonLines(pipe, pipe))
                {
                    try
                    {
                        lock (sync)
                        {
                            if (lifetime.IsCancellationRequested) return;
                            connecting = pipe;
                        }
                        await Task.Run(() => pipe.Connect(800)).ConfigureAwait(false);
                        await channel.SendAsync(new { type = "hello", v = 1, name = name, version = version, protocol = protocol }).ConfigureAwait(false);
                        Task<string> greeting = channel.ReadAsync();
                        if (await Task.WhenAny(greeting, Task.Delay(3000, lifetime.Token)).ConfigureAwait(false) != greeting)
                        { Observe(greeting); throw new IOException("GUI control handshake timed out"); }
                        var welcome = JsonLines.Parse(await greeting.ConfigureAwait(false));
                        if (JsonLines.Text(welcome, "type") != "welcome" || JsonLines.Text(welcome, "v") != "1")
                            throw new IOException("Invalid GUI control handshake");
                        var current = new ControlLink(channel);
                        guiAttempted = true; // Once connected, respect an explicit GUI shutdown.
                        link = current;
                        Console.Error.WriteLine("SketchUp GUI bridge connected.");
                        try { await current.ReadAsync().ConfigureAwait(false); }
                        finally { link = null; current.Close(); }
                    }
                    catch (Exception error)
                    {
                        lastError = "GUI bridge unavailable: " + error.Message + " Run start.cmd and check its MCP status.";
                        if (!lifetime.IsCancellationRequested && autoStart && !guiAttempted)
                        {
                            guiAttempted = true;
                            try
                            {
                                string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "SketchUpPipeProbe.exe");
                                if (!File.Exists(path)) throw new FileNotFoundException("GUI executable missing beside MCP adapter", path);
                                Process.Start(new ProcessStartInfo(path, "--quiet") { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(path) });
                            }
                            catch (Exception startError) { lastError = "Cannot start GUI: " + startError.Message; }
                        }
                    }
                    finally { lock (sync) { if (connecting == pipe) connecting = null; } }
                }
                try { await Task.Delay(1000, lifetime.Token).ConfigureAwait(false); }
                catch (OperationCanceledException) { return; }
            }
        }

        public async Task<object> CallAsync(string name, Dictionary<string, object> args, CancellationToken token)
        {
            // Wait for first/re-established connection, but never retry a submitted command.
            for (int i = 0; i < 50; ++i)
            {
                token.ThrowIfCancellationRequested();
                var current = link;
                if (current != null) return await current.CallAsync(name, args, token).ConfigureAwait(false);
                if (lifetime.IsCancellationRequested) throw new IOException("MCP adapter is shutting down");
                await Task.Delay(100, token).ConfigureAwait(false);
            }
            throw new IOException(lastError);
        }

        public void Dispose()
        {
            lock (sync)
            {
                if (lifetime.IsCancellationRequested) return;
                lifetime.Cancel();
                if (connecting != null) connecting.Dispose();
                var current = link;
                if (current != null) current.Close();
            }
        }

        sealed class ControlLink
        {
            readonly JsonLines channel;
            readonly ConcurrentDictionary<string, TaskCompletionSource<object>> pending = new ConcurrentDictionary<string, TaskCompletionSource<object>>();
            int closed;
            public ControlLink(JsonLines transport) { channel = transport; }

            public async Task ReadAsync()
            {
                string line;
                while ((line = await channel.ReadAsync().ConfigureAwait(false)) != null)
                {
                    var message = JsonLines.Parse(line);
                    TaskCompletionSource<object> completion;
                    object result;
                    if (JsonLines.Text(message, "type") != "result" || !message.TryGetValue("result", out result))
                        throw new IOException("Invalid GUI control response");
                    if (pending.TryGetValue(JsonLines.Text(message, "id"), out completion)) completion.TrySetResult(result);
                }
                throw new IOException("GUI bridge disconnected");
            }

            public async Task<object> CallAsync(string tool, Dictionary<string, object> args, CancellationToken token)
            {
                token.ThrowIfCancellationRequested();
                if (Volatile.Read(ref closed) != 0) throw new IOException("GUI bridge disconnected");
                string id = Guid.NewGuid().ToString();
                var completion = new TaskCompletionSource<object>(TaskCreationOptions.RunContinuationsAsynchronously);
                pending[id] = completion;
                try
                {
                    if (Volatile.Read(ref closed) != 0) throw new IOException("GUI bridge disconnected");
                    await channel.SendAsync(new { type = "request", id = id, tool = tool, arguments = args }).ConfigureAwait(false);
                    using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(token))
                    {
                        timeout.CancelAfter(15000);
                        var canceled = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                        using (timeout.Token.Register(() => canceled.TrySetResult(true)))
                        {
                            if (await Task.WhenAny(completion.Task, canceled.Task).ConfigureAwait(false) != completion.Task)
                            {
                                Observe(channel.SendAsync(new { type = "cancel", id = id }));
                                token.ThrowIfCancellationRequested();
                                throw new TimeoutException("GUI response timed out; request was not retried");
                            }
                            return await completion.Task.ConfigureAwait(false);
                        }
                    }
                }
                finally { TaskCompletionSource<object> ignored; pending.TryRemove(id, out ignored); }
            }

            public void Close()
            {
                if (Interlocked.Exchange(ref closed, 1) != 0) return;
                channel.Dispose();
                foreach (var completion in pending.Values) completion.TrySetException(new IOException("GUI bridge disconnected"));
            }
        }
    }
}
