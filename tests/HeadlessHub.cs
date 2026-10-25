using System;
using System.Threading;
using System.Threading.Tasks;
using System.Linq;
using System.IO;
using SketchUpPipeProbe;

static class HeadlessHub
{
    static int Main(string[] args)
    {
        object gate = new object();
        Action<string> log = message => {
            if (message.Length > 512)
            {
                int count = Char.IsHighSurrogate(message[511]) ? 511 : 512;
                message = message.Substring(0, count) + "...";
            }
            if (args.Length == 0) Console.WriteLine(message);
            else lock (gate) File.AppendAllText(args[0], message + Environment.NewLine);
        };
        using (var hub = new PipeHub(log))
        using (var control = new ControlHub(hub, log))
        {
            hub.McpStateProvider = () => control.Clients.Values.Select(c => new { name = c.Name, pid = c.Pid }).ToArray();
            Wire.Observe(Task.Run(() => hub.RunAsync()), error => Console.Error.WriteLine(error));
            Wire.Observe(Task.Run(() => control.RunAsync()), error => Console.Error.WriteLine(error));
            Console.WriteLine("TEST_HUB_READY");
            log("Control pipe: " + ControlHub.PipeName);
            Console.ReadLine();
        }
        return 0;
    }
}
