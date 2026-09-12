[CmdletBinding()]
param(
    [string]$OutputRoot = (Get-Location).Path,
    [int]$EventHours = 6
)

$ErrorActionPreference = 'Continue'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputDir = Join-Path $OutputRoot "collection-$timestamp"
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

function Save-Section {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [scriptblock]$Action
    )

    $path = Join-Path $outputDir $Name
    try {
        & $Action 2>&1 | Out-File -FilePath $path -Encoding utf8 -Width 300
    }
    catch {
        "ERROR: $($_.Exception.Message)" | Out-File -FilePath $path -Encoding utf8
    }
}

Save-Section 'computer.txt' {
    Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber,
        CsManufacturer, CsModel, CsSystemType, CsProcessors, CsTotalPhysicalMemory,
        BiosManufacturer, BiosName, BiosSMBIOSBIOSVersion, BiosReleaseDate |
        Format-List
}

Save-Section 'bios.txt' {
    Get-CimInstance Win32_BIOS | Format-List Manufacturer, SMBIOSBIOSVersion, ReleaseDate, SerialNumber
}

Save-Section 'problem-devices.txt' {
    pnputil /enum-devices /problem
}

Save-Section 'firmware-devices.txt' {
    Get-PnpDevice -Class Firmware | Format-List FriendlyName, Status, Class, InstanceId, Problem, ConfigManagerErrorCode
}

Save-Section 'storage.txt' {
    Get-PhysicalDisk | Format-List FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, Size
    Get-PhysicalDisk | Get-StorageReliabilityCounter |
        Format-List DeviceId, Temperature, PowerOnHours, Wear, ReadErrorsTotal, ReadErrorsUncorrected, WriteErrorsTotal, WriteErrorsUncorrected
}

Save-Section 'pagefile-and-dumps.txt' {
    Get-CimInstance Win32_PageFileSetting | Format-List Name, InitialSize, MaximumSize
    Get-CimInstance Win32_PageFileUsage | Format-List Name, AllocatedBaseSize, CurrentUsage, PeakUsage
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' |
        Select-Object CrashDumpEnabled, DumpFile, MinidumpDir, AutoReboot, AlwaysKeepMemoryDump |
        Format-List
}

Save-Section 'powercfg-a.txt' {
    powercfg /a
}

Save-Section 'bitlocker.txt' {
    manage-bde -status C:
}

Save-Section 'recent-system-events.txt' {
    $start = (Get-Date).AddHours(-1 * $EventHours)
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $start } |
        Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message |
        Format-List
}

Save-Section 'recent-application-events.txt' {
    $start = (Get-Date).AddHours(-1 * $EventHours)
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $start } |
        Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message |
        Format-List
}

# Keep binary event logs locally for deeper analysis. The repository ignores collection-* folders.
$milliseconds = $EventHours * 60 * 60 * 1000
wevtutil epl System (Join-Path $outputDir 'System.evtx') "/q:*[System[TimeCreated[timediff(@SystemTime) <= $milliseconds]]]" 2>$null
wevtutil epl Application (Join-Path $outputDir 'Application.evtx') "/q:*[System[TimeCreated[timediff(@SystemTime) <= $milliseconds]]]" 2>$null

$metadata = [ordered]@{
    CollectedAtLocal = (Get-Date).ToString('o')
    EventHours       = $EventHours
    OutputDirectory  = $outputDir
    ComputerName     = $env:COMPUTERNAME
    UserName         = $env:USERNAME
}
$metadata.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value } |
    Out-File (Join-Path $outputDir 'collection-metadata.txt') -Encoding utf8

Write-Host "Collection complete: $outputDir"
Write-Host 'Review for sensitive information before publishing anything from this folder.'
