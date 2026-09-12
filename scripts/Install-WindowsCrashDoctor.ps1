[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'WindowsCrashDoctor\App'),
    [switch]$InstallOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-WcdAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-WcdAdministrator)) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'Save this installer to a file before running it so it can request Administrator rights.'
    }

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-InstallRoot', ('"{0}"' -f $InstallRoot)
    )
    if ($InstallOnly) { $args += '-InstallOnly' }

    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($args -join ' ') -PassThru -Wait
    exit $process.ExitCode
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoZip = 'https://github.com/joshualparris/hprobooktroubleshoot/archive/refs/heads/main.zip'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('WindowsCrashDoctorInstall-' + [guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tempRoot 'WindowsCrashDoctor-main.zip'
$extractRoot = Join-Path $tempRoot 'extract'

Write-Host ''
Write-Host 'Windows Crash Doctor installer' -ForegroundColor Cyan
Write-Host '==============================' -ForegroundColor Cyan
Write-Host "Install location: $InstallRoot"
Write-Host ''

New-Item -ItemType Directory -Path $tempRoot, $extractRoot -Force | Out-Null

try {
    Write-Host '1/5 Downloading the current main build...'
    Invoke-WebRequest -Uri $repoZip -OutFile $zipPath -UseBasicParsing

    Write-Host '2/5 Extracting...'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    $source = Join-Path $extractRoot 'hprobooktroubleshoot-main'
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw 'Downloaded archive did not contain the expected hprobooktroubleshoot-main folder.'
    }

    Write-Host '3/5 Installing/updating Windows Crash Doctor...'
    $installParent = Split-Path -Parent $InstallRoot
    New-Item -ItemType Directory -Path $installParent -Force | Out-Null

    $staging = Join-Path $installParent ('App.new-' + [guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $source -Destination $staging -Recurse -Force

    if (Test-Path -LiteralPath $InstallRoot) {
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force
    }
    Move-Item -LiteralPath $staging -Destination $InstallRoot

    $runner = Join-Path $InstallRoot 'windows-crash-doctor\Run-WindowsCrashDoctor.ps1'
    $selfTest = Join-Path $InstallRoot 'windows-crash-doctor\tests\self-test.ps1'
    $integrationSelfTest = Join-Path $InstallRoot 'windows-crash-doctor\tests\integration-self-test.ps1'
    foreach ($required in @($runner, $selfTest, $integrationSelfTest)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Installation is incomplete; missing: $required"
        }
    }

    Write-Host '4/5 Creating a desktop double-click launcher...'
    $desktop = [Environment]::GetFolderPath('Desktop')
    $cmdPath = Join-Path $desktop 'Windows Crash Doctor.cmd'
    $cmd = @"
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$runner"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" echo Windows Crash Doctor exited with code %EXITCODE%.
echo Press any key to close this window.
pause >nul
exit /b %EXITCODE%
"@
    Set-Content -LiteralPath $cmdPath -Value $cmd -Encoding ASCII

    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $shortcutPath = Join-Path $startMenu 'Windows Crash Doctor.lnk'
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runner)
        $shortcut.WorkingDirectory = $InstallRoot
        $shortcut.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
        $shortcut.Description = 'Collect and analyse Windows crash/hang diagnostics'
        $shortcut.Save()
    }
    catch {
        Write-Warning "Start Menu shortcut could not be created: $($_.Exception.Message)"
    }

    Write-Host '5/5 Running installation self-tests...'
    & $selfTest -RepositoryMode
    & $integrationSelfTest

    Write-Host ''
    Write-Host 'INSTALL PASS' -ForegroundColor Green
    Write-Host "Desktop launcher: $cmdPath" -ForegroundColor Green
    Write-Host "Installed app: $InstallRoot" -ForegroundColor Green

    if (-not $InstallOnly) {
        Write-Host ''
        Write-Host 'Starting the first real ProBook diagnostic run now...' -ForegroundColor Cyan
        & $runner
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
