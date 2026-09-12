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

    It 'does not auto-install privileged manual integrations' {
        { Install-WcdIntegration -Id 'chipsec' -ToolRoot $TestDrive -WhatIf } | Should -Throw
        { Install-WcdIntegration -Id 'memtest86plus' -ToolRoot $TestDrive -WhatIf } | Should -Throw
    }

    It 'reports every catalog entry even when no tools are installed' {
        $catalog = @(Get-WcdIntegrationCatalog)
        $status = @(Get-WcdIntegrationStatus -ToolRoot $TestDrive)
        $status.Count | Should -Be $catalog.Count
    }

    It 'keeps risky tools opt-in or manual' {
        (Get-WcdIntegration -Id 'hayabusa').status | Should -Match 'opt-in'
        (Get-WcdIntegration -Id 'chipsec').status | Should -Match 'manual'
        (Get-WcdIntegration -Id 'velociraptor').status | Should -Match 'not-imported'
    }
}
