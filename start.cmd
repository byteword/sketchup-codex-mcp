@echo off
setlocal
cd /d "%~dp0"
set "BRIDGE_BUILD_REQUIRED="
if not exist "dist\SketchUpPipeProbe.exe" set "BRIDGE_BUILD_REQUIRED=1"
if not exist "dist\SketchUpMcp.exe" set "BRIDGE_BUILD_REQUIRED=1"
if defined BRIDGE_BUILD_REQUIRED (
  call build.cmd
  if errorlevel 1 (
    echo Build failed. Copy this window's error text for diagnosis.
    pause
    exit /b 1
  )
)
start "" "%~dp0dist\SketchUpPipeProbe.exe"
