@echo off
setlocal
set "WCD_INSTALLER=%TEMP%\Install-WindowsCrashDoctorGui.ps1"
echo Downloading Windows Crash Doctor installer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/joshualparris/hprobooktroubleshoot/main/scripts/Install-WindowsCrashDoctorGui.ps1' -OutFile '%WCD_INSTALLER%'"
if errorlevel 1 goto :fail
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WCD_INSTALLER%"
if errorlevel 1 goto :fail
exit /b 0
:fail
echo.
echo Windows Crash Doctor installation did not complete.
pause
exit /b 1
