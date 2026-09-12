@echo off
setlocal
echo Windows Crash Doctor bootstrap
echo ==============================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $h=@{'User-Agent'='Windows-Crash-Doctor';'Accept'='application/vnd.github+json'}; $sha=[string](Invoke-RestMethod -Uri 'https://api.github.com/repos/joshualparris/hprobooktroubleshoot/commits/main' -Headers $h -TimeoutSec 30).sha; if($sha -notmatch '^[0-9a-fA-F]{40}$'){throw 'GitHub returned an invalid main commit SHA.'}; $p=Join-Path $env:TEMP ('Install-WindowsCrashDoctor-'+[guid]::NewGuid().ToString('N')+'.ps1'); try { $u='https://raw.githubusercontent.com/joshualparris/hprobooktroubleshoot/'+$sha+'/scripts/Install-WindowsCrashDoctor.ps1'; Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p -TimeoutSec 60; if((Get-Item -LiteralPath $p).Length -gt 1048576){throw 'Installer script exceeds the 1 MiB safety limit.'}; & $p -CommitSha $sha; if(-not $?){exit 1} } finally { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" echo Installation failed with code %EXITCODE%.
echo Press any key to close this window.
pause >nul
exit /b %EXITCODE%
