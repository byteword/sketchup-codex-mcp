param(
    [string]$Python = 'python',
    [string]$Ruby = 'ruby',
    [string[]]$RubyArguments = @()
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
& .\build.cmd
if ($LASTEXITCODE -ne 0) { throw 'GUI build failed' }
$probeCompiler = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $probeCompiler /nologo /target:exe /platform:x64 /warnaserror /codepage:65001 /define:PROBE_TEST /out:dist\HeadlessHub.exe /reference:System.dll /reference:System.Core.dll /reference:System.Web.Extensions.dll shared\BuildInfo.cs shared\CommandCatalog.cs shared\ToolkitCatalog.cs shared\DiscoveryCatalog.cs shared\JsonLines.cs shared\ToolCatalog.cs bridge\PipeHub.cs bridge\ControlHub.cs tests\HeadlessHub.cs @dist\library-gui.rsp
if ($LASTEXITCODE -ne 0) { throw 'Headless hub build failed' }
Copy-Item bridge\App.config dist\HeadlessHub.exe.config -Force
& $probeCompiler /nologo /target:exe /platform:x64 /warnaserror /codepage:65001 /out:dist\McpHarness.exe /reference:System.dll /reference:System.Core.dll /reference:System.Web.Extensions.dll shared\BuildInfo.cs shared\CommandCatalog.cs shared\ToolkitCatalog.cs shared\DiscoveryCatalog.cs shared\JsonLines.cs shared\ToolCatalog.cs mcp\McpServer.cs tests\McpHarness.cs @dist\library-common.rsp
if ($LASTEXITCODE -ne 0) { throw 'MCP harness build failed' }
Copy-Item bridge\App.config dist\McpHarness.exe.config -Force
& $probeCompiler /nologo /target:exe /platform:x64 /warnaserror /codepage:65001 /define:PROBE_TEST /out:dist\SketchUpMcp.Test.exe /reference:System.dll /reference:System.Core.dll /reference:System.Web.Extensions.dll shared\BuildInfo.cs shared\CommandCatalog.cs shared\ToolkitCatalog.cs shared\DiscoveryCatalog.cs shared\JsonLines.cs shared\ToolCatalog.cs mcp\McpServer.cs mcp\BridgeConnection.cs mcp\Program.cs @dist\library-common.rsp
if ($LASTEXITCODE -ne 0) { throw 'Isolated MCP adapter build failed' }
Copy-Item bridge\App.config dist\SketchUpMcp.Test.exe.config -Force
& $probeCompiler /nologo /target:exe /platform:x64 /warnaserror /codepage:65001 /out:dist\LibraryHarness.exe /reference:System.dll /reference:System.Core.dll /reference:System.Web.Extensions.dll shared\BuildInfo.cs shared\CommandCatalog.cs shared\ToolkitCatalog.cs shared\DiscoveryCatalog.cs shared\JsonLines.cs shared\ToolCatalog.cs bridge\PipeHub.cs tests\LibraryHarness.cs @dist\library-gui.rsp
if ($LASTEXITCODE -ne 0) { throw 'Library harness build failed' }
Copy-Item bridge\App.config dist\LibraryHarness.exe.config -Force
& $Python tests/library_test.py (Join-Path $PWD 'dist\LibraryHarness.exe')
if ($LASTEXITCODE -ne 0) { throw 'Library/worker/package tests failed' }
& $Python tests/texture_math_test.py (Join-Path $PWD "dist\LibraryHarness.exe")
if ($LASTEXITCODE -ne 0) { throw "Texture technique math tests failed" }
& $Python tests/terrain_math_test.py (Join-Path $PWD "dist\LibraryHarness.exe")
if ($LASTEXITCODE -ne 0) { throw "Terrain technique math tests failed" }
& $Python tests/mcp_stdio_test.py dist/McpHarness.exe
if ($LASTEXITCODE -ne 0) { throw 'MCP stdio tests failed' }
& $Python tests/native_runner_test.py
if ($LASTEXITCODE -ne 0) { throw 'Standalone native batch runner tests failed' }
& $Ruby @RubyArguments tests/session_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Session tests failed' }
& $Ruby @RubyArguments tests/control_toolbar_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Toolbar/controller tests failed' }
& $Ruby @RubyArguments tests/model_identity_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Model lifecycle identity tests failed' }
& $Ruby @RubyArguments tests/command_session_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Command session tests failed' }
& $Ruby @RubyArguments tests/command_executor_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Command executor tests failed' }
& $Ruby @RubyArguments tests/creation_commands_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Creation and duplication tests failed' }
& $Ruby @RubyArguments tests/basic_commands_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Basic drawing/edit/query and native-suite tests failed' }
& $Ruby @RubyArguments tests/geometry_plan_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Geometry algorithm tests failed' }
& $Ruby @RubyArguments tests/extended_commands_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Extended drawing/component/resource tests failed' }
& $Ruby @RubyArguments tests/library_plan_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Library plan executor tests failed' }
& $Ruby @RubyArguments tests/raw_drawing_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Raw drawing tests failed' }
& $Ruby @RubyArguments tests/native_features_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Native metrics/annotation tests failed' }
& $Ruby @RubyArguments tests/texture_view_test.rb
if ($LASTEXITCODE -ne 0) { throw "Texture/view tests failed" }
& $Ruby @RubyArguments tests/workflow_test.rb
if ($LASTEXITCODE -ne 0) { throw "Scene/file/terrain/classification tests failed" }
& $Ruby @RubyArguments tests/file_style_test.rb
if ($LASTEXITCODE -ne 0) { throw "File/style extensions failed" }
& $Ruby @RubyArguments tests/sliding_window_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Sliding window recipe tests failed' }
& $Ruby @RubyArguments tests/ui_updates_test.rb
if ($LASTEXITCODE -ne 0) { throw 'UI suppression, atomic batch and cleanup tests failed' }
& $Ruby @RubyArguments tests/model_reader_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Model reader tests failed' }
& $Ruby @RubyArguments tests/entity_browser_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Entity browser tests failed' }
& $Ruby @RubyArguments tests/native_call_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Native error output tests failed' }
& $Ruby @RubyArguments tests/transport_test.rb
if ($LASTEXITCODE -ne 0) { throw 'Transport state tests failed' }
$probeProcess = New-Object System.Diagnostics.Process
$probeProcess.StartInfo.FileName = Join-Path (Get-Location) 'dist\HeadlessHub.exe'
$probeProcess.StartInfo.Arguments = '"' + (Join-Path (Get-Location) 'dist\pipe-test.log') + '"'
$probeProcess.StartInfo.UseShellExecute = $false
$probeProcess.StartInfo.RedirectStandardInput = $true
$probeProcess.StartInfo.CreateNoWindow = $true
[void]$probeProcess.Start()
$previousTestMode = $env:SUPIPE_TEST
$env:SUPIPE_TEST = '1'
try {
    & $Ruby @RubyArguments tests/windows_pipe_test.rb
    if ($LASTEXITCODE -ne 0) { throw 'Native pipe tests failed' }
    & $Python tests/windows_mcp_test.py $Ruby @RubyArguments
    if ($LASTEXITCODE -ne 0) { throw 'MCP / GUI / Ruby integration tests failed' }
} finally {
    $env:SUPIPE_TEST = $previousTestMode
    if (!$probeProcess.HasExited) {
        $probeProcess.StandardInput.WriteLine('stop')
        if (!$probeProcess.WaitForExit(5000)) { $probeProcess.Kill() }
    }
    $probeProcess.Dispose()
}
