# Windows Crash Doctor core module
# Compatible with Windows PowerShell 5.1 and PowerShell 7+ on Windows.

$script:WcdVersion = '0.1.0'
$script:ModuleRoot = $PSScriptRoot

foreach ($part in @('Core.ps1','Evidence.ps1','Analysis.ps1','Experiments.ps1')) {
    . (Join-Path (Join-Path $PSScriptRoot 'lib') $part)
}

Export-ModuleMember -Function @(
    'Get-WcdVersion',
    'Get-WcdDataRoot',
    'Get-WcdPaths',
    'Initialize-WcdDataRoot',
    'Get-WcdConfig',
    'Get-WcdState',
    'Get-WcdCanarySample',
    'Get-WcdRecentCanary',
    'Get-WcdEventTimeline',
    'Get-WcdCrashCaptureReadiness',
    'Get-WcdDriverResidue',
    'Get-WcdMachineFacts',
    'Get-WcdStorageEvidence',
    'Get-WcdMachineProfile',
    'Get-WcdEvidence',
    'Get-WcdHypotheses',
    'Get-WcdRecommendations',
    'Invoke-WcdDoctor',
    'New-WcdIncidentBundle',
    'Invoke-WcdDetectPreviousIncident',
    'Invoke-WcdCanaryLoop',
    'Start-WcdExperiment',
    'Stop-WcdExperiment',
    'Get-WcdExperimentStatus',
    'Get-WcdStatus',
    'Invoke-WcdDeepSnapshot',
    'Remove-WcdExpiredData'
)
