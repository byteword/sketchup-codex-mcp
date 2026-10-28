using System.Reflection;

[assembly: AssemblyCompany("byteword")]
[assembly: AssemblyProduct(SketchUpPipeProbe.BuildInfo.Product)]
[assembly: AssemblyCopyright("Copyright (c) 2026 byteword")]
[assembly: AssemblyVersion(SketchUpPipeProbe.BuildInfo.NumericVersion)]
[assembly: AssemblyFileVersion(SketchUpPipeProbe.BuildInfo.NumericVersion)]
[assembly: AssemblyInformationalVersion(SketchUpPipeProbe.BuildInfo.Version)]
#if PROBE_GUI
[assembly: AssemblyTitle("SketchUp MCP Bridge")]
[assembly: AssemblyDescription("Local GUI bridge connecting SketchUp instances and MCP clients.")]
#elif PROBE_MCP
[assembly: AssemblyTitle("SketchUp MCP Adapter")]
[assembly: AssemblyDescription("MCP STDIO adapter for the SketchUp local bridge.")]
#else
[assembly: AssemblyTitle("SketchUp MCP Test Host")]
#endif

namespace SketchUpPipeProbe
{
    public static class BuildInfo
    {
        public const string Version = "0.6.0";
        public const string NumericVersion = Version + ".0";
        public const string Product = "SketchUp Local MCP Bridge";
    }
}
