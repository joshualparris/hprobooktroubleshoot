[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:ProgramFiles 'WindowsCrashDoctor'),
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Windows Crash Doctor installation must be run from an elevated PowerShell window.'
}

Write-Host 'Installing Windows Crash Doctor...' -ForegroundColor Cyan
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

$required = @(
    'WindowsCrashDoctor.psm1',
    'windows-crash-doctor.ps1',
    'canary.ps1',
    'config.default.json',
    'uninstall.ps1'
)

foreach ($name in $required) {
    $source = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Required install file is missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $InstallRoot $name) -Force
}

foreach ($dirName in @('lib','profiles')) {
    $sourceDir = Join-Path $PSScriptRoot $dirName
    if (-not (Test-Path -LiteralPath $sourceDir)) {
        throw "Required install directory is missing: $sourceDir"
    }
    $destDir = Join-Path $InstallRoot $dirName
    Remove-Item -LiteralPath $destDir -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $sourceDir -Destination $InstallRoot -Recurse -Force
}

# Preserve one source of truth: install the repository's existing deep collector
# rather than maintaining a second copy in the app source.
$collectorCandidates = @(
    (Join-Path $PSScriptRoot 'collect-diagnostics.ps1'),
    (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\collect-diagnostics.ps1')
)
$collector = $collectorCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($collector) {
    Copy-Item -LiteralPath $collector -Destination (Join-Path $InstallRoot 'collect-diagnostics.ps1') -Force
} else {
    Write-Warning 'Deep snapshot collector was not found. Core Crash Doctor features will still work.'
}

$cmd = @'
@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows-crash-doctor.ps1" %*
'@
Set-Content -LiteralPath (Join-Path $InstallRoot 'wcd.cmd') -Value $cmd -Encoding ASCII

$modulePath = Join-Path $InstallRoot 'WindowsCrashDoctor.psm1'
Import-Module $modulePath -Force
$paths = Initialize-WcdDataRoot

$taskName = 'WindowsCrashDoctor-Canary'
try {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    $canaryPath = Join-Path $InstallRoot 'canary.ps1'
    $args = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $canaryPath
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
        -Description 'Windows Crash Doctor rolling canary and post-freeze incident reconstruction.' | Out-Null
} catch {
    throw "Failed to register the Crash Doctor canary scheduled task: $($_.Exception.Message)"
}

# A Start Menu shortcut gives the ProBook a visible entry without modifying PATH.
try {
    $startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
    $shortcutPath = Join-Path $startMenu 'Windows Crash Doctor.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = 'powershell.exe'
    $shortcut.Arguments = '-NoExit -NoProfile -ExecutionPolicy Bypass -File "{0}" doctor' -f (Join-Path $InstallRoot 'windows-crash-doctor.ps1')
    $shortcut.WorkingDirectory = $InstallRoot
    $shortcut.Description = 'Run Windows Crash Doctor diagnostics'
    $shortcut.Save()
} catch {
    Write-Warning "Could not create Start Menu shortcut: $($_.Exception.Message)"
}

if (-not $NoStart) {
    try {
        Start-ScheduledTask -TaskName $taskName
        Start-Sleep -Seconds 2
    } catch {
        Write-Warning "Canary task was installed but could not be started immediately: $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host 'Windows Crash Doctor installed.' -ForegroundColor Green
Write-Host "Install: $InstallRoot"
Write-Host "Data:    $($paths.Root)"
Write-Host ''
Write-Host 'Useful commands:'
Write-Host ('  & "{0}" status' -f (Join-Path $InstallRoot 'wcd.cmd'))
Write-Host ('  & "{0}" doctor' -f (Join-Path $InstallRoot 'wcd.cmd'))
Write-Host ('  & "{0}" collect' -f (Join-Path $InstallRoot 'wcd.cmd'))
Write-Host ''
Write-Host 'The canary now starts automatically with Windows and records incrementally so a hard freeze still leaves pre-freeze evidence.'
