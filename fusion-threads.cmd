@echo off
setlocal
where pwsh.exe >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fusion-threads.ps1" %*
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fusion-threads.ps1" %*
)
exit /b %ERRORLEVEL%
