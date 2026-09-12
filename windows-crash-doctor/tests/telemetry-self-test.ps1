[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$crashDoctorRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $crashDoctorRoot 'TelemetryAnalysis.psm1'
Import-Module $modulePath -Force

function Assert-True {
    param(
        [Parameter(Mandatory = $true)] [bool]$Condition,
        [Parameter(Mandatory = $true)] [string]$Message
    )
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("CrashDoctorTelemetryTest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null

try {
    # Deliberately includes a duplicate CPU Package header because HWiNFO does this in real exports.
    @'
Date,Time,"Physical Memory Available [MB]","Physical Memory Load [%]","Virtual Memory Load [%]","Page File Total [MB]","Page File Used [MB]","Total CPU Usage [%]","CPU Package [°C]","CPU Package [°C]","Core Thermal Throttling (avg) [Yes/No]","Total Errors []","Drive Remaining Life [%]","Drive Failure [Yes/No]","Drive Warning [Yes/No]","Total Activity [%]","GT Limit Reasons (avg) [Yes/No]","GT: Fuses limit [Yes/No]","Ring Limit Reasons (avg) [Yes/No]","RING: Max VR Voltage  ICCmax  PL4 [Yes/No]"
12.9.2026,15:16:14.000,360,91,82,2636,650,42,48,48,No,0,86,No,No,12,No,No,No,No
12.9.2026,15:16:16.000,300,92,84,2636,724,100,52,52,No,0,86,No,No,60,Yes,Yes,Yes,Yes
12.9.2026,15:16:18.000,340,90,83,2636,700,35,46,46,No,0,86,No,No,18,No,No,No,No
'@ | Set-Content -LiteralPath (Join-Path $temp 'sensors.csv') -Encoding Default

    @'
<html><script>
var LocalSprData = {"ReportInformation":{"ReportVersion":"1.1","ReportDuration":7,"UtcOffset":600,"ScanTime":"2026-09-12T04:56:16Z","ReportStartTime":"2026-09-05T04:56:15Z"},"ScenarioInstances":[{"Type":9,"EntryTimestamp":"2026-09-12T04:15:59Z","EntryTimestampLocal":"2026-09-12T14:15:59Z","OnAc":false,"Metadata":{"Values":[]}},{"Type":10,"EntryTimestamp":"2042-01-28T10:00:00Z","EntryTimestampLocal":"2042-01-28T20:00:00Z","OnAc":true,"Metadata":{"Values":[{"Key":"EventLog.BugcheckCode","Value":'0x1E'}]}}]};
var OtherData = {};
</script></html>
'@ | Set-Content -LiteralPath (Join-Path $temp 'systempower-report.html') -Encoding utf8

    $telemetry = Invoke-CrashDoctorTelemetryAnalysis -EvidencePath $temp
    Assert-True $telemetry.Available 'Telemetry analysis reported unavailable.'

    $ids = @($telemetry.Findings | ForEach-Object { $_.Id })
    foreach ($expected in @(
        'sensor-sustained-memory-pressure',
        'sensor-no-thermal-throttle-evidence',
        'sensor-whea-counter-clean',
        'sensor-drive-health-reassuring',
        'sensor-capture-continuous',
        'sensor-transient-gpu-ring-limits',
        'sensor-combined-workload-burst',
        'power-report-abnormal-shutdown',
        'power-report-stale-failure-records'
    )) {
        Assert-True ($ids -contains $expected) "Expected finding did not fire: $expected"
    }

    Assert-True (-not ($ids -contains 'power-report-bugcheck')) 'Out-of-window future bugcheck was incorrectly counted as current.'
    Assert-True ($telemetry.Power.Summary.InWindowAbnormalShutdownCount -eq 1) 'Abnormal shutdown count is wrong.'
    Assert-True ($telemetry.Power.Summary.InWindowBugcheckCount -eq 0) 'Future bugcheck contaminated the report window.'
    Assert-True ($telemetry.Power.Summary.OutOfWindowFailureRecordCount -eq 1) 'Out-of-window failure count is wrong.'
    Assert-True ($telemetry.Sensor.Summary.CombinedWorkloadBurstCount -eq 1) 'Combined workload burst was not detected.'
    Assert-True ($telemetry.Sensor.Summary.ThermalThrottleSampleCount -eq 0) 'Quiet thermal fixture reported throttling.'
    Assert-True ($telemetry.Sensor.Summary.WheaTotalErrorsMax -eq 0) 'Quiet WHEA fixture reported an error.'

    $report = [pscustomobject][ordered]@{ Findings = @() }
    $merged = Add-CrashDoctorTelemetryToReport -Report $report -Telemetry $telemetry
    Assert-True (@($merged.Findings).Count -eq @($telemetry.Findings).Count) 'Telemetry findings did not merge into the core report.'
    Assert-True ($null -ne $merged.Telemetry.Sensor) 'Telemetry summary was not attached to the core report.'

    $markdown = ConvertTo-CrashDoctorTelemetryMarkdownSection -Telemetry $telemetry
    Assert-True ($markdown -match 'Telemetry summary') 'Telemetry Markdown section is missing.'
    Assert-True ($markdown -match 'In-window abnormal shutdowns') 'Power-report summary is missing from Markdown.'

    Write-Host 'Windows Crash Doctor telemetry self-test: PASS'
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
