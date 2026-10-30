param(
    [Parameter(Mandatory=$true)][string]$Probe,
    [string]$Config='',
    [string]$Python='',
    [switch]$Apply,
    [string]$Name=''
)
$ErrorActionPreference='Stop'
$probeRepo=Split-Path $PSScriptRoot -Parent
if(!$Config){$Config=Join-Path $probeRepo 'workflows/suyu-site-50m.json'}
$probeExe=(Resolve-Path -LiteralPath $Probe).Path
$probeRoot=Split-Path $probeExe -Parent
$probeRuntime=Join-Path $probeRepo 'dist/vworld-workflow-runtime'
[void](New-Item -ItemType Directory -Path $probeRuntime -Force)
Copy-Item -LiteralPath $probeExe -Destination (Join-Path $probeRuntime 'SketchUpPipeProbe.exe') -Force
Copy-Item -LiteralPath (Join-Path $probeRepo 'bridge/App.config') -Destination (Join-Path $probeRuntime 'VWorldQuery.exe.config') -Force
$probeCompiler="$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$probeHelper=Join-Path $probeRuntime 'VWorldQuery.exe'
& $probeCompiler /nologo /codepage:65001 ("/out:"+$probeHelper) ("/reference:"+(Join-Path $probeRuntime 'SketchUpPipeProbe.exe')) /reference:System.Web.Extensions.dll (Join-Path $PSScriptRoot 'VWorldQuery.cs')
if($LASTEXITCODE -ne 0){throw 'Query helper compilation failed'}
if(!$Python){$Python=Join-Path $probeRepo 'dist/python-3.13.9/python.exe';if(!(Test-Path -LiteralPath $Python)){$Python=(Get-Command python -ErrorAction Stop).Source}}
$probeArgs=@((Join-Path $PSScriptRoot 'vworld_massing.py'),'--config',(Resolve-Path -LiteralPath $Config).Path,'--probe-root',$probeRoot,'--query-helper',$probeHelper,'--mcp',(Join-Path $probeRoot 'SketchUpMcp.exe'))
if($Apply){$probeArgs+='--apply'}
if($Name){$probeArgs+=@('--name',$Name)}
& $Python @probeArgs
if($LASTEXITCODE -ne 0){throw 'VWorld workflow stopped; inspect the output report. Model edits are never retried automatically.'}
