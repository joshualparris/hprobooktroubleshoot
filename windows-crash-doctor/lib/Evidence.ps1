function Get-WcdEventTimeline {
    param(
        [DateTime]$StartTime = ((Get-Date).AddHours(-24)),
        [DateTime]$EndTime = (Get-Date)
    )
    $rows = New-Object System.Collections.Generic.List[object]
    $systemIds = @(1,7,11,12,13,17,18,19,20,41,42,47,51,55,129,153,161,219,4101,6008,1001,1074)
    $applicationIds = @(1000,1001,1002)

    foreach ($spec in @(
        @{ LogName='System'; Id=$systemIds },
        @{ LogName='Application'; Id=$applicationIds }
    )) {
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName=$spec.LogName
                Id=$spec.Id
                StartTime=$StartTime
                EndTime=$EndTime
            } -ErrorAction Stop
            foreach ($event in $events) {
                $message = $event.Message
                if ($message -and $message.Length -gt 800) { $message = $message.Substring(0,800) }
                $rows.Add([pscustomobject]@{
                    TimeCreatedUtc = $event.TimeCreated.ToUniversalTime().ToString('o')
                    LogName = $event.LogName
                    Provider = $event.ProviderName
                    Id = $event.Id
                    Level = $event.LevelDisplayName
                    RecordId = $event.RecordId
                    Message = $message
                })
            }
        } catch {}
    }
    return @($rows | Sort-Object TimeCreatedUtc)
}

function Get-WcdCrashCaptureReadiness {
    $system = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $pagefiles = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
    $allocated = 0
    if ($pagefiles.Count -gt 0) {
        $allocated = [int](($pagefiles | Measure-Object -Property AllocatedBaseSize -Sum).Sum)
    }

    $crash = $null
    try {
        $crash = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction Stop
    } catch {}

    $ramMb = if ($os) { [int][Math]::Round($os.TotalVisibleMemorySize / 1024) } else { $null }
    $autoPage = if ($system) { [bool]$system.AutomaticManagedPagefile } else { $null }
    $dumpMode = if ($crash) { [int]$crash.CrashDumpEnabled } else { 0 }

    $status = 'Review'
    $reasons = New-Object System.Collections.Generic.List[string]
    if ($allocated -le 0) {
        $status = 'NotReady'
        $reasons.Add('No active pagefile allocation was detected.')
    } elseif ($dumpMode -eq 0) {
        $status = 'NotReady'
        $reasons.Add('Crash dumps are disabled.')
    } elseif ($autoPage) {
        $status = 'LikelyReady'
        $reasons.Add('Windows is managing the pagefile automatically.')
    } elseif ($ramMb -and $allocated -lt 1024) {
        $status = 'Review'
        $reasons.Add('The configured pagefile is small; dump capture may be unreliable.')
    } else {
        $status = 'LikelyReady'
    }

    [pscustomobject]@{
        Status = $status
        AutomaticManagedPagefile = $autoPage
        PagefileAllocatedMB = $allocated
        PhysicalMemoryMB = $ramMb
        CrashDumpEnabled = $dumpMode
        DumpFile = if ($crash) { $crash.DumpFile } else { $null }
        MinidumpDir = if ($crash) { $crash.MinidumpDir } else { $null }
        Reasons = @($reasons)
    }
}

function Get-WcdDriverResidue {
    $disconnectedCount = $null
    $pnputilText = $null
    try {
        $pnputilText = (& pnputil.exe /enum-devices /disconnected 2>&1 | Out-String)
        $matches = [regex]::Matches($pnputilText, '(?im)^\s*Instance ID\s*:')
        $disconnectedCount = $matches.Count
    } catch {}

    $problemDevices = @()
    try {
        $problemDevices = @(Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Status -and $_.Status -ne 'OK' } |
            Select-Object -First 100 Status,Class,FriendlyName,InstanceId)
    } catch {}

    $drivers = @(Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue)
    $lowLevelPattern = 'XTU|Extreme Tuning|Conexant|ThrottleStop|WinRing|RWEverything|HWiNFO|AIDA64|Intel.*Tuning'
    $suspicious = @($drivers | Where-Object {
        ($_.Name -match $lowLevelPattern) -or ($_.DisplayName -match $lowLevelPattern) -or ($_.PathName -match $lowLevelPattern)
    } | Select-Object Name,DisplayName,State,StartMode,PathName)

    $setupPath = Join-Path $env:windir 'INF\setupapi.dev.log'
    $sysprepMentions = 0
    if (Test-Path -LiteralPath $setupPath) {
        try {
            $sysprepMentions = @((Select-String -Path $setupPath -Pattern 'Sysprep|respeciali[sz]' -CaseSensitive:$false -ErrorAction Stop)).Count
        } catch {}
    }

    [pscustomobject]@{
        DisconnectedDeviceCount = $disconnectedCount
        ProblemDeviceCount = @($problemDevices).Count
        ProblemDevices = $problemDevices
        SuspiciousLowLevelDriverCount = @($suspicious).Count
        SuspiciousLowLevelDrivers = $suspicious
        SetupApiSysprepMentions = $sysprepMentions
    }
}

function Get-WcdMachineFacts {
    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $product = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue

    $biosDate = $null
    $biosAgeYears = $null
    if ($bios -and $bios.ReleaseDate) {
        try {
            $biosDate = ([DateTime]$bios.ReleaseDate).ToUniversalTime()
            $biosAgeYears = [Math]::Round((([DateTime]::UtcNow - $biosDate).TotalDays / 365.25), 1)
        } catch {}
    }

    [pscustomobject]@{
        Manufacturer = if ($computer) { $computer.Manufacturer } else { $null }
        Model = if ($computer) { $computer.Model } else { $null }
        SystemSku = if ($computer) { $computer.SystemSKUNumber } else { $null }
        ProductName = if ($product) { $product.Name } else { $null }
        BoardProduct = if ($board) { $board.Product } else { $null }
        BiosManufacturer = if ($bios) { $bios.Manufacturer } else { $null }
        BiosVersion = if ($bios) { ($bios.SMBIOSBIOSVersion -join ', ') } else { $null }
        BiosReleaseDateUtc = if ($biosDate) { $biosDate.ToString('o') } else { $null }
        BiosAgeYears = $biosAgeYears
        OsCaption = if ($os) { $os.Caption } else { $null }
        OsVersion = if ($os) { $os.Version } else { $null }
        OsBuild = if ($os) { $os.BuildNumber } else { $null }
        LastBootUtc = if ($os) { ([DateTime]$os.LastBootUpTime).ToUniversalTime().ToString('o') } else { $null }
    }
}

function Get-WcdMachineProfile {
    param($Machine)
    if (-not $Machine) { $Machine = Get-WcdMachineFacts }
    $profileDir = Join-Path $script:ModuleRoot 'profiles'
    if (-not (Test-Path -LiteralPath $profileDir)) { return $null }

    foreach ($file in Get-ChildItem -LiteralPath $profileDir -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        try {
            $profile = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $manufacturerOk = $true
            $modelOk = $true
            if ($profile.Match.ManufacturerRegex) {
                $manufacturerOk = [bool]($Machine.Manufacturer -match $profile.Match.ManufacturerRegex)
            }
            if ($profile.Match.ModelRegex) {
                $modelOk = [bool](("$($Machine.Model) $($Machine.ProductName)") -match $profile.Match.ModelRegex)
            }
            if ($manufacturerOk -and $modelOk) {
                return $profile
            }
        } catch {}
    }
    return $null
}

function Get-WcdStorageEvidence {
    $physical = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $reliability = New-Object System.Collections.Generic.List[object]
    foreach ($disk in $physical) {
        try {
            $r = $disk | Get-StorageReliabilityCounter -ErrorAction Stop
            $reliability.Add([pscustomobject]@{
                FriendlyName = $disk.FriendlyName
                HealthStatus = $disk.HealthStatus
                OperationalStatus = ($disk.OperationalStatus -join ',')
                MediaType = $disk.MediaType
                TemperatureC = $r.Temperature
                ReadErrorsTotal = $r.ReadErrorsTotal
                WriteErrorsTotal = $r.WriteErrorsTotal
                ReadErrorsUncorrected = $r.ReadErrorsUncorrected
                WriteErrorsUncorrected = $r.WriteErrorsUncorrected
                PowerOnHours = $r.PowerOnHours
            })
        } catch {
            $reliability.Add([pscustomobject]@{
                FriendlyName = $disk.FriendlyName
                HealthStatus = $disk.HealthStatus
                OperationalStatus = ($disk.OperationalStatus -join ',')
                MediaType = $disk.MediaType
                TemperatureC = $null
                ReadErrorsTotal = $null
                WriteErrorsTotal = $null
                ReadErrorsUncorrected = $null
                WriteErrorsUncorrected = $null
                PowerOnHours = $null
            })
        }
    }
    return @($reliability)
}

function Get-WcdEvidence {
    param([int]$EventHours = 72)
    $now = Get-Date
    $events = @(Get-WcdEventTimeline -StartTime $now.AddHours(-$EventHours) -EndTime $now)
    $machine = Get-WcdMachineFacts
    [pscustomobject]@{
        CollectedUtc = [DateTime]::UtcNow.ToString('o')
        Machine = $machine
        Profile = Get-WcdMachineProfile -Machine $machine
        CrashCapture = Get-WcdCrashCaptureReadiness
        DriverResidue = Get-WcdDriverResidue
        Storage = @(Get-WcdStorageEvidence)
        CurrentSample = Get-WcdCanarySample -IncludeGpu -IncludeThermal
        Events = $events
    }
}

