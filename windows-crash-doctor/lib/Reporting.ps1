function Get-WcdRecommendations {
    param(
        [Parameter(Mandatory=$true)]$Evidence,
        [Parameter(Mandatory=$true)]$Hypotheses
    )
    $steps = New-Object System.Collections.Generic.List[object]
    function Add-Step([string]$Title,[string]$Reason,[string]$Risk,[string]$Verification,[string]$Command) {
        $steps.Add([pscustomobject]@{
            Order = $steps.Count + 1
            Title = $Title
            Reason = $Reason
            Risk = $Risk
            Verification = $Verification
            Command = $Command
        })
    }

    if ($Evidence.CrashCapture.Status -ne 'LikelyReady') {
        Add-Step 'Make crash capture trustworthy' 'Missing dumps are not interpretable until pagefile and dump settings are adequate.' 'Low to medium; configuration change and reboot may be required.' 'After reboot, re-run doctor and confirm CrashCapture.Status is LikelyReady.' $null
    }

    $power = @($Hypotheses | Where-Object { $_.Id -eq 'power-state' } | Select-Object -First 1)
    if ($power.Count -and $power[0].Score -ge 45) {
        Add-Step 'Run the Fast Startup / resume A-B test' 'Power-state timing is sufficiently suspicious to justify a controlled isolation test.' 'Low; hibernation/Fast Startup becomes unavailable while disabled.' 'Record cold boots, shutdown/start cycles and stable hours before changing another variable.' 'powercfg /h off'
    }

    $driver = @($Hypotheses | Where-Object { $_.Id -eq 'low-level-driver' } | Select-Object -First 1)
    if ($driver.Count -and $driver[0].Score -ge 45) {
        Add-Step 'Review low-level tuning and OEM drivers' 'Low-level drivers can participate in power/ACPI/firmware paths.' 'Medium if removed; inspect before changing.' 'Remove or update one component, then repeat the same workload and power-state test.' $null
    }

    $firmware = @($Hypotheses | Where-Object { $_.Id -eq 'firmware' } | Select-Object -First 1)
    if ($firmware.Count -and $firmware[0].Score -ge 45) {
        Add-Step 'Compare and update BIOS through the official OEM path' 'Old firmware or a firmware-class device error can be a plausible platform-level contributor.' 'Medium; firmware updates require AC power and recovery-key safety.' 'After update, capture BIOS version/date and repeat the controlled stability tests.' $null
    }

    $hardware = @($Hypotheses | Where-Object { $_.Id -eq 'hardware-memory' } | Select-Object -First 1)
    if ($hardware.Count -and $hardware[0].Score -ge 35) {
        Add-Step 'Run extended memory diagnostics' 'Hard locks can be caused by memory/platform faults even without a BSOD.' 'Low; test is time-consuming.' 'Save the test result and exact pass/error count into the incident evidence.' $null
    }

    $image = @($Hypotheses | Where-Object { $_.Id -eq 'reused-image' } | Select-Object -First 1)
    if ($image.Count -and $image[0].Score -ge 45) {
        Add-Step 'Isolate the delivered Windows image' 'A reused/respecialised image adds driver and configuration uncertainty.' 'Medium; clean-OS testing needs backup and planning.' 'If a clean Windows/live environment is stable under the same conditions, image contamination becomes much stronger.' $null
    }

    Add-Step 'Change one major variable at a time' 'This preserves causal information and makes successful fixes reproducible.' 'None.' 'Log every intervention as an experiment and do not stack unrelated fixes.' $null
    return @($steps)
}

function ConvertTo-WcdMarkdown {
    param(
        [Parameter(Mandatory=$true)]$Evidence,
        [Parameter(Mandatory=$true)]$Hypotheses,
        [Parameter(Mandatory=$true)]$Recommendations
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Windows Crash Doctor report')
    $lines.Add('')
    $lines.Add("Generated: $($Evidence.CollectedUtc)")
    $lines.Add("Version: $script:WcdVersion")
    $lines.Add('')
    $lines.Add('## Machine')
    $lines.Add('')
    $lines.Add("* Model: $($Evidence.Machine.Manufacturer) $($Evidence.Machine.Model)")
    $lines.Add("* Board: $($Evidence.Machine.BoardProduct)")
    $lines.Add("* BIOS: $($Evidence.Machine.BiosVersion) ($($Evidence.Machine.BiosReleaseDateUtc))")
    $lines.Add("* OS: $($Evidence.Machine.OsCaption) $($Evidence.Machine.OsBuild)")
    $lines.Add('')
    $lines.Add('## Diagnostic quality')
    $lines.Add('')
    $lines.Add("* Crash capture: **$($Evidence.CrashCapture.Status)**")
    $lines.Add("* Pagefile: $($Evidence.CrashCapture.PagefileAllocatedMB) MB; automatic management: $($Evidence.CrashCapture.AutomaticManagedPagefile)")
    foreach ($reason in @($Evidence.CrashCapture.Reasons)) { $lines.Add("  * $reason") }
    $lines.Add('')
    $lines.Add('## Ranked hypotheses')
    $lines.Add('')
    foreach ($h in $Hypotheses) {
        $lines.Add("### $($h.Title) — $($h.Confidence) ($($h.Score)/100)")
        if (@($h.SupportingEvidence).Count) {
            $lines.Add('Supporting:')
            foreach ($x in @($h.SupportingEvidence)) { $lines.Add("* $x") }
        }
        if (@($h.ContradictingEvidence).Count) {
            $lines.Add('Against:')
            foreach ($x in @($h.ContradictingEvidence)) { $lines.Add("* $x") }
        }
        if (@($h.Unknowns).Count) {
            $lines.Add('Unknowns:')
            foreach ($x in @($h.Unknowns)) { $lines.Add("* $x") }
        }
        $lines.Add("Next test: $($h.NextDiscriminatingTest)")
        $lines.Add('')
    }
    $lines.Add('## Recommended sequence')
    $lines.Add('')
    foreach ($step in $Recommendations) {
        $lines.Add("$($step.Order). **$($step.Title)**")
        $lines.Add("   * Why: $($step.Reason)")
        $lines.Add("   * Risk: $($step.Risk)")
        $lines.Add("   * Verify: $($step.Verification)")
        if ($step.Command) { $lines.Add("   * Candidate command: ``$($step.Command)``") }
    }
    $lines.Add('')
    $lines.Add('## Interpretation rule')
    $lines.Add('')
    $lines.Add('Scores are triage weights, not probabilities. Correlation is not proof of causation. A hard freeze can prevent the final event from being written, so the rolling canary and controlled experiments are primary evidence.')
    return ($lines -join [Environment]::NewLine)
}

function Invoke-WcdDoctor {
    param(
        [int]$EventHours = 72,
        [switch]$PassThru
    )
    $paths = Initialize-WcdDataRoot
    $evidence = Get-WcdEvidence -EventHours $EventHours
    $hypotheses = @(Get-WcdHypotheses -Evidence $evidence)
    $recommendations = @(Get-WcdRecommendations -Evidence $evidence -Hypotheses $hypotheses)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $paths.Reports "doctor-$stamp.json"
    $mdPath = Join-Path $paths.Reports "doctor-$stamp.md"

    $report = [pscustomobject]@{
        SchemaVersion = 1
        AppVersion = $script:WcdVersion
        Evidence = $evidence
        Hypotheses = $hypotheses
        Recommendations = $recommendations
    }
    Write-WcdJson -InputObject $report -Path $jsonPath -Depth 12
    ConvertTo-WcdMarkdown -Evidence $evidence -Hypotheses $hypotheses -Recommendations $recommendations |
        Set-Content -LiteralPath $mdPath -Encoding UTF8
    Write-WcdLedgerEntry -Type 'doctor-report' -Data @{ Json=$jsonPath; Markdown=$mdPath }

    $result = [pscustomobject]@{
        JsonReport = $jsonPath
        MarkdownReport = $mdPath
        Hypotheses = $hypotheses
        Recommendations = $recommendations
        Evidence = $evidence
    }
    if ($PassThru) { return $result }
    Write-Host "Windows Crash Doctor report:" -ForegroundColor Cyan
    Write-Host "  $mdPath"
    $hypotheses | Select-Object -First 5 Title,Score,Confidence | Format-Table -AutoSize
}

