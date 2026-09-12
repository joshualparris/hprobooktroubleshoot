[CmdletBinding(DefaultParameterSetName = 'Evidence')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Evidence')]
    [string]$EvidencePath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Dump')]
    [string]$DumpPath,

    [string]$OutputDirectory,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$coreModulePath = Join-Path $PSScriptRoot 'CrashDoctor.psm1'
$dumpModulePath = Join-Path $PSScriptRoot 'DumpParser.psm1'
$telemetryModulePath = Join-Path $PSScriptRoot 'TelemetryAnalysis.psm1'
$reportingModulePath = Join-Path $PSScriptRoot 'Reporting.psm1'

foreach ($requiredModule in @($coreModulePath, $dumpModulePath, $telemetryModulePath, $reportingModulePath)) {
    if (-not (Test-Path -LiteralPath $requiredModule -PathType Leaf)) {
        throw "Required Crash Doctor module is missing: $requiredModule"
    }
}

Import-Module $reportingModulePath -Force

function Resolve-WcdOutputDirectory {
    param(
        [AllowNull()] [string]$RequestedDirectory,
        [Parameter(Mandatory = $true)] [string]$DefaultDirectory
    )

    $directory = if ([string]::IsNullOrWhiteSpace($RequestedDirectory)) { $DefaultDirectory } else { $RequestedDirectory }
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    }

    return (Resolve-Path -LiteralPath $directory).Path
}

function Write-WcdReportFiles {
    param(
        [Parameter(Mandatory = $true)] [string]$Directory,
        [Parameter(Mandatory = $true)] [string]$MarkdownFileName,
        [Parameter(Mandatory = $true)] [string]$JsonFileName,
        [Parameter(Mandatory = $true)] [string]$Markdown,
        [Parameter(Mandatory = $true)]$Report
    )

    $markdownPath = Join-Path $Directory $MarkdownFileName
    $jsonPath = Join-Path $Directory $JsonFileName
    $Markdown | Out-File -LiteralPath $markdownPath -Encoding utf8 -Width 500 -ErrorAction Stop
    $Report | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $jsonPath -Encoding utf8 -Width 1000 -ErrorAction Stop

    return [pscustomobject][ordered]@{
        MarkdownPath = $markdownPath
        JsonPath     = $jsonPath
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Dump') {
    Import-Module $dumpModulePath -Force

    if (-not (Test-Path -LiteralPath $DumpPath -PathType Leaf)) {
        throw "Dump file does not exist: $DumpPath"
    }
    $resolvedDump = (Resolve-Path -LiteralPath $DumpPath).Path
    $defaultOutput = Split-Path -Parent $resolvedDump
    $resolvedOutput = Resolve-WcdOutputDirectory -RequestedDirectory $OutputDirectory -DefaultDirectory $defaultOutput

    $report = Get-CrashDoctorDumpInfo -Path $resolvedDump
    $markdown = ConvertTo-CrashDoctorDumpMarkdown -Report $report
    $paths = Write-WcdReportFiles -Directory $resolvedOutput `
        -MarkdownFileName 'crash-doctor-dump-report.md' `
        -JsonFileName 'crash-doctor-dump-report.json' `
        -Markdown $markdown `
        -Report $report

    Write-Host "Crash Doctor dump report: $($paths.MarkdownPath)"
    Write-Host "Machine-readable dump report: $($paths.JsonPath)"
    if ($PassThru) {
        return $report
    }
    return
}

Import-Module $coreModulePath -Force
Import-Module $telemetryModulePath -Force

if (-not (Test-Path -LiteralPath $EvidencePath -PathType Container)) {
    throw "Evidence path does not exist or is not a directory: $EvidencePath"
}
$resolvedEvidence = (Resolve-Path -LiteralPath $EvidencePath).Path
$resolvedOutput = Resolve-WcdOutputDirectory -RequestedDirectory $OutputDirectory -DefaultDirectory $resolvedEvidence

$report = Invoke-CrashDoctorAnalysis -EvidencePath $resolvedEvidence
$telemetry = Invoke-CrashDoctorTelemetryAnalysis -EvidencePath $resolvedEvidence
if ($telemetry.Available -or @($telemetry.Errors).Count -gt 0) {
    $report = Add-CrashDoctorTelemetryToReport -Report $report -Telemetry $telemetry
}

$markdown = ConvertTo-CrashDoctorMarkdown -Report $report
$telemetryMarkdown = ConvertTo-CrashDoctorTelemetryMarkdownSection -Telemetry $telemetry
if (-not [string]::IsNullOrWhiteSpace($telemetryMarkdown)) {
    $markdown += [Environment]::NewLine + [Environment]::NewLine + $telemetryMarkdown
}

$paths = Write-WcdReportFiles -Directory $resolvedOutput `
    -MarkdownFileName 'crash-doctor-report.md' `
    -JsonFileName 'crash-doctor-report.json' `
    -Markdown $markdown `
    -Report $report

Write-Host "Crash Doctor report: $($paths.MarkdownPath)"
Write-Host "Machine-readable report: $($paths.JsonPath)"
if ($PassThru) {
    return $report
}
