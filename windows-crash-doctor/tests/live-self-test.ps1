[CmdletBinding()]
param(
    [switch]$RepositoryMode
)

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path $env:TEMP ("WcdSelfTest-{0}" -f ([guid]::NewGuid().ToString('N')))
$env:WCD_DATA_ROOT = Join-Path $testRoot 'data'

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    $appRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $module = Join-Path $appRoot 'WindowsCrashDoctor.psm1'
    if (-not (Test-Path -LiteralPath $module)) { throw "Module missing: $module" }

    Import-Module $module -Force

    if ((Get-WcdVersion) -ne '0.1.0') { throw 'Unexpected app version.' }

    $paths = Initialize-WcdDataRoot
    if (-not (Test-Path -LiteralPath $paths.Config)) { throw 'Config was not created.' }
    $config = Get-WcdConfig
    if ([int]$config.SampleIntervalSeconds -lt 1) { throw 'Invalid sample interval.' }

    $sample = Get-WcdCanarySample
    if (-not $sample.TimestampUtc) { throw 'Canary sample did not include a timestamp.' }
    if (-not $sample.BootId) { throw 'Canary sample did not include a boot ID.' }

    Invoke-WcdCanaryLoop -Once
    $state = Get-WcdState
    if (-not $state -or -not $state.LastHeartbeatUtc) { throw 'One-shot canary did not persist heartbeat state.' }

    $capture = Get-WcdCrashCaptureReadiness
    if ($capture.Status -notin @('LikelyReady','Review','NotReady')) { throw 'Crash-capture status was invalid.' }

    $residue = Get-WcdDriverResidue
    if ($null -eq $residue.ProblemDeviceCount) { throw 'Driver-residue result is malformed.' }

    $machine = Get-WcdMachineFacts
    if (-not $machine.OsVersion) { throw 'Machine facts did not include an OS version.' }

    $profileFile = Join-Path $appRoot 'profiles\hp-probook-11-g2.json'
    $profileJson = Get-Content -LiteralPath $profileFile -Raw | ConvertFrom-Json
    if ($profileJson.Id -ne 'hp-probook-11-g2') { throw 'ProBook profile JSON is invalid.' }

    $evidence = Get-WcdEvidence -EventHours 1
    $hypotheses = @(Get-WcdHypotheses -Evidence $evidence)
    if ($hypotheses.Count -lt 8) { throw "Expected at least 8 hypotheses; got $($hypotheses.Count)." }
    foreach ($h in $hypotheses) {
        if ($h.Score -lt 0 -or $h.Score -gt 100) { throw "Hypothesis score out of range: $($h.Id)" }
        if (-not $h.NextDiscriminatingTest) { throw "Hypothesis missing next test: $($h.Id)" }
    }

    $recommendations = @(Get-WcdRecommendations -Evidence $evidence -Hypotheses $hypotheses)
    if ($recommendations.Count -lt 1) { throw 'No recommendations were generated.' }

    $doctor = Invoke-WcdDoctor -EventHours 1 -PassThru
    if (-not (Test-Path -LiteralPath $doctor.JsonReport)) { throw 'JSON report was not written.' }
    if (-not (Test-Path -LiteralPath $doctor.MarkdownReport)) { throw 'Markdown report was not written.' }
    Get-Content -LiteralPath $doctor.JsonReport -Raw | ConvertFrom-Json | Out-Null

    $exp = Start-WcdExperiment -Name 'Self test' -Variable 'Variable A' -Before 'before' -After 'after'
    if (-not $exp.Id) { throw 'Experiment did not get an ID.' }
    $active = Get-WcdExperimentStatus
    if (-not $active) { throw 'Experiment did not persist.' }
    $ended = Stop-WcdExperiment -Outcome inconclusive -Notes 'CI self-test'
    if ($ended.Outcome -ne 'inconclusive') { throw 'Experiment did not close correctly.' }

    $status = Get-WcdStatus
    if ($status.AppVersion -ne '0.1.0') { throw 'Status version mismatch.' }

    if ($RepositoryMode) {
        $repoRoot = Split-Path -Parent $appRoot
        $collector = Join-Path $repoRoot 'scripts\collect-diagnostics.ps1'
        if (-not (Test-Path -LiteralPath $collector)) { throw 'Canonical deep collector is missing.' }

        $workflow = Join-Path $repoRoot '.github\workflows\windows-crash-doctor.yml'
        if (-not (Test-Path -LiteralPath $workflow)) { throw 'Windows Crash Doctor CI workflow is missing.' }

        $bootstrap = Join-Path $appRoot 'bootstrap.ps1'
        $install = Join-Path $appRoot 'install.ps1'
        $uninstall = Join-Path $appRoot 'uninstall.ps1'
        foreach ($file in @($bootstrap,$install,$uninstall)) {
            if (-not (Test-Path -LiteralPath $file)) { throw "Packaging file missing: $file" }
        }
    }

    Write-Host 'Windows Crash Doctor self-test PASSED.' -ForegroundColor Green
    exit 0
} catch {
    Write-Error ("Windows Crash Doctor self-test FAILED: {0}`r`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
    exit 1
} finally {
    Remove-Item Env:\WCD_DATA_ROOT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
