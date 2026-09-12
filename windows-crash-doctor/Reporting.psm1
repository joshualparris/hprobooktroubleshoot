Set-StrictMode -Version Latest

function ConvertTo-WcdMarkdownCell {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function ConvertTo-CrashDoctorMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Windows Crash Doctor report')
    $lines.Add('')
    $lines.Add("Generated: **$($Report.GeneratedAt)**")
    $lines.Add('')
    $lines.Add("Evidence directory: ``$($Report.EvidencePath)``")
    $lines.Add('')
    $lines.Add('> This report ranks evidence signals. It does not claim that a detected abnormality is the root cause unless independent evidence proves that link.')
    $lines.Add('')
    $lines.Add('## Coverage')
    $lines.Add('')
    $lines.Add("- Files present: **$($Report.Coverage.PresentCount) / $($Report.Coverage.ExpectedCount)** ($($Report.Coverage.Percent)%)")
    if (@($Report.Coverage.MissingFiles).Count -gt 0) {
        $lines.Add("- Missing/empty inputs: $(@($Report.Coverage.MissingFiles) -join ', ')")
    }
    else {
        $lines.Add('- All expected text inputs are present.')
    }

    $lines.Add('')
    $lines.Add('## Inventory')
    $lines.Add('')
    $lines.Add('| Field | Value |')
    $lines.Add('|---|---|')
    $lines.Add("| Model | $(ConvertTo-WcdMarkdownCell $Report.Inventory.Model) |")
    $lines.Add("| BIOS | $(ConvertTo-WcdMarkdownCell $Report.Inventory.BIOS) |")
    $lines.Add("| Physical memory (GiB) | $($Report.Inventory.PhysicalMemoryGiB) |")

    $lines.Add('')
    $lines.Add('## Event summary')
    $lines.Add('')
    $lines.Add('| Signal | Count |')
    $lines.Add('|---|---:|')
    $lines.Add("| WHEA references | $($Report.EventSummary.WHEAReferences) |")
    $lines.Add("| Kernel-Power 41 records | $($Report.EventSummary.KernelPower41Records) |")
    $lines.Add("| volmgr 161 records | $($Report.EventSummary.Volmgr161Records) |")

    $lines.Add('')
    $lines.Add('## Findings')
    $lines.Add('')
    $findings = @($Report.Findings)
    if ($findings.Count -eq 0) {
        $lines.Add('No rule fired from the supplied text evidence. This does **not** mean the machine is healthy; it may mean the evidence set is incomplete.')
    }
    else {
        $lines.Add('| Severity | Confidence | ID | Finding |')
        $lines.Add('|---|---|---|---|')
        foreach ($finding in $findings) {
            $lines.Add("| $($finding.Severity) | $($finding.Confidence) | ``$($finding.Id)`` | $(ConvertTo-WcdMarkdownCell $finding.Title) |")
        }

        foreach ($finding in $findings) {
            $lines.Add('')
            $lines.Add("### $($finding.Title)")
            $lines.Add('')
            $lines.Add("- **Severity:** $($finding.Severity)")
            $lines.Add("- **Confidence:** $($finding.Confidence)")
            $lines.Add("- **Evidence:** $($finding.Evidence)")
            $lines.Add("- **Interpretation:** $($finding.Interpretation)")
            $lines.Add("- **Next step:** $($finding.NextStep)")
        }
    }

    $lines.Add('')
    $lines.Add('## Interpretation rules')
    $lines.Add('')
    $lines.Add('- Event 41 is aftermath evidence, not a root-cause label.')
    $lines.Add('- Missing WHEA/BSOD evidence does not clear intermittent hardware.')
    $lines.Add('- A stale/reused Windows image is a diagnostic confounder, not automatically the cause.')
    $lines.Add('- Firmware Code 10 is real evidence of an abnormal firmware-device state, but the mechanism of a hard hang must still be demonstrated.')
    $lines.Add('- Make one major change at a time and preserve the before/after snapshot.')

    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-CrashDoctorDumpMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Windows Crash Doctor dump report')
    $lines.Add('')
    $lines.Add("Dump: ``$($Report.Path)``")
    $lines.Add('')
    $lines.Add("- **Format:** $($Report.Format)")
    $lines.Add("- **Architecture:** $($Report.Architecture)")
    $lines.Add("- **File size:** $($Report.FileSize) bytes")
    $lines.Add("- **Parser coverage:** $($Report.ParseCoverage)")

    if ($Report.Format -eq 'MiniDump') {
        $lines.Add('')
        $lines.Add('## Minidump summary')
        $lines.Add('')
        $lines.Add("- Streams: $($Report.Header.NumberOfStreams)")
        $lines.Add("- Threads: $($Report.ThreadCount)")
        $lines.Add("- Modules: $($Report.ModuleCount)")
        if ($Report.SystemInfo) {
            $lines.Add("- Windows: $($Report.SystemInfo.MajorVersion).$($Report.SystemInfo.MinorVersion) build $($Report.SystemInfo.BuildNumber)")
            $lines.Add("- Processors: $($Report.SystemInfo.NumberOfProcessors)")
        }
        if ($Report.Exception) {
            $lines.Add("- Exception thread: $($Report.Exception.ThreadId)")
            $lines.Add(('- Exception code: `0x{0:X8}`' -f $Report.Exception.ExceptionCode))
            $lines.Add(('- Exception address: `0x{0:X16}`' -f $Report.Exception.ExceptionAddress))
        }

        if (@($Report.Modules).Count -gt 0) {
            $lines.Add('')
            $lines.Add('## Modules')
            $lines.Add('')
            $lines.Add('| Module | Base | Size |')
            $lines.Add('|---|---:|---:|')
            foreach ($module in @($Report.Modules)) {
                $name = if ($module.Name) { ConvertTo-WcdMarkdownCell $module.Name } else { '(name unavailable)' }
                $lines.Add(('| {0} | `0x{1:X16}` | {2} |' -f $name, $module.BaseOfImage, $module.SizeOfImage))
            }
        }

        $lines.Add('')
        $lines.Add('## Streams')
        $lines.Add('')
        $lines.Add('| Type | Name | Bytes | RVA |')
        $lines.Add('|---:|---|---:|---:|')
        foreach ($stream in @($Report.Streams)) {
            $lines.Add("| $($stream.StreamType) | $(ConvertTo-WcdMarkdownCell $stream.Name) | $($stream.DataSize) | $($stream.Rva) |")
        }
    }
    elseif ($Report.Format -eq 'KernelCrashDump') {
        $lines.Add('')
        $lines.Add('## Kernel crash header')
        $lines.Add('')
        $lines.Add("- Valid marker: $($Report.Header.ValidDump)")
        $lines.Add("- Windows version fields: $($Report.Header.MajorVersion).$($Report.Header.MinorVersion)")
        $lines.Add("- Processors: $($Report.Header.NumberProcessors)")
        $lines.Add(('- Bugcheck: `0x{0:X8}`' -f $Report.Header.BugCheckCode))
        $lines.Add(('- Parameters: `0x{0:X}` `0x{1:X}` `0x{2:X}` `0x{3:X}`' -f $Report.Header.BugCheckParameter1, $Report.Header.BugCheckParameter2, $Report.Header.BugCheckParameter3, $Report.Header.BugCheckParameter4))
        if ($null -ne $Report.Header.PSObject.Properties['DumpTypeName']) {
            $lines.Add("- Dump type: $($Report.Header.DumpTypeName) ($($Report.Header.DumpType))")
        }
    }

    $lines.Add('')
    $lines.Add('> Parsing a dump identifies evidence contained in the file; it does not by itself establish root cause. Symbolization, stack unwinding and memory traversal are separate roadmap capabilities.')
    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-CrashDoctorTelemetryMarkdownSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Telemetry
    )

    if (-not $Telemetry.Available) {
        return ''
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('## Telemetry summary')
    $lines.Add('')

    if ($Telemetry.Sensor.Available) {
        $summary = $Telemetry.Sensor.Summary
        $lines.Add("Sensor source: ``$($Telemetry.Sensor.SourceFile)``")
        $lines.Add('')
        $lines.Add('| Metric | Value |')
        $lines.Add('|---|---:|')
        $lines.Add("| Samples | $($summary.SampleCount) |")
        $lines.Add("| Duration (min) | $($summary.DurationMinutes) |")
        $lines.Add("| Maximum sample gap (s) | $($summary.MaxSampleGapSeconds) |")
        $lines.Add("| RAM load median / P95 / max | $($summary.PhysicalMemoryLoadMedianPct)% / $($summary.PhysicalMemoryLoadP95Pct)% / $($summary.PhysicalMemoryLoadMaxPct)% |")
        $lines.Add("| Minimum physical RAM available | $($summary.PhysicalMemoryAvailableMinMB) MB |")
        $lines.Add("| CPU usage P95 / max | $($summary.CpuUsageP95Pct)% / $($summary.CpuUsageMaxPct)% |")
        $lines.Add("| CPU package max | $($summary.CpuPackageTempMaxC) C |")
        $lines.Add("| Thermal-throttle-positive samples | $($summary.ThermalThrottleSampleCount) |")
        $lines.Add("| WHEA total errors max | $($summary.WheaTotalErrorsMax) |")
        $lines.Add("| Drive remaining life min | $($summary.DriveRemainingLifeMinPct)% |")
        $lines.Add('')
    }

    if ($Telemetry.Power.Available) {
        $summary = $Telemetry.Power.Summary
        $lines.Add("Power-report source: ``$($Telemetry.Power.SourceFile)``")
        $lines.Add('')
        $lines.Add("- In-window abnormal shutdowns: **$($summary.InWindowAbnormalShutdownCount)**")
        $lines.Add("- In-window bugchecks: **$($summary.InWindowBugcheckCount)**")
        $lines.Add("- Out-of-window failure records ignored: **$($summary.OutOfWindowFailureRecordCount)**")
        if ($summary.LatestAbnormalShutdownLocal) {
            $lines.Add("- Latest abnormal shutdown: **$($summary.LatestAbnormalShutdownLocal)**")
        }
        $lines.Add('')
    }

    if (@($Telemetry.Errors).Count -gt 0) {
        $lines.Add('### Telemetry source errors')
        $lines.Add('')
        foreach ($errorRecord in @($Telemetry.Errors)) {
            $lines.Add("- **$($errorRecord.Source):** $($errorRecord.Message)")
        }
        $lines.Add('')
    }

    return ($lines -join [Environment]::NewLine)
}

Export-ModuleMember -Function @(
    'ConvertTo-CrashDoctorMarkdown',
    'ConvertTo-CrashDoctorDumpMarkdown',
    'ConvertTo-CrashDoctorTelemetryMarkdownSection'
)
