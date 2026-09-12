BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'windows-crash-doctor\Integrations.psm1') -Force
}

Describe 'Windows Crash Doctor open-source integrations' {
    It 'has unique catalog ids and the expected core providers' {
        $catalog = @(Get-WcdIntegrationCatalog)
        $catalog.Count | Should -BeGreaterOrEqual 10
        @($catalog.id | Sort-Object -Unique).Count | Should -Be $catalog.Count
        foreach ($id in @('librehardwaremonitor', 'smartmontools', 'evtx', 'hayabusa', 'osquery', 'perfview', 'pester', 'psscriptanalyzer')) {
            $catalog.id | Should -Contain $id
        }
    }

    It 'pins every downloadable integration to an immutable release tag' {
        $downloadable = @(Get-WcdIntegrationCatalog | Where-Object installMode -in @('github-release-zip', 'github-release-file', 'manual-installer-download'))
        foreach ($entry in $downloadable) {
            $entry.releaseTag | Should -Not -BeNullOrEmpty
            $entry.releaseApi | Should -Match '/releases/tags/'
            $entry.releaseApi | Should -Not -Match '/releases/latest$'
            $entry.assetRegex | Should -Not -BeNullOrEmpty
        }
    }

    It 'pins PowerShell QA package versions in the catalog' {
        (Get-WcdIntegration -Id 'pester').packageVersion | Should -Be '5.9.0'
        (Get-WcdIntegration -Id 'psscriptanalyzer').packageVersion | Should -Be '1.25.0'
    }

    It 'rejects malformed and duplicate-id catalogs at the boundary' {
        $invalidJson = Join-Path $TestDrive 'invalid.json'
        '{not-json' | Set-Content -LiteralPath $invalidJson -Encoding UTF8
        { Get-WcdIntegrationCatalog -CatalogPath $invalidJson } | Should -Throw

        $duplicate = Join-Path $TestDrive 'duplicate.json'
        @'
{
  "schemaVersion": "1.1",
  "integrations": [
    {"id":"same","name":"A","repository":"owner/a","license":"MIT","purpose":"test","tier":"test","risk":"low","status":"test","installMode":"manual","adapter":"external"},
    {"id":"same","name":"B","repository":"owner/b","license":"MIT","purpose":"test","tier":"test","risk":"low","status":"test","installMode":"manual","adapter":"external"}
  ]
}
'@ | Set-Content -LiteralPath $duplicate -Encoding UTF8
        { Get-WcdIntegrationCatalog -CatalogPath $duplicate } | Should -Throw
    }

    It 'does not auto-install privileged manual integrations' {
        { Install-WcdIntegration -Id 'chipsec' -ToolRoot $TestDrive -WhatIf } | Should -Throw
        { Install-WcdIntegration -Id 'memtest86plus' -ToolRoot $TestDrive -WhatIf } | Should -Throw
    }

    It 'reports every catalog entry even when no tools are installed' {
        $catalog = @(Get-WcdIntegrationCatalog)
        $status = @(Get-WcdIntegrationStatus -ToolRoot $TestDrive)
        $status.Count | Should -Be $catalog.Count
    }

    It 'surfaces corrupt local installation metadata instead of hiding it' {
        $providerRoot = Join-Path $TestDrive 'librehardwaremonitor'
        New-Item -ItemType Directory -Path $providerRoot -Force | Out-Null
        '{bad-json' | Set-Content -LiteralPath (Join-Path $providerRoot 'installation.json') -Encoding UTF8

        $status = Get-WcdIntegrationStatus -ToolRoot $TestDrive | Where-Object Id -eq 'librehardwaremonitor'
        $status.Error | Should -Match 'metadata:'
        $status.Installed | Should -BeFalse
    }

    It 'keeps risky tools opt-in or manual' {
        (Get-WcdIntegration -Id 'hayabusa').status | Should -Match 'opt-in'
        (Get-WcdIntegration -Id 'chipsec').status | Should -Match 'manual'
        (Get-WcdIntegration -Id 'velociraptor').status | Should -Match 'not-imported'
    }
}
