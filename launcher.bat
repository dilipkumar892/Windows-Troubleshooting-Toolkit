@echo off
setlocal EnableDelayedExpansion
title Windows Troubleshooting Toolkit Launcher

:: Set UTF-8 code page
chcp 65001 >nul

:: Check for Administrative Privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ===============================================================================
    echo   ELEVATION REQUIRED: Requesting Administrator Privileges...
    echo ===============================================================================
    echo.
    powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: Change to the toolkit root directory
cd /d "%~dp0"

:: Launch main PowerShell application
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0main.ps1"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] The toolkit terminated with an error code: %errorlevel%
    pause
)

exit /b %errorlevel%

