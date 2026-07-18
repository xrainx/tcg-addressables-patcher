@echo off
REM Build single-file TCG_Addressables_Patcher.exe (by Rain)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_patcher_exe.ps1"
if errorlevel 1 pause
