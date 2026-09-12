Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'FindingModel.psm1') -Force

$script:MaxSensorCsvBytes = 67108864
$script:MaxSensorRows = 100000
$script:MaxPowerReportBytes = 33554432

function New-WcdUnavailableTelemetrySource {
    param([AllowNull()] [string]$SourceFile)

    return [pscustomobject][ordered]@{
        Available  = $false
        SourceFile = $SourceFile
        Summary    = $null
        Findings   = @()
    }
}

function Get-WcdLatestEvidenceFile {
    param(
        [Parameter(Mandatory = $true)] [string]$EvidencePath,
        [Parameter(Mandatory = $true)] [string]$NamePattern
    )

    return @(
        Get-ChildItem -LiteralPath $EvidencePath -File -ErrorAction Stop |
            Where-Object { $_.Name -match $NamePattern } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    )
}

function Assert-WcdFileWithinLimit {
    param(
        [Parameter(Mandatory = $true)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)] [int64]$MaximumBytes,
        [Parameter(Mandatory = $true)] [string]$Description
    )

    if ($File.Length -gt $MaximumBytes) {
        throw "$Description '$($File.Name)' is $($File.Length) bytes, above the $MaximumBytes-byte safety limit."
    }
}

function ConvertTo-WcdInvariantNumber {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $number = 0.0
    $styles = [Globalization.NumberStyles]::Float -bor [Globalization.NumberStyles]::AllowThousands
    if ([double]::TryParse([string]$Value, $styles, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return $number
    }

    return $null
}

function Get-WcdUniqueSensorHeaders {
    param([Parameter(Mandatory = $true)] [object[]]$RawHeaders)

    if ($RawHeaders.Count -eq 0 -or $RawHeaders.Count -gt 4096) {
        throw "Sensor CSV has an invalid header count: $($RawHeaders.Count)."
    }

    $seen = @{}
    $headers = New-Object System.Collections.Generic.List[string]
    foreach ($rawHeader in $RawHeaders) {
        $header = [string]$rawHeader
        if ([string]::IsNullOrWhiteSpace($header)) {
            $header = 'Unnamed'
        }

        if ($seen.ContainsKey($header)) {
            $seen[$header]++
            $headers.Add(('{0} #{1}' -f $header, $seen[$header]))
        }
        else {
            $seen[$header] = 1
            $headers.Add($header)
        }
    }

    return $headers.ToArray()
}

function Import-WcdSensorCsv {
    param([Parameter(Mandatory = $true)] [System.IO.FileInfo]$File)

    Assert-WcdFileWithinLimit -File $File -MaximumBytes $script:MaxSensorCsvBytes -Description 'Sensor CSV'
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop

    $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser(
        $File.FullName,
        [Text.Encoding]::GetEncoding(28591),
        $true
    )
    $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
    $parser.SetDelimiters(',')
    $parser.HasFieldsEnclosedInQuotes = $true

    try {
        if ($parser.EndOfData) {
            throw "Sensor CSV '$($File.Name)' is empty."
        }

        $headers = Get-WcdUniqueSensorHeaders -RawHeaders @($parser.ReadFields())
        $rows = New-Object System.Collections.Generic.List[object]
        while (-not $parser.EndOfData) {
            if ($rows.Count -ge $script:MaxSensorRows) {
                throw "Sensor CSV exceeds the $script:MaxSensorRows-row safety limit."
            }

            try {
                $fields = @($parser.ReadFields())
            }
            catch [Microsoft.VisualBasic.FileIO.MalformedLineException] {
                throw "Malformed sensor CSV line $($parser.ErrorLineNumber)."
            }

            if ($fields.Count -eq 0) {
                continue
            }
            if ($fields.Count -ne $headers.Count) {
                throw "Sensor CSV line has $($fields.Count) field(s); expected $($headers.Count)."
            }

            $row = [ordered]@{}
            for ($index = 0; $index -lt $headers.Count; $index++) {
                $row[$headers[$index]] = $fields[$index]
            }
            $rows.Add([pscustomobject]$row)
        }

        return $rows.ToArray()
    }
    finally {
        $parser.Close()
    }
}

function Find-WcdSensorColumn {
    param(
        [Parameter(Mandatory = $true)] [object[]]$Rows,
        [Parameter(Mandatory = $true)] [string]$Pattern
    )

    if ($Rows.Count -eq 0) {
        return $null
    }

    return @(
        $Rows[0].PSObject.Properties.Name |
            Where-Object { $_ -match $Pattern } |
            Select-Object -First 1
    ) | Select-Object -First 1
}

function Find-WcdSensorColumns {
    param(
        [Parameter(Mandatory = $true)] [object[]]$Rows,
        [Parameter(Mandatory = $true)] [string]$Pattern
    )

    if ($Rows.Count -eq 0) {
        return @()
    }

    return @($Rows[0].PSObject.Properties.Name | Where-Object { $_ -match $Pattern })
}

function Get-WcdNumericSeries {
    param(
        [Parameter(Mandatory = $true)] [object[]]$Rows,
        [AllowNull()] [string]$Column
    )

    if ([string]::IsNullOrWhiteSpace($Column)) {
        return @()
    }

    return @(
        foreach ($row in $Rows) {
            $number = ConvertTo-WcdInvariantNumber $row.$Column
            if ($null -ne $number) {
                $number
            }
        }
    )
}

function Get-WcdPercentile {
    param(
        [Parameter(Mandatory = $true)] [double[]]$Values,
        [ValidateRange(0, 100)] [double]$Percentile
    )

    if ($Values.Count -eq 0) {
        return $null
    }

    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 1) {
        return [double]$sorted[0]
    }

    $position = ($Percentile / 100) * ($sorted.Count - 1)
    $lowIndex = [math]::Floor($position)
    $highIndex = [math]::Ceiling($position)
    if ($lowIndex -eq $highIndex) {
        return [double]$sorted[$lowIndex]
    }

    return ([double]$sorted[$lowIndex] * (1 - ($position - $lowIndex))) +
        ([double]$sorted[$highIndex] * ($position - $lowIndex))
}

function ConvertTo-WcdSensorTimestamp {
    param([Parameter(Mandatory = $true)]$Row)

    if ($null -eq $Row.PSObject.Properties['Date'] -or $null -eq $Row.PSObject.Properties['Time']) {
        return $null
    }

    $timestamp = [datetime]::MinValue
    $formats = [string[]]@(
        'd.M.yyyy H:m:s.fff',
        'd.M.yyyy H:m:s',
        'dd.MM.yyyy HH:mm:ss.fff',
        'yyyy-MM-dd HH:mm:ss.fff'
    )
    $text = '{0} {1}' -f $Row.Date, $Row.Time
    if ([datetime]::TryParseExact(
        $text,
        $formats,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AllowWhiteSpaces,
        [ref]$timestamp
    )) {
        return $timestamp
    }

    return $null
}

function Test-WcdPositiveFlag {
    param([AllowNull()]$Value)
    return ([string]$Value -match '^(?i:Yes|True|1)$')
}

function Get-WcdSensorColumnMap {
    param([Parameter(Mandatory = $true)] [object[]]$Rows)

    return [pscustomobject][ordered]@{
        MemoryLoad       = Find-WcdSensorColumn $Rows '^Physical Memory Load \[%\]$'
        MemoryAvailable  = Find-WcdSensorColumn $Rows '^Physical Memory Available \[MB\]$'
        VirtualMemory    = Find-WcdSensorColumn $Rows '^Virtual Memory Load \[%\]$'
        PageFileTotal    = Find-WcdSensorColumn $Rows '^Page File Total \[MB\]$'
        PageFileUsed     = Find-WcdSensorColumn $Rows '^Page File Used \[MB\]$'
        CpuUsage         = Find-WcdSensorColumn $Rows '^Total CPU Usage \[%\]$'
        CpuTemperature   = Find-WcdSensorColumn $Rows '^CPU Package \['
        WheaErrors       = Find-WcdSensorColumn $Rows '^(?:WHEA )?Total Errors \[\]$'
        DriveLife        = Find-WcdSensorColumn $Rows '^Drive Remaining Life \[%\]$'
        DriveFailure     = Find-WcdSensorColumn $Rows '^Drive Failure(?: \[Yes/No\])?$'
        DriveWarning     = Find-WcdSensorColumn $Rows '^Drive Warning(?: \[Yes/No\])?$'
        DiskActivity     = Find-WcdSensorColumn $Rows '^Total Activity \[%\]$'
        ThermalFlags     = @(Find-WcdSensorColumns $Rows '(?i)Thermal Throttling|Critical Temperature|PROCHOT')
        GpuRingLimitFlags = @(Find-WcdSensorColumns $Rows '(?i)^GT Limit Reasons|^GT: Fuses limit|^Ring Limit Reasons|^RING: Max VR Voltage')
    }
}

function Get-WcdMaximumSampleGapSeconds {
    param([Parameter(Mandatory = $true)] [datetime[]]$Timestamps)

    if ($Timestamps.Count -lt 2) {
        return $null
    }

    $gaps = New-Object System.Collections.Generic.List[double]
    for ($index = 1; $index -lt $Timestamps.Count; $index++) {
        $seconds = ($Timestamps[$index] - $Timestamps[$index - 1]).TotalSeconds
        if ($seconds -ge 0) {
            $gaps.Add($seconds)
        }
    }
    if ($gaps.Count -eq 0) {
        return $null
    }

    return ($gaps.ToArray() | Measure-Object -Maximum).Maximum
}

function Get-WcdSensorCounters {
    param(
        [Parameter(Mandatory = $true)] [object[]]$Rows,
        [Parameter(Mandatory = $true)]$Columns
    )

    $thermalPositive = 0
    $gpuRingLimitPositive = 0
    $driveFailurePositive = 0
    $driveWarningPositive = 0
    $combinedWorkloadBursts = 0
    $firstCombinedWorkloadBurst = $null

    foreach ($row in $Rows) {
        if (@($Columns.ThermalFlags | Where-Object { Test-WcdPositiveFlag $row.$_ }).Count -gt 0) {
            $thermalPositive++
        }
        if (@($Columns.GpuRingLimitFlags | Where-Object { Test-WcdPositiveFlag $row.$_ }).Count -gt 0) {
            $gpuRingLimitPositive++
        }
        if ($Columns.DriveFailure -and (Test-WcdPositiveFlag $row.($Columns.DriveFailure))) {
            $driveFailurePositive++
        }
        if ($Columns.DriveWarning -and (Test-WcdPositiveFlag $row.($Columns.DriveWarning))) {
            $driveWarningPositive++
        }

        if ($Columns.MemoryLoad -and $Columns.CpuUsage -and $Columns.DiskActivity) {
            $memory = ConvertTo-WcdInvariantNumber $row.($Columns.MemoryLoad)
            $cpu = ConvertTo-WcdInvariantNumber $row.($Columns.CpuUsage)
            $disk = ConvertTo-WcdInvariantNumber $row.($Columns.DiskActivity)
            if ($null -ne $memory -and $null -ne $cpu -and $null -ne $disk -and
                $memory -ge 90 -and $cpu -ge 95 -and $disk -ge 50) {
                $combinedWorkloadBursts++
                if ($null -eq $firstCombinedWorkloadBurst) {
                    $firstCombinedWorkloadBurst = ConvertTo-WcdSensorTimestamp $row
                }
            }
        }
    }

    return [pscustomobject][ordered]@{
        ThermalPositive             = $thermalPositive
        GpuRingLimitPositive        = $gpuRingLimitPositive
        DriveFailurePositive        = $driveFailurePositive
        DriveWarningPositive        = $driveWarningPositive
        CombinedWorkloadBursts      = $combinedWorkloadBursts
        FirstCombinedWorkloadBurst  = $firstCombinedWorkloadBurst
    }
}

function Get-WcdSensorSummary {
    param(
        [Parameter(Mandatory = $true)] [object[]]$Rows,
        [Parameter(Mandatory = $true)]$Columns,
        [Parameter(Mandatory = $true)]$Counters
    )

    $memory = @(Get-WcdNumericSeries $Rows $Columns.MemoryLoad)
    $memoryAvailable = @(Get-WcdNumericSeries $Rows $Columns.MemoryAvailable)
    $virtualMemory = @(Get-WcdNumericSeries $Rows $Columns.VirtualMemory)
    $pageFileTotal = @(Get-WcdNumericSeries $Rows $Columns.PageFileTotal)
    $pageFileUsed = @(Get-WcdNumericSeries $Rows $Columns.PageFileUsed)
    $cpu = @(Get-WcdNumericSeries $Rows $Columns.CpuUsage)
    $temperature = @(Get-WcdNumericSeries $Rows $Columns.CpuTemperature)
    $whea = @(Get-WcdNumericSeries $Rows $Columns.WheaErrors)
    $driveLife = @(Get-WcdNumericSeries $Rows $Columns.DriveLife)
    $disk = @(Get-WcdNumericSeries $Rows $Columns.DiskActivity)
    $timestamps = @(
        foreach ($row in $Rows) {
            $timestamp = ConvertTo-WcdSensorTimestamp $row
            if ($null -ne $timestamp) { $timestamp }
        }
    )
    $maximumGap = Get-WcdMaximumSampleGapSeconds -Timestamps $timestamps

    return [pscustomobject][ordered]@{
        SampleCount                    = $timestamps.Count
        Start                          = if ($timestamps.Count) { $timestamps[0].ToString('o') } else { $null }
        End                            = if ($timestamps.Count) { $timestamps[-1].ToString('o') } else { $null }
        DurationMinutes                = if ($timestamps.Count -gt 1) { [math]::Round(($timestamps[-1] - $timestamps[0]).TotalMinutes, 1) } else { $null }
        MaxSampleGapSeconds            = if ($null -ne $maximumGap) { [math]::Round($maximumGap, 3) } else { $null }
        PhysicalMemoryLoadMedianPct    = if ($memory.Count) { [math]::Round((Get-WcdPercentile $memory 50), 1) } else { $null }
        PhysicalMemoryLoadP95Pct       = if ($memory.Count) { [math]::Round((Get-WcdPercentile $memory 95), 1) } else { $null }
        PhysicalMemoryLoadMaxPct       = if ($memory.Count) { [math]::Round(($memory | Measure-Object -Maximum).Maximum, 1) } else { $null }
        PhysicalMemoryAvailableMinMB   = if ($memoryAvailable.Count) { [math]::Round(($memoryAvailable | Measure-Object -Minimum).Minimum, 0) } else { $null }
        VirtualMemoryLoadMaxPct        = if ($virtualMemory.Count) { [math]::Round(($virtualMemory | Measure-Object -Maximum).Maximum, 1) } else { $null }
        PageFileTotalMaxMB             = if ($pageFileTotal.Count) { [math]::Round(($pageFileTotal | Measure-Object -Maximum).Maximum, 0) } else { $null }
        PageFileUsedMaxMB              = if ($pageFileUsed.Count) { [math]::Round(($pageFileUsed | Measure-Object -Maximum).Maximum, 0) } else { $null }
        CpuUsageP95Pct                 = if ($cpu.Count) { [math]::Round((Get-WcdPercentile $cpu 95), 1) } else { $null }
        CpuUsageMaxPct                 = if ($cpu.Count) { [math]::Round(($cpu | Measure-Object -Maximum).Maximum, 1) } else { $null }
        CpuPackageTempMaxC             = if ($temperature.Count) { [math]::Round(($temperature | Measure-Object -Maximum).Maximum, 1) } else { $null }
        ThermalThrottleSampleCount     = $Counters.ThermalPositive
        WheaTotalErrorsMax             = if ($whea.Count) { [math]::Round(($whea | Measure-Object -Maximum).Maximum, 0) } else { $null }
        DriveRemainingLifeMinPct       = if ($driveLife.Count) { [math]::Round(($driveLife | Measure-Object -Minimum).Minimum, 1) } else { $null }
        DriveFailureSampleCount        = $Counters.DriveFailurePositive
        DriveWarningSampleCount        = $Counters.DriveWarningPositive
        DiskActivityMaxPct             = if ($disk.Count) { [math]::Round(($disk | Measure-Object -Maximum).Maximum, 1) } else { $null }
        GpuRingLimitSampleCount        = $Counters.GpuRingLimitPositive
        CombinedWorkloadBurstCount     = $Counters.CombinedWorkloadBursts
        FirstCombinedWorkloadBurst     = if ($null -ne $Counters.FirstCombinedWorkloadBurst) { $Counters.FirstCombinedWorkloadBurst.ToString('o') } else { $null }
    }
}

function Get-WcdSensorFindings {
    param(
        [Parameter(Mandatory = $true)]$Summary,
        [Parameter(Mandatory = $true)]$Columns
    )

    $findings = New-Object System.Collections.Generic.List[object]

    if ($null -ne $Summary.PhysicalMemoryLoadMaxPct -and
        (($Summary.PhysicalMemoryLoadMedianPct -ge 80) -or
         ($Summary.PhysicalMemoryAvailableMinMB -lt 512) -or
         ($Summary.PhysicalMemoryLoadMaxPct -ge 90))) {
        $severity = if (($Summary.PhysicalMemoryLoadP95Pct -ge 90) -or ($Summary.PhysicalMemoryAvailableMinMB -lt 256)) { 'High' } else { 'Medium' }
        $findings.Add((New-CrashDoctorFinding -Id 'sensor-sustained-memory-pressure' -Severity $severity -Confidence High `
            -Title 'Sensor capture shows sustained physical-memory pressure' `
            -Evidence "Median RAM load=$($Summary.PhysicalMemoryLoadMedianPct)%; P95=$($Summary.PhysicalMemoryLoadP95Pct)%; max=$($Summary.PhysicalMemoryLoadMaxPct)%; minimum available=$($Summary.PhysicalMemoryAvailableMinMB) MB." `
            -Interpretation 'This supports paging pressure and user-visible stalls. It does not by itself prove the mechanism of a hard reset or total machine lock.' `
            -NextStep 'Correlate future hangs with RAM/pagefile pressure and repeat representative workload with more physical RAM if practical.'))
    }

    if ($null -ne $Summary.CpuPackageTempMaxC -or @($Columns.ThermalFlags).Count -gt 0) {
        if ($Summary.ThermalThrottleSampleCount -gt 0 -or ($null -ne $Summary.CpuPackageTempMaxC -and $Summary.CpuPackageTempMaxC -ge 95)) {
            $findings.Add((New-CrashDoctorFinding -Id 'sensor-thermal-pressure-present' -Severity High -Confidence High `
                -Title 'Sensor capture contains thermal-limit evidence' `
                -Evidence "CPU package max=$($Summary.CpuPackageTempMaxC) C; throttle-positive samples=$($Summary.ThermalThrottleSampleCount)." `
                -Interpretation 'Thermal pressure is present in this interval.' `
                -NextStep 'Inspect cooling and exact throttle timestamps before unrelated changes.'))
        }
        elseif ($null -ne $Summary.CpuPackageTempMaxC) {
            $findings.Add((New-CrashDoctorFinding -Id 'sensor-no-thermal-throttle-evidence' -Severity Info -Confidence High `
                -Title 'No CPU thermal-throttling evidence appears in the sensor capture' `
                -Evidence "CPU package max=$($Summary.CpuPackageTempMaxC) C; throttle-positive samples=0." `
                -Interpretation 'This weakens overheating for this captured interval only.' `
                -NextStep 'Keep thermal failure lower unless a future incident capture shows a temperature/throttle excursion.'))
        }
    }

    if ($null -ne $Summary.WheaTotalErrorsMax) {
        if ($Summary.WheaTotalErrorsMax -gt 0) {
            $findings.Add((New-CrashDoctorFinding -Id 'sensor-whea-errors-present' -Severity High -Confidence High `
                -Title 'HWiNFO reports WHEA hardware errors' `
                -Evidence "Maximum WHEA Total Errors=$($Summary.WheaTotalErrorsMax)." `
                -Interpretation 'This raises CPU, memory, PCIe and motherboard priority.' `
                -NextStep 'Inspect matching WHEA-Logger events.'))
        }
        else {
            $findings.Add((New-CrashDoctorFinding -Id 'sensor-whea-counter-clean' -Severity Info -Confidence High `
                -Title 'HWiNFO WHEA counter remained at zero' `
                -Evidence 'WHEA Total Errors stayed at 0 for all numeric sensor samples.' `
                -Interpretation 'This is bounded negative evidence for the capture, not a hardware guarantee.' `
                -NextStep 'Preserve longer captures if the machine fails again.'))
        }
    }

    if ($Columns.DriveFailure -or $Columns.DriveWarning -or $null -ne $Summary.DriveRemainingLifeMinPct) {
        if ($Summary.DriveFailureSampleCount -gt 0 -or $Summary.DriveWarningSampleCount -gt 0) {
            $findings.Add((New-CrashDoctorFinding -Id 'sensor-drive-health-warning' -Severity High -Confidence High `
                -Title 'Drive health warning appears in the sensor capture' `
                -Evidence "Drive Failure samples=$($Summary.DriveFailureSampleCount); Drive Warning samples=$($Summary.DriveWarningSampleCount); minimum remaining life=$($Summary.DriveRemainingLifeMinPct)%." `
                -Interpretation 'Storage should move up the suspect order.' `
                -NextStep 'Run vendor/UEFI storage diagnostics and preserve SMART data.'))
        }
        else {
            $findings.Add((New-CrashDoctorFinding -Id 'sensor-drive-health-reassuring' -Severity Info -Confidence Medium `
                -Title 'Sensor drive-health flags are reassuring' `
                -Evidence "Drive Failure samples=0; Drive Warning samples=0; minimum remaining life=$($Summary.DriveRemainingLifeMinPct)%." `
                -Interpretation 'This weakens a straightforward failing-drive theory but cannot rule out intermittent faults.' `
                -NextStep 'Keep storage lower unless new timeouts, SMART changes or diagnostic failures appear.'))
        }
    }

    if ($null -ne $Summary.MaxSampleGapSeconds) {
        if ($Summary.MaxSampleGapSeconds -le 5) {
            $findings.Add((New-CrashDoctorFinding -Id 'sensor-capture-continuous' -Severity Info -Confidence High `
                -Title 'Sensor sampling remained continuous' `
                -Evidence "Maximum sample gap=$($Summary.MaxSampleGapSeconds) seconds across $($Summary.SampleCount) samples." `
                -Interpretation 'No long logger pause is visible; a hidden freeze during this exact capture is unlikely.' `
                -NextStep 'Use the same logging method across the next incident window.'))
        }
        elseif ($Summary.MaxSampleGapSeconds -gt 10) {
            $findings.Add((New-CrashDoctorFinding -Id 'sensor-capture-gap' -Severity Medium -Confidence Medium `
                -Title 'Sensor capture contains a significant sampling gap' `
                -Evidence "Maximum sample gap=$($Summary.MaxSampleGapSeconds) seconds." `
                -Interpretation 'A gap can reflect a stall, sleep or logger interruption.' `
                -NextStep 'Correlate the gap with events and user-observed timing.'))
        }
    }

    if ($Summary.GpuRingLimitSampleCount -gt 0 -and $Summary.ThermalThrottleSampleCount -eq 0) {
        $findings.Add((New-CrashDoctorFinding -Id 'sensor-transient-gpu-ring-limits' -Severity Low -Confidence Medium `
            -Title 'Transient GPU/ring limit reasons occurred without thermal throttling' `
            -Evidence "GT/ring limit-positive samples=$($Summary.GpuRingLimitSampleCount); thermal-positive samples=0." `
            -Interpretation 'These can occur during normal power management and are a lead, not a GPU-failure diagnosis.' `
            -NextStep 'Elevate only if future failures align with the same flags or graphics errors.'))
    }

    if ($Summary.CombinedWorkloadBurstCount -gt 0) {
        $findings.Add((New-CrashDoctorFinding -Id 'sensor-combined-workload-burst' -Severity Low -Confidence High `
            -Title 'A combined CPU, memory and disk workload burst was captured' `
            -Evidence "CPU>=95%, RAM>=90%, disk>=50% samples=$($Summary.CombinedWorkloadBurstCount); first=$($Summary.FirstCombinedWorkloadBurst)." `
            -Interpretation 'This is a real stress point; continuous sampling means it was not a captured hard freeze.' `
            -NextStep 'Add process-level capture around future bursts.'))
    }

    return $findings.ToArray()
}

function Get-WcdSensorTelemetry {
    param([Parameter(Mandatory = $true)] [string]$EvidencePath)

    $files = @(Get-WcdLatestEvidenceFile -EvidencePath $EvidencePath -NamePattern '(?i)^(sensors?|hwinfo).*\.csv$')
    if ($files.Count -eq 0) {
        return New-WcdUnavailableTelemetrySource -SourceFile $null
    }

    $file = $files[0]
    $rows = @(Import-WcdSensorCsv -File $file)
    if ($rows.Count -eq 0) {
        throw "Sensor CSV '$($file.Name)' contains no data rows."
    }

    $columns = Get-WcdSensorColumnMap -Rows $rows
    $counters = Get-WcdSensorCounters -Rows $rows -Columns $columns
    $summary = Get-WcdSensorSummary -Rows $rows -Columns $columns -Counters $counters
    $findings = @(Get-WcdSensorFindings -Summary $summary -Columns $columns)

    return [pscustomobject][ordered]@{
        Available  = $true
        SourceFile = $file.Name
        Summary    = $summary
        Findings   = $findings
    }
}

function ConvertFrom-WcdPowerReportData {
    param([Parameter(Mandatory = $true)] [System.IO.FileInfo]$File)

    Assert-WcdFileWithinLimit -File $File -MaximumBytes $script:MaxPowerReportBytes -Description 'System power report'
    $html = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
    $match = [regex]::Match($html, '(?s)var\s+LocalSprData\s*=\s*(\{.*?\});\s*(?:var\s+|</script>)')
    if (-not $match.Success) {
        throw "System power report '$($File.Name)' does not contain LocalSprData."
    }

    # Windows emits a JavaScript object where a small number of values may use single quotes; normalize only those value tokens before JSON parsing.
    $json = [regex]::Replace($match.Groups[1].Value, ":\s*'([^']*)'", ': "$1"')
    try {
        $data = $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "System power report '$($File.Name)' contains invalid LocalSprData: $($_.Exception.Message)"
    }

    if ($null -eq $data.PSObject.Properties['ReportInformation'] -or
        $null -eq $data.PSObject.Properties['ScenarioInstances']) {
        throw "System power report '$($File.Name)' is missing required LocalSprData fields."
    }

    return $data
}

function ConvertTo-WcdRequiredUtcTimestamp {
    param(
        [Parameter(Mandatory = $true)] [string]$Value,
        [Parameter(Mandatory = $true)] [string]$FieldName
    )

    $timestamp = [datetime]::MinValue
    if (-not [datetime]::TryParse(
        $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$timestamp
    )) {
        throw "Power report field '$FieldName' has invalid timestamp '$Value'."
    }

    return $timestamp.ToUniversalTime()
}

function Get-WcdPowerSummary {
    param([Parameter(Mandatory = $true)]$Data)

    $reportInfo = $Data.ReportInformation
    $reportStart = ConvertTo-WcdRequiredUtcTimestamp -Value ([string]$reportInfo.ReportStartTime) -FieldName 'ReportStartTime'
    $scanTime = ConvertTo-WcdRequiredUtcTimestamp -Value ([string]$reportInfo.ScanTime) -FieldName 'ScanTime'
    if ($reportStart -gt $scanTime) {
        throw 'Power report starts after its scan time.'
    }

    $abnormalShutdowns = New-Object System.Collections.Generic.List[object]
    $bugchecks = New-Object System.Collections.Generic.List[object]
    $outOfWindowCount = 0

    foreach ($instance in @($Data.ScenarioInstances)) {
        $type = 0
        if (-not [int]::TryParse([string]$instance.Type, [ref]$type)) {
            continue
        }
        if ($type -notin @(9, 10)) {
            continue
        }

        $timestamp = ConvertTo-WcdRequiredUtcTimestamp -Value ([string]$instance.EntryTimestamp) -FieldName 'ScenarioInstances.EntryTimestamp'
        if ($timestamp -lt $reportStart -or $timestamp -gt $scanTime) {
            $outOfWindowCount++
            continue
        }

        if ($type -eq 9) {
            $abnormalShutdowns.Add($instance)
        }
        else {
            $bugchecks.Add($instance)
        }
    }

    $summary = [pscustomobject][ordered]@{
        ReportStartUtc                   = $reportStart.ToString('o')
        ScanTimeUtc                      = $scanTime.ToString('o')
        UtcOffsetMinutes                 = [int]$reportInfo.UtcOffset
        InWindowAbnormalShutdownCount    = $abnormalShutdowns.Count
        InWindowBugcheckCount            = $bugchecks.Count
        OutOfWindowFailureRecordCount    = $outOfWindowCount
        LatestAbnormalShutdownLocal      = $null
        LatestAbnormalShutdownOnAc       = $null
        LatestBugcheckLocal              = $null
        LatestBugcheckCode               = $null
    }

    if ($abnormalShutdowns.Count -gt 0) {
        $latest = @($abnormalShutdowns.ToArray() | Sort-Object EntryTimestamp | Select-Object -Last 1)[0]
        $summary.LatestAbnormalShutdownLocal = [string]$latest.EntryTimestampLocal
        $summary.LatestAbnormalShutdownOnAc = [bool]$latest.OnAc
    }

    if ($bugchecks.Count -gt 0) {
        $latest = @($bugchecks.ToArray() | Sort-Object EntryTimestamp | Select-Object -Last 1)[0]
        $summary.LatestBugcheckLocal = [string]$latest.EntryTimestampLocal
        if ($null -ne $latest.PSObject.Properties['Metadata']) {
            foreach ($value in @($latest.Metadata.Values)) {
                if ([string]$value.Key -eq 'EventLog.BugcheckCode') {
                    $summary.LatestBugcheckCode = [string]$value.Value
                    break
                }
            }
        }
    }

    return $summary
}

function Get-WcdPowerFindings {
    param([Parameter(Mandatory = $true)]$Summary)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($Summary.InWindowAbnormalShutdownCount -gt 0) {
        $powerSource = if ($Summary.LatestAbnormalShutdownOnAc) { 'AC' } else { 'battery' }
        $findings.Add((New-CrashDoctorFinding -Id 'power-report-abnormal-shutdown' -Severity Medium -Confidence High `
            -Title 'System power report confirms an abnormal shutdown in the report window' `
            -Evidence "In-window abnormal shutdowns=$($Summary.InWindowAbnormalShutdownCount); latest=$($Summary.LatestAbnormalShutdownLocal); power source=$powerSource." `
            -Interpretation 'This precisely confirms an unclean incident boundary; it records the outcome rather than proving cause.' `
            -NextStep 'Correlate with final pre-incident System events and any sensor/ETW capture.'))
    }

    if ($Summary.InWindowBugcheckCount -gt 0) {
        $findings.Add((New-CrashDoctorFinding -Id 'power-report-bugcheck' -Severity High -Confidence High `
            -Title 'System power report contains an in-window bugcheck' `
            -Evidence "In-window bugchecks=$($Summary.InWindowBugcheckCount); latest=$($Summary.LatestBugcheckLocal); code=$($Summary.LatestBugcheckCode)." `
            -Interpretation 'A true bugcheck provides a stronger diagnostic path than a generic reset.' `
            -NextStep 'Preserve and analyse the matching dump.'))
    }

    if ($Summary.OutOfWindowFailureRecordCount -gt 0) {
        $findings.Add((New-CrashDoctorFinding -Id 'power-report-stale-failure-records' -Severity Info -Confidence High `
            -Title 'Power report contains failure records outside its declared report window' `
            -Evidence "Failure records outside $($Summary.ReportStartUtc) to $($Summary.ScanTimeUtc): $($Summary.OutOfWindowFailureRecordCount)." `
            -Interpretation 'Historical, cloned-image or clock-corrupted records can contaminate naive crash counts; Crash Doctor excludes them.' `
            -NextStep 'Use the report window and current-machine timestamps as hard boundaries.'))
    }

    return $findings.ToArray()
}

function Get-WcdPowerTelemetry {
    param([Parameter(Mandatory = $true)] [string]$EvidencePath)

    $files = @(Get-WcdLatestEvidenceFile -EvidencePath $EvidencePath -NamePattern '(?i)^(systempower|sleepstudy)-report.*\.html$')
    if ($files.Count -eq 0) {
        return New-WcdUnavailableTelemetrySource -SourceFile $null
    }

    $file = $files[0]
    $data = ConvertFrom-WcdPowerReportData -File $file
    $summary = Get-WcdPowerSummary -Data $data
    return [pscustomobject][ordered]@{
        Available  = $true
        SourceFile = $file.Name
        Summary    = $summary
        Findings   = @(Get-WcdPowerFindings -Summary $summary)
    }
}

function Invoke-CrashDoctorTelemetryAnalysis {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string]$EvidencePath)

    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Container)) {
        throw "Evidence path does not exist or is not a directory: $EvidencePath"
    }

    $errors = New-Object System.Collections.Generic.List[object]
    try {
        $sensor = Get-WcdSensorTelemetry -EvidencePath $EvidencePath
    }
    catch {
        $sensorFile = @(Get-WcdLatestEvidenceFile -EvidencePath $EvidencePath -NamePattern '(?i)^(sensors?|hwinfo).*\.csv$' | Select-Object -First 1)
        $sensor = New-WcdUnavailableTelemetrySource -SourceFile $(if ($sensorFile.Count) { $sensorFile[0].Name } else { $null })
        $errors.Add([pscustomobject][ordered]@{ Source = 'sensor'; Message = $_.Exception.Message })
    }

    try {
        $power = Get-WcdPowerTelemetry -EvidencePath $EvidencePath
    }
    catch {
        $powerFile = @(Get-WcdLatestEvidenceFile -EvidencePath $EvidencePath -NamePattern '(?i)^(systempower|sleepstudy)-report.*\.html$' | Select-Object -First 1)
        $power = New-WcdUnavailableTelemetrySource -SourceFile $(if ($powerFile.Count) { $powerFile[0].Name } else { $null })
        $errors.Add([pscustomobject][ordered]@{ Source = 'power'; Message = $_.Exception.Message })
    }

    $findings = @($sensor.Findings) + @($power.Findings)
    return [pscustomobject][ordered]@{
        Available = ($sensor.Available -or $power.Available)
        Sensor    = $sensor
        Power     = $power
        Findings  = @(Sort-CrashDoctorFindings -Findings $findings)
        Errors    = $errors.ToArray()
    }
}

function Add-CrashDoctorTelemetryToReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Report,
        [Parameter(Mandatory = $true)]$Telemetry
    )

    $copy = [ordered]@{}
    foreach ($property in $Report.PSObject.Properties) {
        if ($property.Name -notin @('Findings', 'Telemetry')) {
            $copy[$property.Name] = $property.Value
        }
    }

    $copy['Findings'] = @(Sort-CrashDoctorFindings -Findings (@($Report.Findings) + @($Telemetry.Findings)))
    $copy['Telemetry'] = [pscustomobject][ordered]@{
        Sensor = $Telemetry.Sensor
        Power  = $Telemetry.Power
        Errors = @($Telemetry.Errors)
    }

    return [pscustomobject]$copy
}

Export-ModuleMember -Function Invoke-CrashDoctorTelemetryAnalysis, Add-CrashDoctorTelemetryToReport
