[CmdletBinding()]
param(
    [string]$Ref = 'main'
)

$ErrorActionPreference = 'Stop'
$repo = 'joshualparris/hprobooktroubleshoot'
$base = "https://raw.githubusercontent.com/$repo/$Ref"
$stage = Join-Path $env:TEMP ("WindowsCrashDoctor-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$files = @(
    @{ Remote='windows-crash-doctor/WindowsCrashDoctor.psm1'; Local='WindowsCrashDoctor.psm1' },
    @{ Remote='windows-crash-doctor/windows-crash-doctor.ps1'; Local='windows-crash-doctor.ps1' },
    @{ Remote='windows-crash-doctor/canary.ps1'; Local='canary.ps1' },
    @{ Remote='windows-crash-doctor/config.default.json'; Local='config.default.json' },
    @{ Remote='windows-crash-doctor/install.ps1'; Local='install.ps1' },
    @{ Remote='windows-crash-doctor/uninstall.ps1'; Local='uninstall.ps1' },
    @{ Remote='windows-crash-doctor/lib/Core.ps1'; Local='lib\Core.ps1' },
    @{ Remote='windows-crash-doctor/lib/Evidence.ps1'; Local='lib\Evidence.ps1' },
    @{ Remote='windows-crash-doctor/lib/Hypotheses.ps1'; Local='lib\Hypotheses.ps1' },
    @{ Remote='windows-crash-doctor/lib/Reporting.ps1'; Local='lib\Reporting.ps1' },
    @{ Remote='windows-crash-doctor/lib/Incidents.ps1'; Local='lib\Incidents.ps1' },
    @{ Remote='windows-crash-doctor/lib/Experiments.ps1'; Local='lib\Experiments.ps1' },
    @{ Remote='windows-crash-doctor/profiles/hp-probook-11-g2.json'; Local='profiles\hp-probook-11-g2.json' },
    @{ Remote='scripts/collect-diagnostics.ps1'; Local='collect-diagnostics.ps1' }
)

try {
    foreach ($file in $files) {
        $url = "$base/$($file.Remote)"
        $dest = Join-Path $stage $file.Local
        $parent = Split-Path -Parent $dest
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Write-Host "Downloading $($file.Local)..."
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest
    }

    $installer = Join-Path $stage 'install.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer
    if ($LASTEXITCODE -ne 0) {
        throw "Installer exited with code $LASTEXITCODE."
    }
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
