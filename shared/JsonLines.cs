using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace SketchUpPipeProbe
{
    // One reader, serialized writers. A partial/oversized frame closes the connection.
    public sealed class JsonLines : IDisposable
    {
        public const int Limit = 1048576;
        readonly Stream input, output;
        readonly bool ownsStreams;
        readonly byte[] buffer = new byte[8192];
        readonly SemaphoreSlim gate = new SemaphoreSlim(1, 1);
        int offset, available;
        public JsonLines(Stream read, Stream write, bool owns = true)
        { input = read; output = write; ownsStreams = owns; }

        public static string Serialize(object value)
        { return new JavaScriptSerializer { MaxJsonLength = Limit, RecursionLimit = 32 }.Serialize(value); }
        public static Dictionary<string, object> Parse(string value)
        { return new JavaScriptSerializer { MaxJsonLength = Limit, RecursionLimit = 32 }.DeserializeObject(value) as Dictionary<string, object>; }
        public static string Text(IDictionary<string, object> value, string key)
        { object result; return value != null && value.TryGetValue(key, out result) && result != null ? Convert.ToString(result) : ""; }
        public static Dictionary<string, object> Object(IDictionary<string, object> value, string key)
        { object result; return value != null && value.TryGetValue(key, out result) ? result as Dictionary<string, object> : null; }

        public async Task<string> ReadAsync()
        {
            var frame = new List<byte>();
            while (true)
            {
                if (offset == available)
                {
                    available = await input.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
                    offset = 0;
                    if (available == 0)
                    {
                        if (frame.Count != 0) throw new IOException("Truncated JSON frame");
                        return null;
                    }
                }
                byte b = buffer[offset++];
                if (b == 10) return new UTF8Encoding(false, true).GetString(frame.ToArray());
                if (frame.Count >= Limit) throw new IOException("JSON frame too large");
                frame.Add(b);
            }
        }

        public async Task SendAsync(object value)
        {
            byte[] bytes = new UTF8Encoding(false, true).GetBytes(Serialize(value) + "\n");
            if (bytes.Length > Limit + 1) throw new IOException("JSON frame too large");
            if (!await gate.WaitAsync(5000).ConfigureAwait(false)) throw new IOException("Writer queue timeout");
            try
            {
                Task writing = WriteAsync(bytes);
                if (await Task.WhenAny(writing, Task.Delay(5000)).ConfigureAwait(false) != writing)
                {
                    Dispose();
                    Observe(writing);
                    throw new IOException("Writer timeout");
                }
                await writing.ConfigureAwait(false);
            }
            finally { gate.Release(); }
        }

        async Task WriteAsync(byte[] bytes)
        {
            await output.WriteAsync(bytes, 0, bytes.Length).ConfigureAwait(false);
            await output.FlushAsync().ConfigureAwait(false);
        }

        static void Observe(Task task)
        { task.ContinueWith(t => { var ignored = t.Exception; }, TaskContinuationOptions.OnlyOnFaulted); }

        public void Dispose()
        {
            if (!ownsStreams) return;
            input.Dispose();
            if (!object.ReferenceEquals(input, output)) output.Dispose();
        }
    }
}
