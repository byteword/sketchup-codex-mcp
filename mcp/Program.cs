using System;
using System.Text;

namespace SketchUpPipeProbe
{
    static class McpProgram
    {
        static int Main(string[] args)
        {
            bool start = false;
            foreach (string arg in args)
            {
                if (arg == "--start-gui") start = true;
                else if (arg == "--version") { Console.WriteLine("SketchUp MCP " + BuildInfo.Version); return 0; }
                else if (arg == "--help") { Console.WriteLine("SketchUpMcp.exe [--start-gui]\nMCP stdio adapter. Register this executable in your MCP client; run start.cmd to open the GUI."); return 0; }
                else { Console.Error.WriteLine("Unknown argument: " + arg); return 1; }
            }
            Console.InputEncoding = new UTF8Encoding(false);
            Console.OutputEncoding = new UTF8Encoding(false);
            try
            {
                using (var channel = new JsonLines(Console.OpenStandardInput(), Console.OpenStandardOutput(), false))
                using (var bridge = new BridgeConnection(start))
                    new McpServer(channel, bridge).RunAsync().GetAwaiter().GetResult();
                return 0;
            }
            catch (Exception error) { Console.Error.WriteLine("SketchUp MCP: " + error.Message); return 1; }
        }
    }
}
