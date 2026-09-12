function Start-WcdExperiment {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Variable,
        [Parameter(Mandatory=$true)][string]$Before,
        [Parameter(Mandatory=$true)][string]$After
    )
    $paths = Initialize-WcdDataRoot
    $active = Join-Path $paths.Experiments 'active.json'
    if (Test-Path -LiteralPath $active) {
        throw 'An experiment is already active. End it before starting another.'
    }
    $exp = [ordered]@{
        SchemaVersion = 1
        Id = [guid]::NewGuid().ToString()
        Name = $Name
        Variable = $Variable
        Before = $Before
        After = $After
        StartedUtc = [DateTime]::UtcNow.ToString('o')
        StartBootId = Get-WcdBootId
        EndedUtc = $null
        Outcome = $null
        Notes = $null
    }
    Write-WcdJson -InputObject $exp -Path $active
    Write-WcdLedgerEntry -Type 'experiment-start' -Data $exp
    return [pscustomobject]$exp
}

function Stop-WcdExperiment {
    param(
        [ValidateSet('stable','failed','inconclusive')][string]$Outcome,
        [string]$Notes
    )
    $paths = Initialize-WcdDataRoot
    $active = Join-Path $paths.Experiments 'active.json'
    if (-not (Test-Path -LiteralPath $active)) {
        throw 'No active experiment exists.'
    }
    $exp = Get-Content -LiteralPath $active -Raw | ConvertFrom-Json
    $exp.EndedUtc = [DateTime]::UtcNow.ToString('o')
    $exp.Outcome = $Outcome
    $exp.Notes = $Notes
    $dest = Join-Path $paths.Experiments ("{0}-{1}.json" -f $exp.StartedUtc.Substring(0,10).Replace('-',''), $exp.Id)
    Write-WcdJson -InputObject $exp -Path $dest
    Remove-Item -LiteralPath $active -Force
    Write-WcdLedgerEntry -Type 'experiment-end' -Data $exp
    return $exp
}

function Get-WcdExperimentStatus {
    $paths = Initialize-WcdDataRoot
    $active = Join-Path $paths.Experiments 'active.json'
    if (Test-Path -LiteralPath $active) {
        return (Get-Content -LiteralPath $active -Raw | ConvertFrom-Json)
    }
    return $null
}

function Get-WcdStatus {
    $paths = Initialize-WcdDataRoot
    $state = Get-WcdState
    $task = $null
    try { $task = Get-ScheduledTask -TaskName 'WindowsCrashDoctor-Canary' -ErrorAction Stop } catch {}
    $lastSample = $null
    if ($state -and $state.CurrentCanaryFile -and (Test-Path -LiteralPath $state.CurrentCanaryFile)) {
        try {
            $lastLine = Get-Content -LiteralPath $state.CurrentCanaryFile -Tail 1 -ErrorAction Stop
            if ($lastLine) { $lastSample = $lastLine | ConvertFrom-Json }
        } catch {}
    }
    [pscustomobject]@{
        AppVersion = $script:WcdVersion
        DataRoot = $paths.Root
        ScheduledTaskState = if ($task) { $task.State } else { 'NotInstalled' }
        BootId = if ($state) { $state.BootId } else { $null }
        LastHeartbeatUtc = if ($state) { $state.LastHeartbeatUtc } else { $null }
        LastSample = $lastSample
        ActiveExperiment = Get-WcdExperimentStatus
    }
}

function Invoke-WcdDeepSnapshot {
    param([string]$OutputRoot)
    $candidate = Join-Path $script:ModuleRoot 'collect-diagnostics.ps1'
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw 'collect-diagnostics.ps1 is not installed alongside Windows Crash Doctor.'
    }
    if ($OutputRoot) {
        & $candidate -OutputRoot $OutputRoot
    } else {
        & $candidate
    }
}

