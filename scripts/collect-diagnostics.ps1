# HP ProBook 11 G2 diagnostic snapshot
# Collection is read-only apart from files written beneath OutputRoot. Run elevated for the most complete result.

[CmdletBinding()]
param(
    [string]$OutputRoot = ([Environment]::GetFolderPath('Desktop')),

    [ValidateRange(1, 168)]
    [int]$EventHours = 6,

    [string]$SensorCsvPath,

    # Used by the non-elevated runner to receive the exact snapshot path from an elevated collector process.
    [string]$ResultPathFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    throw 'OutputRoot cannot be empty.'
}
if (-not [string]::IsNullOrWhiteSpace($SensorCsvPath) -and -not (Test-Path -LiteralPath $SensorCsvPath -PathType Leaf)) {
    throw "Sensor CSV was requested but does not exist: $SensorCsvPath"
}

New-Item -ItemType Directory -Path $OutputRoot -Force -ErrorAction Stop | Out-Null
$resolvedOutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
$collectionId = [guid]::NewGuid().ToString('N')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $resolvedOutputRoot ('HPProBook-{0}-{1}' -f $stamp, $collectionId.Substring(0, 8))
New-Item -ItemType Directory -Path $out -ErrorAction Stop | Out-Null

$failures = New-Object System.Collections.Generic.List[object]

function Add-WcdCollectionFailure {
    param(
        [Parameter(Mandatory = $true)] [string]$Stage,
        [Parameter(Mandatory = $true)] [System.Exception]$Exception
    )

    $message = ([string]$Exception.Message).Replace("`r", ' ').Replace("`n", ' ')
    $failures.Add([pscustomobject][ordered]@{
        Stage   = $Stage
        Message = $message
    })
}

function Save-WcdSection {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [scriptblock]$Action
    )

    $path = Join-Path $out $Name
    try {
        & $Action 2>&1 | Out-File -LiteralPath $path -Encoding utf8 -Width 300 -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        Add-WcdCollectionFailure -Stage $Name -Exception $_.Exception
        "Collection failed for '$Name': $($_.Exception.Message)" |
            Out-File -LiteralPath (Join-Path $out ($Name + '.error.txt')) -Encoding utf8 -Width 300
    }
}

function Invoke-WcdNativeTextCommand {
    param(
        [Parameter(Mandatory = $true)] [string]$FilePath,
        [string[]]$Arguments = @()
    )

    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$(Split-Path -Leaf $FilePath) exited with code $exitCode."
    }
    return $output
}

function Invoke-WcdNativeFileCommand {
    param(
        [Parameter(Mandatory = $true)] [string]$Stage,
        [Parameter(Mandatory = $true)] [string]$FilePath,
        [string[]]$Arguments = @()
    )

    try {
        & $FilePath @Arguments 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "$(Split-Path -Leaf $FilePath) exited with code $LASTEXITCODE."
        }
    }
    catch {
        Add-WcdCollectionFailure -Stage $Stage -Exception $_.Exception
    }
}

Save-WcdSection 'computer-system.txt' { Get-CimInstance Win32_ComputerSystem | Format-List * }
Save-WcdSection 'os.txt' {
    Get-CimInstance Win32_OperatingSystem |
        Format-List Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime, LocalDateTime
}
Save-WcdSection 'baseboard.txt' { Get-CimInstance Win32_BaseBoard | Format-List * }
Save-WcdSection 'bios.txt' { Get-CimInstance Win32_BIOS | Format-List * }
Save-WcdSection 'cpu.txt' { Get-CimInstance Win32_Processor | Format-List * }
Save-WcdSection 'memory.txt' { Get-CimInstance Win32_PhysicalMemory | Format-List * }
Save-WcdSection 'memory-pressure.txt' {
    Get-CimInstance Win32_OperatingSystem |
        Select-Object TotalVisibleMemorySize, FreePhysicalMemory, TotalVirtualMemorySize, FreeVirtualMemory |
        Format-List
    Get-Counter '\Memory\Available MBytes', '\Memory\Committed Bytes', '\Memory\% Committed Bytes In Use' -MaxSamples 3 -SampleInterval 1 |
        Select-Object -ExpandProperty CounterSamples |
        Select-Object Path, CookedValue |
        Format-Table -AutoSize
}

Save-WcdSection 'pagefile-and-dumps.txt' {
    Get-CimInstance Win32_ComputerSystem | Format-List AutomaticManagedPagefile
    Get-CimInstance Win32_PageFileSetting | Format-List Name, InitialSize, MaximumSize
    Get-CimInstance Win32_PageFileUsage | Format-List Name, AllocatedBaseSize, CurrentUsage, PeakUsage
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' |
        Select-Object CrashDumpEnabled, DumpFile, MinidumpDir, AutoReboot, AlwaysKeepMemoryDump |
        Format-List
}

Save-WcdSection 'physical-disks.txt' { Get-PhysicalDisk | Format-List * }
Save-WcdSection 'storage-reliability.txt' { Get-PhysicalDisk | Get-StorageReliabilityCounter | Format-List * }
Save-WcdSection 'powercfg-a.txt' { Invoke-WcdNativeTextCommand 'powercfg.exe' @('/a') }
Save-WcdSection 'powercfg-lastwake.txt' { Invoke-WcdNativeTextCommand 'powercfg.exe' @('/lastwake') }
Save-WcdSection 'powercfg-waketimers.txt' { Invoke-WcdNativeTextCommand 'powercfg.exe' @('/waketimers') }
Save-WcdSection 'bitlocker-status.txt' { Invoke-WcdNativeTextCommand 'manage-bde.exe' @('-status', 'C:') }
Save-WcdSection 'problem-devices.txt' { Invoke-WcdNativeTextCommand 'pnputil.exe' @('/enum-devices', '/problem') }
Save-WcdSection 'firmware-devices.txt' {
    Get-PnpDevice -Class Firmware | Format-List FriendlyName, Status, Class, InstanceId, Problem, ConfigManagerErrorCode
}
Save-WcdSection 'published-drivers.txt' { Invoke-WcdNativeTextCommand 'pnputil.exe' @('/enum-drivers') }

Save-WcdSection 'interesting-services.txt' {
    Get-Service | Where-Object {
        ($_.Name -match 'XTU|Cx|Conex|WirelessButton|HP') -or ($_.DisplayName -match 'XTU|Conex|Wireless Button|HP')
    } | Sort-Object Name | Format-Table -AutoSize
}

Save-WcdSection 'interesting-drivers.txt' {
    Get-CimInstance Win32_SystemDriver | Where-Object {
        ($_.Name -match 'XTU|Cx|Conex|HP|Intel') -or
        ($_.DisplayName -match 'XTU|Conex|HP|Intel') -or
        ($_.PathName -match 'XTU|Conex|Cx|HP')
    } | Sort-Object Name |
        Select-Object Name, DisplayName, State, StartMode, PathName |
        Format-Table -AutoSize
}

$start = (Get-Date).AddHours(-1 * $EventHours)
Save-WcdSection 'recent-system-events.txt' {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $start } -ErrorAction Stop |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Format-List
}
Save-WcdSection 'recent-application-events.txt' {
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $start } -ErrorAction Stop |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Format-List
}

$milliseconds = [int64]$EventHours * 60 * 60 * 1000
$eventQuery = "*[System[TimeCreated[timediff(@SystemTime) <= $milliseconds]]]"
$systemEvtx = Join-Path $out 'System.evtx'
$applicationEvtx = Join-Path $out 'Application.evtx'
Invoke-WcdNativeFileCommand -Stage 'System.evtx' -FilePath 'wevtutil.exe' -Arguments @('epl', 'System', $systemEvtx, "/q:$eventQuery")
Invoke-WcdNativeFileCommand -Stage 'Application.evtx' -FilePath 'wevtutil.exe' -Arguments @('epl', 'Application', $applicationEvtx, "/q:$eventQuery")

try {
    Copy-Item -LiteralPath "$env:WINDIR\INF\setupapi.dev.log" -Destination (Join-Path $out 'setupapi.dev.log') -ErrorAction Stop
}
catch { Add-WcdCollectionFailure -Stage 'setupapi.dev.log' -Exception $_.Exception }

Invoke-WcdNativeFileCommand -Stage 'battery-report.html' -FilePath 'powercfg.exe' -Arguments @('/batteryreport', '/output', (Join-Path $out 'battery-report.html'))
Invoke-WcdNativeFileCommand -Stage 'systempower-report.html' -FilePath 'powercfg.exe' -Arguments @('/systempowerreport', '/output', (Join-Path $out 'systempower-report.html'))

try {
    $msinfoReport = Join-Path $out 'msinfo32.nfo'
    $process = Start-Process -FilePath 'msinfo32.exe' -ArgumentList @('/nfo', ('"{0}"' -f $msinfoReport)) -Wait -PassThru -NoNewWindow -ErrorAction Stop
    if ($process.ExitCode -ne 0) { throw "msinfo32.exe exited with code $($process.ExitCode)." }
}
catch { Add-WcdCollectionFailure -Stage 'msinfo32.nfo' -Exception $_.Exception }

$sensorCsvAttached = $false
if (-not [string]::IsNullOrWhiteSpace($SensorCsvPath)) {
    try {
        Copy-Item -LiteralPath $SensorCsvPath -Destination (Join-Path $out 'sensors.csv') -Force -ErrorAction Stop
        $sensorCsvAttached = $true
    }
    catch { Add-WcdCollectionFailure -Stage 'sensors.csv' -Exception $_.Exception }
}

$metadata = [ordered]@{
    SchemaVersion     = '1.0'
    CollectionId      = $collectionId
    CollectedAtLocal  = (Get-Date).ToString('o')
    EventHours        = $EventHours
    SensorCsvAttached = $sensorCsvAttached
}
$metadata.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value } |
    Out-File -LiteralPath (Join-Path $out 'collection-metadata.txt') -Encoding utf8

$status = [pscustomobject][ordered]@{
    SchemaVersion       = '1.0'
    CollectionId        = $collectionId
    CompletedAt         = (Get-Date).ToString('o')
    CompletedWithErrors = ($failures.Count -gt 0)
    FailureCount        = $failures.Count
    Failures            = $failures.ToArray()
}
$status | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $out 'collection-status.json') -Encoding utf8 -Width 1000

if (-not [string]::IsNullOrWhiteSpace($ResultPathFile)) {
    $resultParent = Split-Path -Parent ([IO.Path]::GetFullPath($ResultPathFile))
    if (-not [string]::IsNullOrWhiteSpace($resultParent)) {
        New-Item -ItemType Directory -Path $resultParent -Force -ErrorAction Stop | Out-Null
    }
    $temporaryResult = "$ResultPathFile.$collectionId.tmp"
    $out | Set-Content -LiteralPath $temporaryResult -Encoding UTF8 -ErrorAction Stop
    Move-Item -LiteralPath $temporaryResult -Destination $ResultPathFile -Force -ErrorAction Stop
}

Write-Host "Saved diagnostic snapshot to $out"
if ($failures.Count -gt 0) {
    Write-Warning "Collection completed with $($failures.Count) failed stage(s). See collection-status.json."
}
if (-not $sensorCsvAttached) {
    Write-Host 'Optional: rerun with -SensorCsvPath <HWiNFO CSV> to let Crash Doctor correlate sensor telemetry.'
}
Write-Host 'Review the folder for sensitive information before publishing any file from it.'
