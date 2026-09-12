[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$EvidencePath,
    [string]$OutputDirectory,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'CrashDoctor.psm1'
Import-Module $modulePath -Force

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = $EvidencePath
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$report = Invoke-CrashDoctorAnalysis -EvidencePath $EvidencePath
$markdown = ConvertTo-CrashDoctorMarkdown -Report $report

$markdownPath = Join-Path $OutputDirectory 'crash-doctor-report.md'
$jsonPath = Join-Path $OutputDirectory 'crash-doctor-report.json'

$markdown | Out-File -LiteralPath $markdownPath -Encoding utf8 -Width 500
$report | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $jsonPath -Encoding utf8 -Width 500

Write-Host "Crash Doctor report: $markdownPath"
Write-Host "Machine-readable report: $jsonPath"

if ($PassThru) {
    return $report
}
