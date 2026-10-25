@echo off
setlocal
cd /d "%~dp0"
set "PROBE_CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%PROBE_CSC%" (
  echo Windows x64 and .NET Framework 4.8 are required.
  exit /b 1
)
if not exist dist mkdir dist
"%PROBE_CSC%" /nologo /target:winexe /define:PROBE_GUI /platform:x64 /optimize+ /warnaserror /codepage:65001 /out:dist\SketchUpPipeProbe.exe /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Web.Extensions.dll shared\BuildInfo.cs shared\CommandCatalog.cs shared\JsonLines.cs shared\ToolCatalog.cs bridge\PipeHub.cs bridge\ControlHub.cs bridge\Program.cs
if errorlevel 1 exit /b 1
copy /y bridge\App.config dist\SketchUpPipeProbe.exe.config >nul
"%PROBE_CSC%" /nologo /target:exe /define:PROBE_MCP /platform:x64 /optimize+ /warnaserror /codepage:65001 /out:dist\SketchUpMcp.exe /reference:System.dll /reference:System.Core.dll /reference:System.Web.Extensions.dll shared\BuildInfo.cs shared\CommandCatalog.cs shared\JsonLines.cs shared\ToolCatalog.cs mcp\McpServer.cs mcp\BridgeConnection.cs mcp\Program.cs
if errorlevel 1 exit /b 1
copy /y bridge\App.config dist\SketchUpMcp.exe.config >nul
echo Built: dist\SketchUpPipeProbe.exe and dist\SketchUpMcp.exe
exit /b 0
