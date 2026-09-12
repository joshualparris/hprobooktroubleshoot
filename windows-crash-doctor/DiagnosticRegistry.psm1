Set-StrictMode -Version Latest

function Get-WcdDiagnosticRegistry {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $PSScriptRoot 'diagnostics\registry.json')
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Crash Doctor diagnostic registry is missing: $Path"
    }

    $registry = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (-not $registry.registryVersion -or -not $registry.diagnostics) {
        throw 'Crash Doctor diagnostic registry is invalid: registryVersion/diagnostics are required.'
    }

    $ids = @($registry.diagnostics | ForEach-Object { [string]$_.id })
    $duplicates = @($ids | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
    if ($duplicates.Count -gt 0) {
        throw "Crash Doctor diagnostic registry contains duplicate IDs: $($duplicates -join ', ')"
    }

    foreach ($diagnostic in @($registry.diagnostics)) {
        if ([string]::IsNullOrWhiteSpace([string]$diagnostic.id) -or
            [string]::IsNullOrWhiteSpace([string]$diagnostic.name) -or
            [string]::IsNullOrWhiteSpace([string]$diagnostic.category) -or
            [string]::IsNullOrWhiteSpace([string]$diagnostic.evidenceFile)) {
            throw 'Every Crash Doctor diagnostic must define id, name, category and evidenceFile.'
        }
    }

    return $registry
}

function Get-WcdRegistryCoverage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$EvidencePath,
        $Registry = (Get-WcdDiagnosticRegistry)
    )

    $resolved = (Resolve-Path -LiteralPath $EvidencePath -ErrorAction Stop).Path
    $present = New-Object System.Collections.Generic.List[string]
    $missing = New-Object System.Collections.Generic.List[string]
    $states = New-Object System.Collections.Generic.List[object]

    foreach ($diagnostic in @($Registry.diagnostics)) {
        $file = [string]$diagnostic.evidenceFile
        $path = Join-Path $resolved $file
        $hasEvidence = (Test-Path -LiteralPath $path -PathType Leaf) -and ((Get-Item -LiteralPath $path).Length -gt 0)
        if ($hasEvidence) { $present.Add($file) } else { $missing.Add($file) }
        $states.Add([pscustomobject][ordered]@{
            Id = [string]$diagnostic.id
            Name = [string]$diagnostic.name
            Category = [string]$diagnostic.category
            EvidenceFile = $file
            State = if ($hasEvidence) { 'healthy' } else { 'unavailable' }
            FailureMode = [string]$diagnostic.failureMode
            RuleVersion = [string]$diagnostic.ruleVersion
        })
    }

    $expected = @($Registry.diagnostics).Count
    $percent = if ($expected -eq 0) { 0.0 } else { [math]::Round(100.0 * $present.Count / $expected, 1) }
    [pscustomobject][ordered]@{
        PresentFiles = @($present)
        MissingFiles = @($missing)
        PresentCount = $present.Count
        ExpectedCount = $expected
        Percent = $percent
        Diagnostics = @($states)
    }
}

Export-ModuleMember -Function Get-WcdDiagnosticRegistry, Get-WcdRegistryCoverage
