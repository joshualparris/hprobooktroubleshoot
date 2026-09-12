[CmdletBinding(DefaultParameterSetName = 'Evidence')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Evidence')] [string]$EvidencePath,
    [Parameter(Mandatory = $true, ParameterSetName = 'Dump')] [string]$DumpPath,
    [string]$OutputDirectory,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

function ConvertTo-CrashDoctorDumpMarkdown {
    param([Parameter(Mandatory = $true)]$Report)

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

        if ($Report.Modules.Count -gt 0) {
            $lines.Add('')
            $lines.Add('## Modules')
            $lines.Add('')
            $lines.Add('| Module | Base | Size |')
            $lines.Add('|---|---:|---:|')
            foreach ($module in $Report.Modules) {
                $name = if ($module.Name) { $module.Name.Replace('|', '\|') } else { '(name unavailable)' }
                $lines.Add(('| {0} | `0x{1:X16}` | {2} |' -f $name, $module.BaseOfImage, $module.SizeOfImage))
            }
        }

        $lines.Add('')
        $lines.Add('## Streams')
        $lines.Add('')
        $lines.Add('| Type | Name | Bytes | RVA |')
        $lines.Add('|---:|---|---:|---:|')
        foreach ($stream in $Report.Streams) {
            $lines.Add("| $($stream.StreamType) | $($stream.Name) | $($stream.DataSize) | $($stream.Rva) |")
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

if ($PSCmdlet.ParameterSetName -eq 'Dump') {
    $dumpModulePath = Join-Path $PSScriptRoot 'DumpParser.psm1'
    Import-Module $dumpModulePath -Force

    $resolvedDump = (Resolve-Path -LiteralPath $DumpPath).Path
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Split-Path -Parent $resolvedDump
    }
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $report = Get-CrashDoctorDumpInfo -Path $resolvedDump
    $markdown = ConvertTo-CrashDoctorDumpMarkdown -Report $report
    $markdownPath = Join-Path $OutputDirectory 'crash-doctor-dump-report.md'
    $jsonPath = Join-Path $OutputDirectory 'crash-doctor-dump-report.json'

    $markdown | Out-File -LiteralPath $markdownPath -Encoding utf8 -Width 500
    $report | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $jsonPath -Encoding utf8 -Width 500

    Write-Host "Crash Doctor dump report: $markdownPath"
    Write-Host "Machine-readable dump report: $jsonPath"

    if ($PassThru) { return $report }
    return
}

$coreModulePath = Join-Path $PSScriptRoot 'CrashDoctor.psm1'
$telemetryModulePath = Join-Path $PSScriptRoot 'TelemetryAnalysis.psm1'
Import-Module $coreModulePath -Force
if (Test-Path -LiteralPath $telemetryModulePath -PathType Leaf) {
    Import-Module $telemetryModulePath -Force
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = $EvidencePath
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$report = Invoke-CrashDoctorAnalysis -EvidencePath $EvidencePath
$telemetry = $null
if (Get-Command Invoke-CrashDoctorTelemetryAnalysis -ErrorAction SilentlyContinue) {
    $telemetry = Invoke-CrashDoctorTelemetryAnalysis -EvidencePath $EvidencePath
    if ($telemetry.Available) {
        $report = Add-CrashDoctorTelemetryToReport -Report $report -Telemetry $telemetry
    }
}

$markdown = ConvertTo-CrashDoctorMarkdown -Report $report
if ($null -ne $telemetry -and $telemetry.Available) {
    $telemetryMarkdown = ConvertTo-CrashDoctorTelemetryMarkdownSection -Telemetry $telemetry
    if (-not [string]::IsNullOrWhiteSpace($telemetryMarkdown)) {
        $markdown += [Environment]::NewLine + [Environment]::NewLine + $telemetryMarkdown
    }
}

$markdownPath = Join-Path $OutputDirectory 'crash-doctor-report.md'
$jsonPath = Join-Path $OutputDirectory 'crash-doctor-report.json'

$markdown | Out-File -LiteralPath $markdownPath -Encoding utf8 -Width 500
$report | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $jsonPath -Encoding utf8 -Width 500

Write-Host "Crash Doctor report: $markdownPath"
Write-Host "Machine-readable report: $jsonPath"

if ($PassThru) {
    return $report
}
