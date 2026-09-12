function Get-WcdVersion {
    return $script:WcdVersion
}

function Get-WcdDataRoot {
    if ($env:WCD_DATA_ROOT) {
        return $env:WCD_DATA_ROOT
    }
    if (-not $env:ProgramData) {
        return (Join-Path $env:TEMP 'WindowsCrashDoctor')
    }
    return (Join-Path $env:ProgramData 'WindowsCrashDoctor')
}

function Get-WcdPaths {
    $root = Get-WcdDataRoot
    [pscustomobject]@{
        Root        = $root
        Canary      = Join-Path $root 'canary'
        Incidents   = Join-Path $root 'incidents'
        Reports     = Join-Path $root 'reports'
        Experiments = Join-Path $root 'experiments'
        Logs        = Join-Path $root 'logs'
        State       = Join-Path $root 'state.json'
        Config      = Join-Path $root 'config.json'
        Ledger      = Join-Path $root 'ledger.jsonl'
    }
}

function Initialize-WcdDataRoot {
    $paths = Get-WcdPaths
    @($paths.Root, $paths.Canary, $paths.Incidents, $paths.Reports, $paths.Experiments, $paths.Logs) | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }

    if (-not (Test-Path -LiteralPath $paths.Config)) {
        $defaultConfig = Join-Path $script:ModuleRoot 'config.default.json'
        if (Test-Path -LiteralPath $defaultConfig) {
            Copy-Item -LiteralPath $defaultConfig -Destination $paths.Config -Force
        } else {
            @{
                SchemaVersion = 1
                SampleIntervalSeconds = 10
                WarningIntervalSeconds = 2
                WarningDurationSeconds = 120
                WarningCpuPercent = 95
                WarningMemoryPercent = 90
                WarningDiskQueue = 4
                IncidentPreWindowMinutes = 30
                IncidentPostWindowMinutes = 5
                RetentionDays = 14
                MaxCanaryFileMB = 25
                IncludeGpu = $false
                IncludeThermal = $false
            } | ConvertTo-Json | Set-Content -LiteralPath $paths.Config -Encoding UTF8
        }
    }
    return $paths
}

function Get-WcdConfig {
    $paths = Initialize-WcdDataRoot
    try {
        return (Get-Content -LiteralPath $paths.Config -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        throw "Windows Crash Doctor config is unreadable: $($paths.Config). $($_.Exception.Message)"
    }
}

function Write-WcdJson {
    param(
        [Parameter(Mandatory=$true)]$InputObject,
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$Depth = 8
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $InputObject | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-WcdJsonLine {
    param(
        [Parameter(Mandatory=$true)]$InputObject,
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$Depth = 6
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $line = $InputObject | ConvertTo-Json -Depth $Depth -Compress
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Write-WcdLedgerEntry {
    param(
        [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$true)]$Data
    )
    $paths = Initialize-WcdDataRoot
    Write-WcdJsonLine -Path $paths.Ledger -InputObject ([pscustomobject]@{
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
        Type = $Type
        Data = $Data
    })
}

function Get-WcdBootTimeUtc {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        return ([DateTime]$os.LastBootUpTime).ToUniversalTime()
    } catch {
        return [DateTime]::UtcNow
    }
}

function Get-WcdBootId {
    $boot = Get-WcdBootTimeUtc
    return $boot.ToString('yyyyMMddTHHmmssZ')
}

function Get-WcdState {
    $paths = Initialize-WcdDataRoot
    if (-not (Test-Path -LiteralPath $paths.State)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $paths.State -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Set-WcdState {
    param([Parameter(Mandatory=$true)]$State)
    $paths = Initialize-WcdDataRoot
    Write-WcdJson -InputObject $State -Path $paths.State -Depth 8
}

function Get-WcdTemperatureC {
    try {
        $temps = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        $values = @($temps | ForEach-Object {
            if ($_.CurrentTemperature -gt 0) {
                [Math]::Round((($_.CurrentTemperature / 10.0) - 273.15), 1)
            }
        } | Where-Object { $_ -gt -50 -and $_ -lt 150 })
        if ($values.Count -gt 0) {
            return [Math]::Round(($values | Measure-Object -Maximum).Maximum, 1)
        }
    } catch {}
    return $null
}

function Get-WcdGpuPercent {
    try {
        $engines = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop
        $values = @($engines | Where-Object { $_.Name -match 'engtype_(3D|Compute)' } | Select-Object -ExpandProperty UtilizationPercentage)
        if ($values.Count -eq 0) {
            $values = @($engines | Select-Object -ExpandProperty UtilizationPercentage)
        }
        if ($values.Count -gt 0) {
            $max = ($values | Measure-Object -Maximum).Maximum
            if ($max -gt 100) { $max = 100 }
            return [int]$max
        }
    } catch {}
    return $null
}

function Get-WcdCanarySample {
    param(
        [switch]$IncludeGpu,
        [switch]$IncludeThermal
    )
    $started = [System.Diagnostics.Stopwatch]::StartNew()
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $page = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
    $disk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue

    $memoryUsedPercent = $null
    $commitUsedPercent = $null
    if ($os -and $os.TotalVisibleMemorySize -gt 0) {
        $memoryUsedPercent = [Math]::Round((1 - ($os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize)) * 100, 1)
    }
    try {
        $memPerf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        if ($memPerf.CommitLimit -gt 0) {
            $commitUsedPercent = [Math]::Round(($memPerf.CommittedBytes / [double]$memPerf.CommitLimit) * 100, 1)
        }
    } catch {}

    $systemDrive = $env:SystemDrive
    if (-not $systemDrive) { $systemDrive = 'C:' }
    $escapedDrive = $systemDrive.Replace('\','')
    $logical = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $escapedDrive) -ErrorAction SilentlyContinue
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1

    $pageAllocated = 0
    $pageUsed = 0
    if ($page.Count -gt 0) {
        $pageAllocated = [int](($page | Measure-Object -Property AllocatedBaseSize -Sum).Sum)
        $pageUsed = [int](($page | Measure-Object -Property CurrentUsage -Sum).Sum)
    }

    $topMemory = Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 1

    $sample = [ordered]@{
        SchemaVersion = 1
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
        BootId = Get-WcdBootId
        UptimeSeconds = if ($os) { [int](([DateTime]::Now - [DateTime]$os.LastBootUpTime).TotalSeconds) } else { $null }
        CpuPercent = if ($cpu) { [int]$cpu.LoadPercentage } else { $null }
        MemoryUsedPercent = $memoryUsedPercent
        CommitUsedPercent = $commitUsedPercent
        PagefileAllocatedMB = $pageAllocated
        PagefileUsedMB = $pageUsed
        DiskQueue = if ($disk) { [Math]::Round([double]$disk.AvgDiskQueueLength, 2) } else { $null }
        DiskPercent = if ($disk) { [int]$disk.PercentDiskTime } else { $null }
        DiskBytesPerSec = if ($disk) { [int64]$disk.DiskBytesPersec } else { $null }
        SystemDriveFreeGB = if ($logical) { [Math]::Round($logical.FreeSpace / 1GB, 2) } else { $null }
        BatteryPercent = if ($battery) { [int]$battery.EstimatedChargeRemaining } else { $null }
        BatteryStatus = if ($battery) { [int]$battery.BatteryStatus } else { $null }
        TopMemoryProcess = if ($topMemory) { $topMemory.ProcessName } else { $null }
        TopMemoryMB = if ($topMemory) { [Math]::Round($topMemory.WorkingSet64 / 1MB, 1) } else { $null }
        GpuPercent = $null
        TemperatureC = $null
        SampleDurationMs = 0
    }

    if ($IncludeGpu) { $sample.GpuPercent = Get-WcdGpuPercent }
    if ($IncludeThermal) { $sample.TemperatureC = Get-WcdTemperatureC }

    $started.Stop()
    $sample.SampleDurationMs = [int]$started.ElapsedMilliseconds
    return [pscustomobject]$sample
}

function Test-WcdWarningSample {
    param(
        [Parameter(Mandatory=$true)]$Sample,
        [Parameter(Mandatory=$true)]$Config
    )
    if ($null -ne $Sample.CpuPercent -and $Sample.CpuPercent -ge [int]$Config.WarningCpuPercent) { return $true }
    if ($null -ne $Sample.MemoryUsedPercent -and $Sample.MemoryUsedPercent -ge [double]$Config.WarningMemoryPercent) { return $true }
    if ($null -ne $Sample.DiskQueue -and $Sample.DiskQueue -ge [double]$Config.WarningDiskQueue) { return $true }
    return $false
}

function Remove-WcdExpiredData {
    $config = Get-WcdConfig
    $paths = Get-WcdPaths
    $cutoff = (Get-Date).AddDays(-[int]$config.RetentionDays)
    @($paths.Canary, $paths.Incidents, $paths.Reports, $paths.Logs) | ForEach-Object {
        if (Test-Path -LiteralPath $_) {
            Get-ChildItem -LiteralPath $_ -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

function Rotate-WcdCanaryFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)]$Config
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($item -and $item.Length -ge ([double]$Config.MaxCanaryFileMB * 1MB)) {
        $archive = Join-Path $item.DirectoryName ("canary-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Move-Item -LiteralPath $Path -Destination $archive -Force
    }
    return $Path
}

function Get-WcdRecentCanary {
    param(
        [int]$Minutes = 30,
        [DateTime]$EndUtc = ([DateTime]::UtcNow)
    )
    $paths = Initialize-WcdDataRoot
    $start = $EndUtc.AddMinutes(-$Minutes)
    $result = New-Object System.Collections.Generic.List[object]
    $files = Get-ChildItem -LiteralPath $paths.Canary -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 4

    foreach ($file in $files) {
        foreach ($line in Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                $ts = [DateTime]::Parse($row.TimestampUtc).ToUniversalTime()
                if ($ts -ge $start -and $ts -le $EndUtc) {
                    $result.Add($row)
                }
            } catch {}
        }
    }
    return @($result | Sort-Object TimestampUtc)
}

