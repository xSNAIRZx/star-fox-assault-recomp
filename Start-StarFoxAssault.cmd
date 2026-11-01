@echo off
setlocal
if exist "%~dp0Star Fox Assault Recomp.exe" (
  start "" "%~dp0Star Fox Assault Recomp.exe"
  exit /b
)
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Launch-StarFoxAssault.ps1"
endlocal
