# HP ProBook 11 G2 diagnostic snapshot
# Run from an elevated PowerShell. Read-only apart from writing output files.

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $env:USERPROFILE "Desktop\HPProBook-$stamp"
New-Item -ItemType Directory -Path $out -Force | Out-Null

Get-CimInstance Win32_ComputerSystem | Format-List * | Out-File "$out\computer-system.txt"
Get-CimInstance Win32_BaseBoard | Format-List * | Out-File "$out\baseboard.txt"
Get-CimInstance Win32_BIOS | Format-List * | Out-File "$out\bios.txt"
Get-CimInstance Win32_Processor | Format-List * | Out-File "$out\cpu.txt"
Get-CimInstance Win32_PhysicalMemory | Format-List * | Out-File "$out\memory.txt"
Get-CimInstance Win32_PageFileUsage | Format-List * | Out-File "$out\pagefile.txt"
Get-PhysicalDisk | Format-List * | Out-File "$out\physical-disks.txt"
Get-PhysicalDisk | Get-StorageReliabilityCounter | Format-List * | Out-File "$out\storage-reliability.txt"

powercfg /a | Out-File "$out\powercfg-a.txt"
powercfg /lastwake | Out-File "$out\powercfg-lastwake.txt"
powercfg /waketimers | Out-File "$out\powercfg-waketimers.txt"
manage-bde -status C: | Out-File "$out\bitlocker-status.txt"
pnputil /enum-devices /problem | Out-File "$out\problem-devices.txt"
Get-PnpDevice -Class Firmware | Format-List * | Out-File "$out\firmware-devices.txt"

Get-Service | Where-Object { $_.Name -match 'XTU|Cx|Conex|WirelessButton|HP' -or $_.DisplayName -match 'XTU|Conex|Wireless Button|HP' } |
    Sort-Object Name | Format-Table -AutoSize | Out-File "$out\interesting-services.txt"

$start = (Get-Date).AddHours(-4)
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
    Format-List | Out-File "$out\system-last4h.txt"
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$start} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
    Format-List | Out-File "$out\application-last4h.txt"

Copy-Item "$env:WINDIR\INF\setupapi.dev.log" "$out\setupapi.dev.log" -ErrorAction SilentlyContinue
powercfg /batteryreport /output "$out\battery-report.html" | Out-Null
powercfg /systempowerreport /output "$out\systempower-report.html" | Out-Null
msinfo32 /nfo "$out\msinfo32.nfo"

Write-Host "Saved diagnostic snapshot to $out"
