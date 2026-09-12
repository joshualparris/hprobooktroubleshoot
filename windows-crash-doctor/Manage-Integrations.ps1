[CmdletBinding()]
param(
    [ValidateSet('catalog', 'status', 'install', 'sensors', 'evtx', 'timeline', 'osquery', 'smart')]
    [string]$Action = 'status',
    [string]$Id,
    [string]$Path,
    [string]$OutputPath,
    [string]$ToolRoot,
    [double]$DurationMinutes = 30,
    [int]$IntervalSeconds = 2,
    [switch]$AllowUnverified
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Integrations.psm1') -Force

switch ($Action) {
    'catalog' {
        Get-WcdIntegrationCatalog |
            Select-Object id, name, repository, license, tier, risk, status, purpose |
            Format-Table -Wrap -AutoSize
    }
    'status' {
        Get-WcdIntegrationStatus -ToolRoot $ToolRoot | Format-Table -AutoSize
    }
    'install' {
        if ([string]::IsNullOrWhiteSpace($Id)) {
            throw 'Use -Id with install, for example: -Action install -Id evtx'
        }
        Install-WcdIntegration -Id $Id -ToolRoot $ToolRoot -AllowUnverified:$AllowUnverified | Format-List
    }
    'sensors' {
        $result = Start-WcdSensorWatch -DurationMinutes $DurationMinutes -IntervalSeconds $IntervalSeconds -OutputPath $OutputPath -ToolRoot $ToolRoot
        Write-Host "Sensor JSONL: $result"
    }
    'evtx' {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw 'Use -Path with evtx to specify an .evtx file.'
        }
        $result = Convert-WcdEvtx -EvtxPath $Path -OutputPath $OutputPath -Format jsonl -ToolRoot $ToolRoot
        Write-Host "Parsed EVTX: $result"
    }
    'timeline' {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw 'Use -Path with timeline to specify a directory containing .evtx files.'
        }
        $result = Invoke-WcdHayabusaTimeline -EvidencePath $Path -OutputPath $OutputPath -ToolRoot $ToolRoot
        Write-Host "Hayabusa timeline: $result"
    }
    'osquery' {
        $result = Invoke-WcdOsqueryInventory -OutputPath $OutputPath -ToolRoot $ToolRoot
        Write-Host "osquery inventory: $result"
    }
    'smart' {
        $result = Invoke-WcdSmartctlInventory -OutputPath $OutputPath -ToolRoot $ToolRoot
        Write-Host "smartctl inventory: $result"
    }
}
