[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Assert-Principle {
    param(
        [Parameter(Mandatory = $true)] [bool]$Condition,
        [Parameter(Mandatory = $true)] [string]$Message
    )
    if (-not $Condition) { throw "PRINCIPLE ASSERTION FAILED: $Message" }
}

function Read-RepoText {
    param([Parameter(Mandatory = $true)] [string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    Assert-Principle (Test-Path -LiteralPath $path -PathType Leaf) "Required repository file is missing: $RelativePath"
    return Get-Content -LiteralPath $path -Raw
}

$mainWindow = Read-RepoText 'desktop/WindowsCrashDoctor.App/MainWindow.xaml.cs'
$mainWindowV2 = Read-RepoText 'desktop/WindowsCrashDoctor.App/MainWindow.V2.cs'
$mainXaml = Read-RepoText 'desktop/WindowsCrashDoctor.App/MainWindow.xaml'
$models = Read-RepoText 'desktop/WindowsCrashDoctor.App/Models/DiagnosticModels.cs'
$workflow = Read-RepoText 'desktop/WindowsCrashDoctor.App/Services/DiagnosticWorkflowService.cs'
$runner = Read-RepoText 'desktop/WindowsCrashDoctor.App/Services/PowerShellRunner.cs'
$history = Read-RepoText 'desktop/WindowsCrashDoctor.App/Services/HistoryService.cs'
$reportReader = Read-RepoText 'desktop/WindowsCrashDoctor.App/Services/CrashDoctorReportReader.cs'
$metrics = Read-RepoText 'desktop/WindowsCrashDoctor.App/Services/SystemMetricsService.cs'
$engineExtractor = Read-RepoText 'desktop/WindowsCrashDoctor.App/Services/EngineExtractor.cs'
$integrationService = Read-RepoText 'desktop/WindowsCrashDoctor.App/Services/IntegrationService.cs'
$collector = Read-RepoText 'scripts/collect-diagnostics.ps1'
$coreWorkflow = Read-RepoText '.github/workflows/windows-crash-doctor.yml'
$desktopWorkflow = Read-RepoText '.github/workflows/windows-crash-doctor-desktop.yml'

# The WPF application is a production surface, not dead scaffolding.
Assert-Principle ($mainXaml -match 'x:Class="WindowsCrashDoctor\.MainWindow"') 'The real WPF MainWindow must remain present.'
Assert-Principle ($mainWindow -match 'DiagnosticWorkflowService') 'MainWindow must delegate diagnosis to the workflow service.'
Assert-Principle ($mainWindow -match 'IntegrationService') 'MainWindow must delegate provider operations to the integration service.'

# Least privilege and exact collection identity.
Assert-Principle ($mainWindow -notmatch 'RelaunchElevated') 'The whole GUI must not relaunch itself elevated.'
Assert-Principle ($mainWindow -notmatch 'Verb\s*=\s*"runas"') 'The presentation layer must not own a runas boundary.'
Assert-Principle ($workflow -match 'RunFileElevatedAsync') 'Only the diagnostic workflow should request collector elevation.'
Assert-Principle ($workflow -match 'ResultPathFile') 'The workflow must request the collector exact-path result contract.'
Assert-Principle ($collector -match '\[string\]\$ResultPathFile') 'The collector must expose an explicit result-path file parameter.'
Assert-Principle ($mainWindow -notmatch 'GetDirectories\("HPProBook-\*"\)') 'The GUI must not guess the latest HPProBook snapshot directory.'

# Directional dependencies and one source of orchestration truth.
Assert-Principle ($models -notmatch 'System\.Windows\.Media') 'Diagnostic/persistence models must not import WPF presentation types.'
Assert-Principle ($models -notmatch '\bBrush\b') 'Diagnostic/persistence models must not expose UI brushes.'
Assert-Principle ($mainWindowV2 -notmatch 'FingerprintService|RunComparisonService|ReportEnrichmentService') 'MainWindow.V2 must not recreate the domain workflow.'
Assert-Principle ($workflow -match 'FingerprintService' -and $workflow -match 'RunComparisonService' -and $workflow -match 'ReportEnrichmentService') 'One workflow service must coordinate the existing comparison/enrichment services.'
Assert-Principle ($integrationService -match 'SafeProviderId') 'Integration IDs must be validated at their service boundary.'

# Boundary validation and persistence evolution.
Assert-Principle ($reportReader -match 'MaxReportBytes' -and $reportReader -match 'SchemaVersion') 'Untrusted report JSON must be size- and schema-validated before UI use.'
Assert-Principle ($mainWindow -notmatch 'JsonSerializer\.Deserialize') 'MainWindow must not deserialize report JSON directly.'
Assert-Principle ($history -match 'PRAGMA user_version = 1') 'SQLite history schema must be explicitly versioned.'
Assert-Principle ($history -match 'SettingsDocument') 'Settings must use a versioned document envelope.'
Assert-Principle ($history -match 'WriteJsonAtomically') 'Settings writes must be staged/atomic.'
Assert-Principle ($history -match 'StartupWarning') 'Persistence failures must remain visible to the UI.'

# Live data must remain truthful and bounded.
Assert-Principle ($metrics -match 'double\? CpuPercent' -and $metrics -match 'double\? MemoryPercent') 'Unavailable live metrics must be represented as unknown, not fake zero values.'
Assert-Principle ($metrics -match 'string\? Warning') 'Live telemetry provider failures must be observable.'
Assert-Principle ($runner -match 'MaxCapturedCharacters') 'Process output buffering must have an explicit ceiling.'
Assert-Principle ($runner -match 'MaximumTimeout') 'External diagnostic work must have an explicit maximum timeout.'

# Engine extraction must have one version source and a rollback-safe replacement path.
Assert-Principle ($engineExtractor -match 'VersionResourceName') 'Desktop engine version must come from embedded version.json.'
Assert-Principle ($engineExtractor -match '\.stage-' -and $engineExtractor -match '\.backup-') 'Embedded engine extraction must stage before replacement and retain rollback state.'

# Accessibility/responsive correctness is now a real requirement because the WPF app exists.
Assert-Principle ($mainWindow -match 'MinWidth\s*=\s*760') 'Desktop runtime minimum width must support smaller laptop displays.'
Assert-Principle ($mainWindow -match 'AutomationProperties\.SetName') 'Key controls must expose explicit automation names.'
Assert-Principle ($mainWindow -match 'AutomationProperties\.SetLiveSetting') 'Changing diagnostic status must be exposed to assistive technology.'
Assert-Principle ($mainWindow -match 'KeyboardNavigation\.SetTabNavigation') 'Keyboard navigation must be explicitly configured.'

# Silent catches are not allowed in the A4-owned desktop architecture paths.
$observableCatchFiles = @(
    'desktop/WindowsCrashDoctor.App/MainWindow.xaml.cs',
    'desktop/WindowsCrashDoctor.App/MainWindow.V2.cs',
    'desktop/WindowsCrashDoctor.App/Services/PowerShellRunner.cs',
    'desktop/WindowsCrashDoctor.App/Services/SystemMetricsService.cs',
    'desktop/WindowsCrashDoctor.App/Services/HistoryService.cs',
    'desktop/WindowsCrashDoctor.App/Services/PrivacyExportService.cs',
    'desktop/WindowsCrashDoctor.App/Services/DesktopSelfTest.cs',
    'desktop/WindowsCrashDoctor.App/Services/ReportEnrichmentService.cs',
    'desktop/WindowsCrashDoctor.App/Services/DiagnosticWorkflowService.cs',
    'desktop/WindowsCrashDoctor.App/Services/CrashDoctorReportReader.cs',
    'desktop/WindowsCrashDoctor.App/Services/IntegrationService.cs'
)
foreach ($relativePath in $observableCatchFiles) {
    $content = Read-RepoText $relativePath
    Assert-Principle ($content -notmatch 'catch\s*(?:\([^\)]*\))?\s*\{\s*\}') "Silent empty catch remains in $relativePath"
}

# Reproducible merge gates: immutable actions, fixed OS/SDK, and desktop PR validation.
Assert-Principle ($coreWorkflow -match 'runs-on:\s*windows-2025') 'Core QA must use a fixed Windows runner image.'
Assert-Principle ($coreWorkflow -match 'actions/checkout@11d5960a326750d5838078e36cf38b85af677262') 'Core checkout action must be pinned by commit.'
Assert-Principle ($desktopWorkflow -match '(?m)^\s*pull_request:') 'Desktop product gate must run before PR merge.'
Assert-Principle ($desktopWorkflow -match 'runs-on:\s*windows-2025') 'Desktop gate must use a fixed Windows runner image.'
Assert-Principle ($desktopWorkflow -match "dotnet-version:\s*'8\.0\.425'") 'Desktop gate must use the exact audited .NET SDK.'
Assert-Principle ($desktopWorkflow -match 'actions/setup-dotnet@67a3573c9a986a3f9c594539f4ab511d57bb3ce9') 'setup-dotnet must be pinned by commit.'
Assert-Principle ($desktopWorkflow -match 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02') 'upload-artifact must be pinned by commit.'
Assert-Principle ($desktopWorkflow -match 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093') 'download-artifact must be pinned by commit.'

Write-Host 'Windows Crash Doctor principles self-test: PASS'
