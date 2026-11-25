@echo off
setlocal
set "LAB_LOG=%~dp0launcher.log"
echo Starting the Docker lab. The first run can take several minutes.
echo Output is being saved to "%LAB_LOG%".
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Run-Lab.ps1" >"%LAB_LOG%" 2>&1
set "LAB_EXIT=%errorlevel%"
type "%LAB_LOG%"
echo.
echo Launcher exit code: %LAB_EXIT%
pause
exit /b %LAB_EXIT%
