@echo off
setlocal
cd /d "%~dp0.."
if not defined VSCMD_VER (
  for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do call "%%i\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
)
if not exist dist mkdir dist
cl /nologo /O2 /W3 /Fodist\sketchup_ruby_runner.obj /Fedist\sketchup_ruby_runner.exe tests\sketchup_ruby_runner.c
exit /b %ERRORLEVEL%
