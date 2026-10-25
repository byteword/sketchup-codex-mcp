using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using SketchUpPipeProbe;

// Test-only backend. Production stdio parser/dispatcher is used unchanged.
sealed class FakeBridge : IBridge
{
    bool started;
    public void Start(string name, string version, string protocol) { started = true; }
    public async Task<object> CallAsync(string name, Dictionary<string, object> args, CancellationToken token)
    {
        if (!started) throw new InvalidOperationException("Backend started before initialize notification");
        string text = JsonLines.Text(args, "text");
        if (text == "slow") await Task.Delay(30000, token);
        if (text == "offline") throw new System.IO.IOException("simulated disconnect");
        return ToolCatalog.Result(new { tool = name, arguments = args });
    }
    public void Dispose() { }
}

static class McpHarness
{
    static int Main()
    {
        try
        {
            using (var channel = new JsonLines(Console.OpenStandardInput(), Console.OpenStandardOutput(), false))
            using (var bridge = new FakeBridge())
                new McpServer(channel, bridge).RunAsync().GetAwaiter().GetResult();
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
