[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$PurgeData,
    [string]$InstallRoot = (Join-Path $env:ProgramFiles 'WindowsCrashDoctor')
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Uninstall must be run from an elevated PowerShell window.'
}

$taskName = 'WindowsCrashDoctor-Canary'
if ($PSCmdlet.ShouldProcess($taskName, 'Remove scheduled task')) {
    try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch {}
    try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
}

$shortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Windows Crash Doctor.lnk'
if ($PSCmdlet.ShouldProcess($shortcut, 'Remove Start Menu shortcut')) {
    Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
}

if ($PSCmdlet.ShouldProcess($InstallRoot, 'Remove application files')) {
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($PurgeData) {
    $data = if ($env:WCD_DATA_ROOT) { $env:WCD_DATA_ROOT } else { Join-Path $env:ProgramData 'WindowsCrashDoctor' }
    if ($PSCmdlet.ShouldProcess($data, 'Permanently remove diagnostic data')) {
        Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host 'Diagnostic data was kept in %ProgramData%\WindowsCrashDoctor. Use -PurgeData to remove it.' -ForegroundColor Yellow
}
