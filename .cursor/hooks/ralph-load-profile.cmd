@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%ralph-load-profile.py" (
  py -3 "%SCRIPT_DIR%ralph-load-profile.py" 2>nul
  if not errorlevel 1 exit /b 0
  python "%SCRIPT_DIR%ralph-load-profile.py" 2>nul
  if not errorlevel 1 exit /b 0
)
echo {}
exit /b 0
