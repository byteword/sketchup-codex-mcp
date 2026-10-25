param([switch]$TestRelease)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$releaseVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $PWD 'shared\BuildInfo.cs')), 'public const string Version = "([^"]+)"').Groups[1].Value
$rubyVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $PWD 'extension\su_pipe_probe\version.rb')), "VERSION = '([^']+)'").Groups[1].Value
if ($releaseVersion -notmatch '^\d+\.\d+\.\d+$' -or $releaseVersion -ne $rubyVersion) {
    throw 'C# and Ruby release versions must match and use major.minor.patch format'
}
& .\build.cmd
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
foreach ($executable in @('SketchUpMcp.exe', 'SketchUpPipeProbe.exe')) {
    $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $PWD ('dist\' + $executable)))
    if ($versionInfo.FileVersion -ne ($releaseVersion + '.0') -or $versionInfo.ProductVersion -ne $releaseVersion -or
        $versionInfo.ProductName -ne 'SketchUp Local MCP Bridge' -or [string]::IsNullOrEmpty($versionInfo.FileDescription)) {
        throw ('Missing or inconsistent executable version information: ' + $executable)
    }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$extensionZip = Join-Path $PWD ('dist\su_pipe_probe-' + $releaseVersion + '.rbz')
if (Test-Path -LiteralPath $extensionZip) { Remove-Item -LiteralPath $extensionZip }
[IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $PWD 'extension'), $extensionZip)
# User preference: installation ZIPs contain only this runtime allowlist.
# Source, tests, documentation and development helpers stay in the workspace.
$releaseFiles = @('SketchUpMcp.exe','SketchUpMcp.exe.config','SketchUpPipeProbe.exe','SketchUpPipeProbe.exe.config',('su_pipe_probe-' + $releaseVersion + '.rbz'))
$checksumLines = foreach ($releaseFile in $releaseFiles) {
    $hash = Get-FileHash -LiteralPath (Join-Path $PWD ('dist\' + $releaseFile)) -Algorithm SHA256
    '{0}  dist/{1}' -f $hash.Hash.ToLowerInvariant(), $releaseFile
}
[IO.File]::WriteAllLines((Join-Path $PWD 'SHA256SUMS.txt'), $checksumLines, (New-Object Text.UTF8Encoding($false)))
$packageSuffix = if ($TestRelease) { '-test' } else { '' }
$releaseZip = Join-Path $PWD ('dist\sketchup-codex-mcp-' + $releaseVersion + $packageSuffix + '.zip')
if (Test-Path -LiteralPath $releaseZip) { Remove-Item -LiteralPath $releaseZip }
$archive = [IO.Compression.ZipFile]::Open($releaseZip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $releaseFiles) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $PWD ('dist\' + $file)), ('dist/' + $file))
    }
} finally { $archive.Dispose() }
Write-Output ('Packaged: ' + $releaseZip)
