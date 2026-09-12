[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('doctor','status','sample','incident','collect','experiment-start','experiment-end','experiment-status','help')]
    [string]$Command = 'doctor',

    [string]$Name,
    [string]$Variable,
    [string]$Before,
    [string]$After,

    [ValidateSet('stable','failed','inconclusive')]
    [string]$Outcome,
    [string]$Notes,
    [int]$EventHours = 72,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'WindowsCrashDoctor.psm1'
Import-Module $modulePath -Force

function Show-WcdHelp {
@'
Windows Crash Doctor

Usage:
  .\windows-crash-doctor.ps1 doctor
  .\windows-crash-doctor.ps1 status
  .\windows-crash-doctor.ps1 sample
  .\windows-crash-doctor.ps1 incident
  .\windows-crash-doctor.ps1 collect
  .\windows-crash-doctor.ps1 experiment-start -Name "Fast Startup off" -Variable "Fast Startup" -Before "Enabled" -After "Disabled"
  .\windows-crash-doctor.ps1 experiment-end -Outcome stable -Notes "24 hours, 6 cold boots, no freeze"
  .\windows-crash-doctor.ps1 experiment-status

Commands:
  doctor             Collect current evidence, rank hypotheses and write JSON + Markdown reports.
  status             Show canary heartbeat, scheduled-task state and active experiment.
  sample             Take one canary sample without starting the background loop.
  incident           Create an incident bundle now using the recent canary and event timeline.
  collect            Run the deep snapshot collector.
  experiment-start   Begin a one-variable-at-a-time A/B experiment.
  experiment-end     Close the active experiment as stable, failed or inconclusive.
  experiment-status  Show the active experiment.
  help               Show this text.

Data:
  %ProgramData%\WindowsCrashDoctor

Important:
  Hypothesis scores are triage weights, not probabilities.
  Crash Doctor never treats correlation as proof of causation.
'@ | Write-Host
}

switch ($Command) {
    'doctor' {
        Invoke-WcdDoctor -EventHours $EventHours
    }
    'status' {
        Get-WcdStatus | Format-List
    }
    'sample' {
        Get-WcdCanarySample -IncludeGpu -IncludeThermal | Format-List
    }
    'incident' {
        $now = [DateTime]::UtcNow
        $path = New-WcdIncidentBundle -IncidentEndUtc $now -Reason 'manual-incident'
        Write-Host "Incident bundle: $path" -ForegroundColor Cyan
    }
    'collect' {
        Invoke-WcdDeepSnapshot -OutputRoot $OutputRoot
    }
    'experiment-start' {
        if (-not $Name -or -not $Variable -or -not $Before -or -not $After) {
            throw 'experiment-start requires -Name, -Variable, -Before and -After.'
        }
        Start-WcdExperiment -Name $Name -Variable $Variable -Before $Before -After $After | Format-List
    }
    'experiment-end' {
        if (-not $Outcome) {
            throw 'experiment-end requires -Outcome stable, failed or inconclusive.'
        }
        Stop-WcdExperiment -Outcome $Outcome -Notes $Notes | Format-List
    }
    'experiment-status' {
        $exp = Get-WcdExperimentStatus
        if ($exp) { $exp | Format-List } else { Write-Host 'No active experiment.' }
    }
    'help' {
        Show-WcdHelp
    }
}
