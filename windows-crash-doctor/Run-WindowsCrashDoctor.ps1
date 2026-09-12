[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Windows Crash Doctor Results'),

    [ValidateRange(1, 168)]
    [int]$EventHours = 12
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-WcdAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-WcdCommandLineSafePath {
    param([Parameter(Mandatory = $true)] [string]$Path)
    if ($Path.Contains('"')) {
        throw "Path cannot contain a double-quote character: $Path"
    }
}

function Write-WcdStep {
    param(
        [Parameter(Mandatory = $true)] [string]$Message,
        [Parameter(Mandatory = $true)] [string]$SessionLog
    )

    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line -ForegroundColor Cyan
    Add-Content -LiteralPath $SessionLog -Value $line -Encoding UTF8 -ErrorAction Stop
}

function Invoke-WcdLogged {
    param(
        [Parameter(Mandatory = $true)] [scriptblock]$Action,
        [Parameter(Mandatory = $true)] [string]$SessionLog
    )

    & $Action 2>&1 | ForEach-Object {
        $text = ($_ | Out-String).TrimEnd()
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-Host $text
            Add-Content -LiteralPath $SessionLog -Value $text -Encoding UTF8 -ErrorAction Stop
        }
    }
}

function Invoke-WcdCollector {
    param(
        [Parameter(Mandatory = $true)] [string]$CollectorPath,
        [Parameter(Mandatory = $true)] [string]$OutputRoot,
        [Parameter(Mandatory = $true)] [int]$EventHours,
        [Parameter(Mandatory = $true)] [string]$ResultPathFile,
        [Parameter(Mandatory = $true)] [string]$SessionLog
    )

    if (Test-WcdAdministrator) {
        Invoke-WcdLogged -SessionLog $SessionLog -Action {
            & $CollectorPath -OutputRoot $OutputRoot -EventHours $EventHours -ResultPathFile $ResultPathFile
        }
        return
    }

    foreach ($path in @($CollectorPath, $OutputRoot, $ResultPathFile)) {
        Assert-WcdCommandLineSafePath -Path $path
    }

    # Only the collector needs Administrator rights; analysis, tests and reporting remain least-privileged.
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $CollectorPath),
        '-OutputRoot', ('"{0}"' -f $OutputRoot),
        '-EventHours', [string]$EventHours,
        '-ResultPathFile', ('"{0}"' -f $ResultPathFile)
    ) -join ' '

    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -PassThru -Wait -ErrorAction Stop
    if ($process.ExitCode -ne 0) {
        throw "Elevated diagnostic collector exited with code $($process.ExitCode)."
    }
}

function Read-WcdCollectorResultPath {
    param([Parameter(Mandatory = $true)] [string]$ResultPathFile)

    if (-not (Test-Path -LiteralPath $ResultPathFile -PathType Leaf)) {
        throw 'Diagnostic collection completed without returning its snapshot path.'
    }

    $path = (Get-Content -LiteralPath $ResultPathFile -Raw -ErrorAction Stop).Trim()
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Container)) {
        throw 'Diagnostic collector returned an invalid snapshot path.'
    }
    return (Resolve-Path -LiteralPath $path).Path
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$collector = Join-Path $repositoryRoot 'scripts\collect-diagnostics.ps1'
$crashDoctor = Join-Path $PSScriptRoot 'Invoke-CrashDoctor.ps1'
$selfTest = Join-Path $PSScriptRoot 'tests\self-test.ps1'
$integrationSelfTest = Join-Path $PSScriptRoot 'tests\integration-self-test.ps1'
$integrationManager = Join-Path $PSScriptRoot 'Manage-Integrations.ps1'

foreach ($required in @($collector, $crashDoctor, $selfTest, $integrationSelfTest, $integrationManager)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Windows Crash Doctor file is missing: $required"
    }
}

New-Item -ItemType Directory -Path $OutputRoot -Force -ErrorAction Stop | Out-Null
$resolvedOutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
$runId = [guid]::NewGuid().ToString('N')
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionLog = Join-Path $resolvedOutputRoot ('CrashDoctor-Run-{0}-{1}.txt' -f $runStamp, $runId.Substring(0, 8))
$resultPathFile = Join-Path ([IO.Path]::GetTempPath()) ('WcdCollectorResult-{0}.txt' -f $runId)

try {
    Write-WcdStep -SessionLog $sessionLog -Message 'Windows Crash Doctor one-click test starting.'
    Write-WcdStep -SessionLog $sessionLog -Message 'Running built-in regression self-test without elevation.'
    Invoke-WcdLogged -SessionLog $sessionLog -Action { & $selfTest -RepositoryMode }

    Write-WcdStep -SessionLog $sessionLog -Message 'Running integration policy self-test without elevation.'
    Invoke-WcdLogged -SessionLog $sessionLog -Action { & $integrationSelfTest }

    Write-WcdStep -SessionLog $sessionLog -Message 'Collecting a fresh read-only diagnostic snapshot; only this step requests elevation when needed.'
    Invoke-WcdCollector -CollectorPath $collector -OutputRoot $resolvedOutputRoot -EventHours $EventHours -ResultPathFile $resultPathFile -SessionLog $sessionLog
    $snapshot = Read-WcdCollectorResultPath -ResultPathFile $resultPathFile

    $collectionStatusPath = Join-Path $snapshot 'collection-status.json'
    if (Test-Path -LiteralPath $collectionStatusPath -PathType Leaf) {
        $statusFile = Get-Item -LiteralPath $collectionStatusPath -ErrorAction Stop
        if ($statusFile.Length -gt 1048576) { throw 'collection-status.json exceeds the 1 MiB safety limit.' }
        $collectionStatus = Get-Content -LiteralPath $collectionStatusPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($collectionStatus.CompletedWithErrors) {
            Write-WcdStep -SessionLog $sessionLog -Message ("Collection is partial: {0} stage(s) failed; analysis will mark missing evidence as unknown." -f $collectionStatus.FailureCount)
        }
    }

    Write-WcdStep -SessionLog $sessionLog -Message ("Analysing snapshot: {0}" -f $snapshot)
    Invoke-WcdLogged -SessionLog $sessionLog -Action { & $crashDoctor -EvidencePath $snapshot -OutputDirectory $snapshot }

    Write-WcdStep -SessionLog $sessionLog -Message 'Recording optional integration/provider status.'
    $providerStatus = Join-Path $snapshot 'integration-status.txt'
    & $integrationManager -Action status 2>&1 | Out-File -LiteralPath $providerStatus -Encoding UTF8 -Width 240 -ErrorAction Stop

    $report = Join-Path $snapshot 'crash-doctor-report.md'
    $jsonReport = Join-Path $snapshot 'crash-doctor-report.json'
    if (-not (Test-Path -LiteralPath $report -PathType Leaf) -or -not (Test-Path -LiteralPath $jsonReport -PathType Leaf)) {
        throw 'Crash Doctor did not produce both Markdown and JSON reports.'
    }

    Write-WcdStep -SessionLog $sessionLog -Message 'PASS: installation tests, collection and real-machine analysis all completed.'
    Write-WcdStep -SessionLog $sessionLog -Message ("Report: {0}" -f $report)

    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $snapshot) -ErrorAction Stop | Out-Null }
    catch { Write-Warning "Could not open results folder: $($_.Exception.Message)" }
    try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $report) -ErrorAction Stop | Out-Null }
    catch { Write-Warning "Could not open report: $($_.Exception.Message)" }

    Write-Host ''
    Write-Host 'Windows Crash Doctor: PASS' -ForegroundColor Green
    Write-Host "Your report is here: $report" -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $resultPathFile -Force -ErrorAction SilentlyContinue
}
