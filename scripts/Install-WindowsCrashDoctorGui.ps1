[CmdletBinding()]
param(
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$releaseUrl = 'https://github.com/joshualparris/hprobooktroubleshoot/releases/download/windows-crash-doctor-desktop-latest/WindowsCrashDoctor.exe'
$installRoot = Join-Path $env:LOCALAPPDATA 'WindowsCrashDoctor\app'
$exePath = Join-Path $installRoot 'WindowsCrashDoctor.exe'
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Windows Crash Doctor.lnk'

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
$temp = Join-Path $env:TEMP ('WindowsCrashDoctor-' + [guid]::NewGuid().ToString('N') + '.exe')

Write-Host 'Downloading Windows Crash Doctor Desktop…' -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing -Uri $releaseUrl -OutFile $temp
if ((Get-Item $temp).Length -lt 1000000) {
    Remove-Item $temp -Force -ErrorAction SilentlyContinue
    throw 'The downloaded file is unexpectedly small. The desktop release may still be building; try again in a minute.'
}

Copy-Item -LiteralPath $temp -Destination $exePath -Force
Remove-Item $temp -Force -ErrorAction SilentlyContinue
Unblock-File -LiteralPath $exePath -ErrorAction SilentlyContinue

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $exePath
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = 'Windows Crash Doctor'
$shortcut.Save()

Write-Host "Installed: $exePath" -ForegroundColor Green
Write-Host "Desktop shortcut: $shortcutPath" -ForegroundColor Green

if (-not $NoLaunch) {
    Start-Process -FilePath $exePath
}
