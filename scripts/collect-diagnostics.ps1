# HP ProBook 11 G2 diagnostic snapshot
# Read-only apart from writing output files. Run elevated for the most complete result.

[CmdletBinding()]
param(
    [string]$OutputRoot = ([Environment]::GetFolderPath('Desktop')),
    [int]$EventHours = 6
)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $OutputRoot "HPProBook-$stamp"
New-Item -ItemType Directory -Path $out -Force | Out-Null

function Save-Section {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [scriptblock]$Action
    )

    $path = Join-Path $out $Name
    try {
        & $Action 2>&1 | Out-File -FilePath $path -Encoding utf8 -Width 300
    }
    catch {
        "ERROR: $($_.Exception.Message)" | Out-File -FilePath $path -Encoding utf8
    }
}

Save-Section 'computer-system.txt' { Get-CimInstance Win32_ComputerSystem | Format-List * }
Save-Section 'baseboard.txt' { Get-CimInstance Win32_BaseBoard | Format-List * }
Save-Section 'bios.txt' { Get-CimInstance Win32_BIOS | Format-List * }
Save-Section 'cpu.txt' { Get-CimInstance Win32_Processor | Format-List * }
Save-Section 'memory.txt' { Get-CimInstance Win32_PhysicalMemory | Format-List * }

Save-Section 'pagefile-and-dumps.txt' {
    Get-CimInstance Win32_PageFileSetting | Format-List Name, InitialSize, MaximumSize
    Get-CimInstance Win32_PageFileUsage | Format-List Name, AllocatedBaseSize, CurrentUsage, PeakUsage
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' |
        Select-Object CrashDumpEnabled, DumpFile, MinidumpDir, AutoReboot, AlwaysKeepMemoryDump |
        Format-List
}

Save-Section 'physical-disks.txt' { Get-PhysicalDisk | Format-List * }
Save-Section 'storage-reliability.txt' {
    Get-PhysicalDisk | Get-StorageReliabilityCounter | Format-List *
}

Save-Section 'powercfg-a.txt' { powercfg /a }
Save-Section 'powercfg-lastwake.txt' { powercfg /lastwake }
Save-Section 'powercfg-waketimers.txt' { powercfg /waketimers }
Save-Section 'bitlocker-status.txt' { manage-bde -status C: }
Save-Section 'problem-devices.txt' { pnputil /enum-devices /problem }
Save-Section 'firmware-devices.txt' { Get-PnpDevice -Class Firmware | Format-List * }

Save-Section 'interesting-services.txt' {
    Get-Service | Where-Object {
        $_.Name -match 'XTU|Cx|Conex|WirelessButton|HP' -or
        $_.DisplayName -match 'XTU|Conex|Wireless Button|HP'
    } | Sort-Object Name | Format-Table -AutoSize
}

$start = (Get-Date).AddHours(-1 * $EventHours)
Save-Section 'recent-system-events.txt' {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $start } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Format-List
}
Save-Section 'recent-application-events.txt' {
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $start } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Format-List
}

# Preserve recent binary event logs locally for deeper analysis.
$milliseconds = $EventHours * 60 * 60 * 1000
wevtutil epl System (Join-Path $out 'System.evtx') "/q:*[System[TimeCreated[timediff(@SystemTime) <= $milliseconds]]]" 2>$null
wevtutil epl Application (Join-Path $out 'Application.evtx') "/q:*[System[TimeCreated[timediff(@SystemTime) <= $milliseconds]]]" 2>$null

Copy-Item "$env:WINDIR\INF\setupapi.dev.log" (Join-Path $out 'setupapi.dev.log') -ErrorAction SilentlyContinue
powercfg /batteryreport /output (Join-Path $out 'battery-report.html') | Out-Null
powercfg /systempowerreport /output (Join-Path $out 'systempower-report.html') | Out-Null
Start-Process -FilePath 'msinfo32.exe' -ArgumentList '/nfo', (Join-Path $out 'msinfo32.nfo') -Wait -NoNewWindow

[ordered]@{
    CollectedAtLocal = (Get-Date).ToString('o')
    EventHours       = $EventHours
    ComputerName     = $env:COMPUTERNAME
    UserName         = $env:USERNAME
    OutputDirectory  = $out
}.GetEnumerator() | ForEach-Object {
    '{0}={1}' -f $_.Key, $_.Value
} | Out-File (Join-Path $out 'collection-metadata.txt') -Encoding utf8

Write-Host "Saved diagnostic snapshot to $out"
Write-Host 'Review the folder for sensitive information before publishing any file from it.'
