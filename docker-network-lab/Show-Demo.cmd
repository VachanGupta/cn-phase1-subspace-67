@echo off
setlocal
cd /d "%~dp0"
echo Running the Docker lab live. Both test phases will print results here.
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Run-Lab.ps1"
set "result=%errorlevel%"
echo.
echo Demo exit code: %result%
pause
exit /b %result%
