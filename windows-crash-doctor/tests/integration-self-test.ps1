[CmdletBinding()]
param(
    [switch]$RepositoryMode
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$module = Join-Path $root 'windows-crash-doctor\Integrations.psm1'
Import-Module $module -Force

$catalog = @(Get-WcdIntegrationCatalog)
if ($catalog.Count -lt 10) {
    throw "Expected a broad integration catalog; found only $($catalog.Count) entries."
}

$ids = @($catalog | ForEach-Object id)
if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) {
    throw 'Integration ids are not unique.'
}

foreach ($entry in $catalog) {
    foreach ($required in @('id', 'name', 'repository', 'license', 'purpose', 'tier', 'risk', 'status', 'installMode', 'adapter')) {
        if (-not ($entry.PSObject.Properties.Name -contains $required) -or
            [string]::IsNullOrWhiteSpace([string]$entry.$required)) {
            throw "Integration '$($entry.id)' is missing required field '$required'."
        }
    }
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wcd-integrations-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $status = @(Get-WcdIntegrationStatus -ToolRoot $temporaryRoot)
    if ($status.Count -ne $catalog.Count) {
        throw "Status count $($status.Count) does not match catalog count $($catalog.Count)."
    }

    $manualRejected = $false
    try {
        Install-WcdIntegration -Id 'chipsec' -ToolRoot $temporaryRoot -WhatIf
    }
    catch {
        $manualRejected = $true
    }
    if (-not $manualRejected) {
        throw 'Privileged/manual integrations must not be accepted by the automatic installer.'
    }

    foreach ($id in @('librehardwaremonitor', 'evtx', 'hayabusa', 'osquery', 'perfview')) {
        $entry = Get-WcdIntegration -Id $id
        if ([string]$entry.status -notmatch 'integrated') {
            throw "Expected '$id' to be an integrated provider."
        }
    }
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS: integration catalog and safety policy ($($catalog.Count) entries)."
