param()
$ErrorActionPreference='Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
$deps=@(
 @('jint','3.1.6','4f223bd00bb1c5ee17baddc10610ea39a7be903b52079a4badfe5121afdc8ae9','lib/net462/Jint.dll'),
 @('esprima','3.0.5','5e4e4957bd4d2ea88ad66fcce3c7dd98b6035f1f39bcee87c890b9cf60b069a4','lib/net462/Esprima.dll'),
 @('system.memory','4.5.5','10f43da352a29fb2b3188e4edd4dcf5100194c8b526e4f61fe2e2b5623775a22','lib/net461/System.Memory.dll'),
 @('system.buffers','4.5.1','c30b3dd2c7e2f4cee4b823d692fd42118309b42ab1f5007f923d329a5b0d6b12','lib/net461/System.Buffers.dll'),
 @('system.runtime.compilerservices.unsafe','4.5.3','96764c52a44ee1161151e48ef07489f72047a851cb55b99e9f01d6908536d1a9','lib/net461/System.Runtime.CompilerServices.Unsafe.dll'),
 @('system.numerics.vectors','4.5.0','a9d49320581fda1b4f4be6212c68c01a22cdf228026099c20a8eabefcf90f9cf','lib/net46/System.Numerics.Vectors.dll')
)
$folder=Join-Path $PWD 'dist/engine-deps'
[IO.Directory]::CreateDirectory($folder) | Out-Null
$resources=New-Object 'System.Collections.Generic.List[string]'
foreach($dep in $deps) {
 $archive=Join-Path $folder ($dep[0]+'.'+$dep[1]+'.nupkg')
 if(!(Test-Path -LiteralPath $archive)) { Invoke-WebRequest -UseBasicParsing ('https://api.nuget.org/v3-flatcontainer/'+$dep[0]+'/'+$dep[1]+'/'+$dep[0]+'.'+$dep[1]+'.nupkg') -OutFile $archive }
 $hasher=[Security.Cryptography.SHA256]::Create()
 try { $digest=[BitConverter]::ToString($hasher.ComputeHash([IO.File]::ReadAllBytes($archive))).Replace('-','').ToLowerInvariant() }finally{$hasher.Dispose()}
 if($digest -ne $dep[2]) {throw ('Dependency checksum mismatch: '+$dep[0])}
 $zip=[IO.Compression.ZipFile]::OpenRead($archive)
 try {
  $name=[IO.Path]::GetFileName($dep[3]);$entry=$zip.GetEntry($dep[3])
  [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $folder $name),$true)
  $resources.Add('/resource:"dist\engine-deps\'+$name+'",ProbeRuntime.'+$name)
 }finally{$zip.Dispose()}
}
$common=New-Object 'System.Collections.Generic.List[string]'
$common.Add('shared\AddOnCatalog.cs')
$common.Add('/resource:shared\LibraryTools.json,ProbeRuntime.library-tools.json');$common.Add('shared\LibraryCatalog.cs');$common.Add('bridge\library\LibraryJson.cs')
foreach($name in @('manifest','plan','operations','report','tests','package')) { $common.Add('/resource:docs\library-spec\'+$name+'.schema.json,ProbeRuntime.'+$name+'.schema.json') }
[IO.File]::WriteAllLines((Join-Path $PWD 'dist/library-common.rsp'),$common)
foreach($name in @('manifest.json','inputs.schema.json','technique.js','tests.json')) { $resources.Add('/resource:docs\library-spec\example\solid-panel/'+$name+',ProbeRuntime.example.'+$name) }
foreach($name in @('manifest.json','inputs.schema.json','technique.js','tests.json')) { $resources.Add('/resource:docs\library-spec\example\sliding-window/'+$name+',ProbeRuntime.window.'+$name) }
foreach($name in @('manifest.json','inputs.schema.json','technique.js','tests.json')) { $resources.Add('/resource:docs\library-spec\example\raw-drawing/'+$name+',ProbeRuntime.raw.'+$name) }
foreach($name in @('manifest.json','inputs.schema.json','technique.js','tests.json')) { $resources.Add('/resource:docs\library-spec\example\face-texture/'+$name+',ProbeRuntime.texture.'+$name) }
foreach($name in @('manifest.json','inputs.schema.json','technique.js','tests.json')) { $resources.Add('/resource:docs\library-spec\example\terrain-grid/'+$name+',ProbeRuntime.terrain.'+$name) }
$gui=@($common)+@($resources)+@(
 '/reference:System.Security.dll',
 'bridge\addons\AddOnService.cs','bridge\addons\AddOnScript.cs',
 '/reference:dist\engine-deps\Jint.dll',
 '/reference:dist\engine-deps\Esprima.dll',
 '/reference:System.Numerics.dll',
 '/reference:System.IO.Compression.dll',
 '/reference:System.IO.Compression.FileSystem.dll',
 '/resource:third_party\ScriptRuntime.NOTICES.txt,ProbeRuntime.NOTICES',
 'bridge\library\LibraryWorker.cs','bridge\library\LibraryStore.cs','bridge\library\LibraryRun.cs','bridge\library\LibraryActivity.cs','bridge\library\LibraryPackages.cs','bridge\library\LibraryWorkspace.cs')
[IO.File]::WriteAllLines((Join-Path $PWD 'dist/library-gui.rsp'),$gui)
