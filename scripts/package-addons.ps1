param()
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$probeRepo=Split-Path $PSScriptRoot -Parent
$probeOut=Join-Path $probeRepo ('dist/probe-addons-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.zip')
$probeZip=[IO.Compression.ZipFile]::Open($probeOut,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($probeName in @('addon.json','addon.js','terrain.html')) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($probeZip,(Join-Path $probeRepo ('AddOns/vworld/'+$probeName)),('AddOns/vworld/'+$probeName))
    }
} finally { $probeZip.Dispose() }
Write-Output $probeOut
