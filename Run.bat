@echo off
setlocal

where pwsh >nul 2>nul
if %errorlevel% == 0 (
    pwsh -ExecutionPolicy Bypass -File "%~dp0ProxiFyre-GUI.ps1"
    exit /b
)

where powershell >nul 2>nul
if %errorlevel% == 0 (
    powershell -ExecutionPolicy Bypass -File "%~dp0ProxiFyre-GUI.ps1"
    exit /b
)

echo PowerShell not found!
pause
exit /b 1
