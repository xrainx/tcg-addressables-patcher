@echo off
REM ============================================================================
REM  TCG World Addressables Crash Patcher - by Rain
REM  Double-click this file, or run from a terminal.
REM  Best experience: Windows Terminal
REM ============================================================================
cd /d "%~dp0"
title TCG Addressables Patcher - by Rain

where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0TCG_Addressables_Patcher.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0TCG_Addressables_Patcher.ps1"
)

if errorlevel 1 (
  echo.
  echo  Patcher exited with an error.
  pause
)
