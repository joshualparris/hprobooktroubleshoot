[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$crashDoctorRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $crashDoctorRoot

function Assert-WcdPrinciple {
    param(
        [Parameter(Mandatory = $true)] [bool]$Condition,
        [Parameter(Mandatory = $true)] [string]$Message
    )
    if (-not $Condition) { throw "PRINCIPLE ASSERTION FAILED: $Message" }
}

function Read-WcdRepositoryText {
    param([Parameter(Mandatory = $true)] [string]$RelativePath)
    return Get-Content -LiteralPath (Join-Path $repositoryRoot $RelativePath) -Raw -ErrorAction Stop
}

$findingModel = Read-WcdRepositoryText 'windows-crash-doctor\FindingModel.psm1'
$core = Read-WcdRepositoryText 'windows-crash-doctor\CrashDoctor.psm1'
$telemetry = Read-WcdRepositoryText 'windows-crash-doctor\TelemetryAnalysis.psm1'
$reporting = Read-WcdRepositoryText 'windows-crash-doctor\Reporting.psm1'
$installer = Read-WcdRepositoryText 'scripts\Install-WindowsCrashDoctor.ps1'
$runner = Read-WcdRepositoryText 'windows-crash-doctor\Run-WindowsCrashDoctor.ps1'
$collector = Read-WcdRepositoryText 'scripts\collect-diagnostics.ps1'
$catalog = Read-WcdRepositoryText 'windows-crash-doctor\integrations\catalog.json'
$workflow = Read-WcdRepositoryText '.github\workflows\windows-crash-doctor.yml'

Assert-WcdPrinciple ($findingModel -match 'function New-CrashDoctorFinding') 'FindingModel.psm1 must own the finding constructor.'
Assert-WcdPrinciple ($core -notmatch 'function New-CrashDoctorFinding') 'Core analysis must not duplicate the finding constructor.'
Assert-WcdPrinciple ($telemetry -notmatch 'function New-(Telemetry|CrashDoctor)Finding') 'Telemetry must use the canonical finding model.'
Assert-WcdPrinciple ($reporting -match 'function ConvertTo-CrashDoctorMarkdown') 'Reporting.psm1 must own report formatting.'
Assert-WcdPrinciple ($core -notmatch 'function ConvertTo-CrashDoctorMarkdown') 'Core analysis must not own presentation formatting.'
Assert-WcdPrinciple ($telemetry -notmatch 'function ConvertTo-CrashDoctorTelemetryMarkdownSection') 'Telemetry analysis must not own presentation formatting.'

Assert-WcdPrinciple ($installer -notmatch 'Verb\s+RunAs') 'Installer must not elevate user-local installation work.'
Assert-WcdPrinciple ($installer -notmatch 'refs/heads/main\.zip') 'Installer must not install a mutable main.zip artifact.'
Assert-WcdPrinciple ($installer -match 'CommitSha') 'Installer must identify the exact source commit.'
Assert-WcdPrinciple ($runner -match 'Verb\s+RunAs') 'Runner must retain an explicit collector-only elevation boundary.'
Assert-WcdPrinciple ($runner -match 'ResultPathFile') 'Runner must receive the snapshot path explicitly rather than infer it from directory timestamps.'

Assert-WcdPrinciple ($collector -notmatch '\bUserName\b') 'Default collection metadata must not store the account username.'
Assert-WcdPrinciple ($collector -notmatch '\bComputerName\b') 'Default collection metadata must not store the computer name.'
Assert-WcdPrinciple ($collector -match 'collection-status\.json') 'Collector must expose structured partial-failure state.'
Assert-WcdPrinciple ($collector -match 'CollectionId') 'Collector output must have a collision-resistant identity.'

Assert-WcdPrinciple ($catalog -notmatch '/releases/latest') 'Runtime dependency catalogue must not use mutable latest-release endpoints.'
Assert-WcdPrinciple ($catalog -match '"packageVersion": "5\.9\.0"') 'Pester version must be pinned in the dependency catalogue.'
Assert-WcdPrinciple ($catalog -match '"packageVersion": "1\.25\.0"') 'PSScriptAnalyzer version must be pinned in the dependency catalogue.'
Assert-WcdPrinciple ($workflow -match 'runs-on:\s*windows-2025') 'CI runner image must be pinned to Windows 2025.'
Assert-WcdPrinciple ($workflow -notmatch 'actions/(?:checkout|upload-artifact)@v\d') 'CI actions must use immutable commit SHAs, not moving major tags.'

$deadDesktopScaffold = Join-Path $repositoryRoot 'desktop\WindowsCrashDoctor.App'
Assert-WcdPrinciple (-not (Test-Path -LiteralPath $deadDesktopScaffold)) 'Dead desktop-app scaffolding must not remain in the repository.'

foreach ($module in Get-ChildItem -LiteralPath $crashDoctorRoot -Filter '*.psm1' -File) {
    $text = Get-Content -LiteralPath $module.FullName -Raw -ErrorAction Stop
    Assert-WcdPrinciple ($text -match 'Set-StrictMode\s+-Version\s+Latest') "$($module.Name) must enable StrictMode."
}

Write-Host 'Windows Crash Doctor code-principles self-test: PASS'
