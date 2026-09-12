[CmdletBinding()]
param(
    [switch]$RepositoryMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$crashDoctorRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $crashDoctorRoot
$coreModulePath = Join-Path $crashDoctorRoot 'CrashDoctor.psm1'
$reportingModulePath = Join-Path $crashDoctorRoot 'Reporting.psm1'
$cliPath = Join-Path $crashDoctorRoot 'Invoke-CrashDoctor.ps1'
$securityScanner = Join-Path $repositoryRoot 'scripts\check-public-evidence.ps1'

Import-Module $coreModulePath -Force
Import-Module $reportingModulePath -Force

function Assert-True {
    param(
        [Parameter(Mandatory = $true)] [bool]$Condition,
        [Parameter(Mandatory = $true)] [string]$Message
    )

    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('CrashDoctorSelfTest-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $temp 'fixture-abnormal'
$quietFixture = Join-Path $temp 'fixture-quiet'
$output = Join-Path $temp 'output'
New-Item -ItemType Directory -Path $fixture, $quietFixture, $output -Force | Out-Null

try {
    @'
Model : HP ProBook 11 G2
'@ | Set-Content -LiteralPath (Join-Path $fixture 'computer-system.txt') -Encoding utf8

    @'
SMBIOSBIOSVersion : N92 Ver. 01.04
Name : N92 Ver. 01.04
'@ | Set-Content -LiteralPath (Join-Path $fixture 'bios.txt') -Encoding utf8

    'Capacity : 4294967296' | Set-Content -LiteralPath (Join-Path $fixture 'memory.txt') -Encoding utf8

    @'
AllocatedBaseSize : 1380
CurrentUsage : 127
PeakUsage : 401
CrashDumpEnabled : 7
'@ | Set-Content -LiteralPath (Join-Path $fixture 'pagefile-and-dumps.txt') -Encoding utf8

    @'
ReadErrorsTotal : 0
ReadErrorsUncorrected : 0
Temperature : 40
PowerOnHours : 2242
'@ | Set-Content -LiteralPath (Join-Path $fixture 'storage-reliability.txt') -Encoding utf8

    @'
Hibernate
    Hibernation has not been enabled.
Fast Startup
    Hibernation is not available.
'@ | Set-Content -LiteralPath (Join-Path $fixture 'powercfg-a.txt') -Encoding utf8

    @'
Conversion Status: Encryption in Progress
Percentage Encrypted: 99.0%
Protection Status: Protection Off
'@ | Set-Content -LiteralPath (Join-Path $fixture 'bitlocker-status.txt') -Encoding utf8

    @'
Device Description: HP N92 System Firmware 01.60
Class Name: Firmware
Status: Problem
Problem Code: 10 (0x0A) [CM_PROB_FAILED_START]
Problem Status: 0xC0000001
'@ | Set-Content -LiteralPath (Join-Path $fixture 'problem-devices.txt') -Encoding utf8

    @'
XTUOCDriverService Running
CxMonSvc Running
'@ | Set-Content -LiteralPath (Join-Path $fixture 'interesting-services.txt') -Encoding utf8

    @'
>>> [Sysprep Respecialize - {fixture}]
set: System Product Name: HP ProBook 11 G2
set: Devices non-present: 154 (121 internal, 33 external)
set: SWD\DRIVERENUM\{fixture}#XTUCOMPONENT -> Configured and started
'@ | Set-Content -LiteralPath (Join-Path $fixture 'setupapi.dev.log') -Encoding utf8

    @'
TimeCreated : 12/09/2026 2:15:59 PM
Id : 41
LevelDisplayName : Critical
ProviderName : Microsoft-Windows-Kernel-Power
Message : The system rebooted without cleanly shutting down first.

TimeCreated : 12/09/2026 2:15:58 PM
Id : 161
LevelDisplayName : Error
ProviderName : volmgr
Message : Dump file creation failed due to error during dump creation.
'@ | Set-Content -LiteralPath (Join-Path $fixture 'recent-system-events.txt') -Encoding utf8

    $report = Invoke-CrashDoctorAnalysis -EvidencePath $fixture
    $ids = @($report.Findings | ForEach-Object { $_.Id })
    foreach ($expectedId in @(
        'firmware-device-failed-start',
        'generalised-or-reused-windows-image',
        'intel-xtu-stack-present',
        'crash-dump-capture-risk',
        'storage-counters-reassuring',
        'bitlocker-conversion-active',
        'fast-startup-disabled',
        'kernel-power-41-present',
        'volmgr-161-present'
    )) {
        Assert-True ($ids -contains $expectedId) "Expected finding did not fire: $expectedId"
    }

    Assert-True ($report.EventSummary.WHEAReferences -eq 0) 'Fixture unexpectedly reported WHEA evidence.'
    Assert-True ($report.Inventory.Model -eq 'HP ProBook 11 G2') 'Model parsing failed.'
    Assert-True ($report.Inventory.BIOS -eq 'N92 Ver. 01.04') 'BIOS parsing failed.'

    $markdown = ConvertTo-CrashDoctorMarkdown -Report $report
    Assert-True ($markdown -match 'does not claim') 'Evidence-discipline warning is missing from Markdown output.'

    & $cliPath -EvidencePath $fixture -OutputDirectory $output | Out-Null
    Assert-True (Test-Path -LiteralPath (Join-Path $output 'crash-doctor-report.md')) 'CLI did not produce Markdown output.'
    Assert-True (Test-Path -LiteralPath (Join-Path $output 'crash-doctor-report.json')) 'CLI did not produce JSON output.'

    'Model : Generic Test Laptop' | Set-Content -LiteralPath (Join-Path $quietFixture 'computer-system.txt') -Encoding utf8
    'SMBIOSBIOSVersion : TEST 1.0' | Set-Content -LiteralPath (Join-Path $quietFixture 'bios.txt') -Encoding utf8
    @'
Capacity : 4294967296
Capacity : 4294967296
'@ | Set-Content -LiteralPath (Join-Path $quietFixture 'memory.txt') -Encoding utf8
    @'
AllocatedBaseSize : 8192
CrashDumpEnabled : 7
'@ | Set-Content -LiteralPath (Join-Path $quietFixture 'pagefile-and-dumps.txt') -Encoding utf8
    @'
ReadErrorsTotal : 0
ReadErrorsUncorrected : 0
'@ | Set-Content -LiteralPath (Join-Path $quietFixture 'storage-reliability.txt') -Encoding utf8
    @'
Standby (S3)
Hibernate
Fast Startup
'@ | Set-Content -LiteralPath (Join-Path $quietFixture 'powercfg-a.txt') -Encoding utf8
    'No devices with problems were found.' | Set-Content -LiteralPath (Join-Path $quietFixture 'problem-devices.txt') -Encoding utf8
    @'
Conversion Status: Fully Encrypted
Percentage Encrypted: 100.0%
Protection Status: On
'@ | Set-Content -LiteralPath (Join-Path $quietFixture 'bitlocker-status.txt') -Encoding utf8
    @'
TimeCreated : 12/09/2026 4:00:00 PM
Id : 1
ProviderName : ExampleProvider
Message : Quiet fixture
'@ | Set-Content -LiteralPath (Join-Path $quietFixture 'recent-system-events.txt') -Encoding utf8

    $quietReport = Invoke-CrashDoctorAnalysis -EvidencePath $quietFixture
    $highOrCritical = @($quietReport.Findings | Where-Object { $_.Severity -in @('High', 'Critical') })
    Assert-True ($highOrCritical.Count -eq 0) 'Quiet fixture produced a High/Critical false positive.'
    Assert-True ($quietReport.Inventory.PhysicalMemoryGiB -eq 8) 'Multi-module memory summing failed.'

    if ($RepositoryMode) {
        & $securityScanner -Root $repositoryRoot
    }

    Write-Host 'Windows Crash Doctor self-test: PASS'
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
