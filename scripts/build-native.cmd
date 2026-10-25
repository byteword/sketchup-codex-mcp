@echo off
setlocal
cd /d "%~dp0.."
if not defined VSCMD_VER (
  for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do call "%%i\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
)
where cl >nul 2>nul
if errorlevel 1 (
  echo Visual Studio C++ x64 Build Tools are required ONLY to rebuild the native helper.
  exit /b 1
)
if not exist dist mkdir dist
if not exist extension\su_pipe_probe\native mkdir extension\su_pipe_probe\native
cl /nologo /c /O2 /W4 /WX /GS- /Zl /Fodist\pipe_win32.obj native\pipe_win32.c
if errorlevel 1 exit /b 1
link /nologo /DLL /NOENTRY /NODEFAULTLIB /MACHINE:X64 /OUT:extension\su_pipe_probe\native\pipe_win32_x64.dll /IMPLIB:dist\pipe_win32.lib dist\pipe_win32.obj kernel32.lib
exit /b %ERRORLEVEL%
