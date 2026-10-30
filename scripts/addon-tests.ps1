param([switch]$SkipBuild)
$ErrorActionPreference='Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if(!$SkipBuild) { & .\build.cmd; if($LASTEXITCODE -ne 0){throw 'Build failed'} }
$probeCompiler="$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $probeCompiler /nologo /target:exe /platform:x64 /warnaserror /codepage:65001 /out:dist\AddOnHarness.exe /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Web.Extensions.dll shared\BuildInfo.cs shared\CommandCatalog.cs shared\ToolkitCatalog.cs shared\DiscoveryCatalog.cs shared\JsonLines.cs shared\ToolCatalog.cs tests\AddOnHarness.cs bridge\PipeHub.cs bridge\addons\AddOnForm.cs bridge\addons\GeoJsonView.cs @dist\library-gui.rsp
if($LASTEXITCODE -ne 0){throw 'Add-on harness build failed'}
Copy-Item bridge\App.config dist\AddOnHarness.exe.config -Force
& .\dist\AddOnHarness.exe $PWD.Path
if($LASTEXITCODE -ne 0){throw 'Add-on tests failed'}
