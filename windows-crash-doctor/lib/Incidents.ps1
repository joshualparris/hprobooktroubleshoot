function New-WcdIncidentBundle {
    param(
        [Parameter(Mandatory=$true)][DateTime]$IncidentEndUtc,
        [string]$Reason = 'unexpected-shutdown',
        $PreviousState = $null
    )
    $paths = Initialize-WcdDataRoot
    $config = Get-WcdConfig
    $startUtc = $IncidentEndUtc.AddMinutes(-[int]$config.IncidentPreWindowMinutes)
    $postUtc = [DateTime]::UtcNow
    $canary = @(Get-WcdRecentCanary -Minutes ([int]$config.IncidentPreWindowMinutes) -EndUtc $IncidentEndUtc)
    $events = @(Get-WcdEventTimeline -StartTime $startUtc.ToLocalTime() -EndTime $postUtc.ToLocalTime())
    $evidence = Get-WcdEvidence -EventHours 24
    $hypotheses = @(Get-WcdHypotheses -Evidence $evidence)
    $recommendations = @(Get-WcdRecommendations -Evidence $evidence -Hypotheses $hypotheses)

    $incidentId = "incident-{0}" -f (Get-Date -Date ($IncidentEndUtc.ToLocalTime()) -Format 'yyyyMMdd-HHmmss')
    $incidentDir = Join-Path $paths.Incidents $incidentId
    New-Item -ItemType Directory -Path $incidentDir -Force | Out-Null

    $bundle = [pscustomobject]@{
        SchemaVersion = 1
        AppVersion = $script:WcdVersion
        IncidentId = $incidentId
        Reason = $Reason
        IncidentEndUtc = $IncidentEndUtc.ToString('o')
        PreviousState = $PreviousState
        Canary = $canary
        Events = $events
        Evidence = $evidence
        Hypotheses = $hypotheses
        Recommendations = $recommendations
    }
    Write-WcdJson -InputObject $bundle -Path (Join-Path $incidentDir 'incident.json') -Depth 14
    ConvertTo-WcdMarkdown -Evidence $evidence -Hypotheses $hypotheses -Recommendations $recommendations |
        Set-Content -LiteralPath (Join-Path $incidentDir 'report.md') -Encoding UTF8

    Write-WcdLedgerEntry -Type 'incident-created' -Data @{ IncidentId=$incidentId; Reason=$Reason; Path=$incidentDir }
    return $incidentDir
}

function Invoke-WcdDetectPreviousIncident {
    param($PreviousState)
    if (-not $PreviousState) { return $null }
    if (-not $PreviousState.BootTimeUtc -or -not $PreviousState.LastHeartbeatUtc) { return $null }

    $currentBoot = Get-WcdBootTimeUtc
    $previousBoot = [DateTime]::Parse($PreviousState.BootTimeUtc).ToUniversalTime()
    if ([Math]::Abs(($currentBoot - $previousBoot).TotalSeconds) -lt 30) { return $null }

    if ($PreviousState.LastIncidentForBootUtc -and $PreviousState.LastIncidentForBootUtc -eq $PreviousState.BootTimeUtc) {
        return $null
    }

    $queryStart = $currentBoot.AddMinutes(-2).ToLocalTime()
    $queryEnd = (Get-Date).AddMinutes(2)
    $abnormal = @()
    try {
        $abnormal = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=@(41,6008); StartTime=$queryStart; EndTime=$queryEnd} -ErrorAction Stop)
    } catch {}

    if ($abnormal.Count -gt 0) {
        $lastHeartbeat = [DateTime]::Parse($PreviousState.LastHeartbeatUtc).ToUniversalTime()
        return (New-WcdIncidentBundle -IncidentEndUtc $lastHeartbeat -Reason 'abnormal-reboot-after-missing-heartbeat' -PreviousState $PreviousState)
    }
    return $null
}

function Invoke-WcdCanaryLoop {
    [CmdletBinding()]
    param([switch]$Once)

    $paths = Initialize-WcdDataRoot
    $config = Get-WcdConfig
    $previousState = Get-WcdState
    Invoke-WcdDetectPreviousIncident -PreviousState $previousState | Out-Null

    $bootUtc = Get-WcdBootTimeUtc
    $bootId = $bootUtc.ToString('yyyyMMddTHHmmssZ')
    $canaryPath = Join-Path $paths.Canary ("canary-$bootId.jsonl")
    $warningUntil = [DateTime]::MinValue

    $state = [ordered]@{
        SchemaVersion = 1
        AppVersion = $script:WcdVersion
        BootId = $bootId
        BootTimeUtc = $bootUtc.ToString('o')
        StartedUtc = [DateTime]::UtcNow.ToString('o')
        LastHeartbeatUtc = $null
        CurrentCanaryFile = $canaryPath
        CanaryPid = $PID
        LastIncidentForBootUtc = if ($previousState) { $previousState.LastIncidentForBootUtc } else { $null }
    }

    do {
        Rotate-WcdCanaryFile -Path $canaryPath -Config $config | Out-Null
        $sample = Get-WcdCanarySample -IncludeGpu:([bool]$config.IncludeGpu) -IncludeThermal:([bool]$config.IncludeThermal)
        Write-WcdJsonLine -InputObject $sample -Path $canaryPath
        $state.LastHeartbeatUtc = $sample.TimestampUtc
        Set-WcdState -State $state

        if (Test-WcdWarningSample -Sample $sample -Config $config) {
            $warningUntil = [DateTime]::UtcNow.AddSeconds([int]$config.WarningDurationSeconds)
        }

        if ($Once) { break }
        $sleep = [int]$config.SampleIntervalSeconds
        if ([DateTime]::UtcNow -lt $warningUntil) {
            $sleep = [int]$config.WarningIntervalSeconds
        }
        if ($sleep -lt 1) { $sleep = 1 }
        Start-Sleep -Seconds $sleep
    } while ($true)
}

