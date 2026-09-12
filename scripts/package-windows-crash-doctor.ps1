[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $repoRoot 'windows-crash-doctor'
$collector = Join-Path $repoRoot 'scripts\collect-diagnostics.ps1'

if (-not (Test-Path -LiteralPath $appRoot)) { throw 'windows-crash-doctor directory is missing.' }
if (-not (Test-Path -LiteralPath $collector)) { throw 'Canonical collect-diagnostics.ps1 is missing.' }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stage = Join-Path $env:TEMP ("WcdPackage-{0}" -f ([guid]::NewGuid().ToString('N')))
$payload = Join-Path $stage 'WindowsCrashDoctor'
New-Item -ItemType Directory -Path $payload -Force | Out-Null

try {
    Copy-Item -LiteralPath (Join-Path $appRoot 'WindowsCrashDoctor.psm1') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'CrashDoctor.psm1') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'Invoke-CrashDoctor.ps1') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'windows-crash-doctor.ps1') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'canary.ps1') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'config.default.json') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'install.ps1') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'uninstall.ps1') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'bootstrap.ps1') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'README.md') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $appRoot 'profiles') -Destination $payload -Recurse
    Copy-Item -LiteralPath (Join-Path $appRoot 'lib') -Destination $payload -Recurse
    Copy-Item -LiteralPath $collector -Destination (Join-Path $payload 'collect-diagnostics.ps1')

    $versionMatch = Select-String -LiteralPath (Join-Path $appRoot 'WindowsCrashDoctor.psm1') -Pattern "\$script:WcdVersion\s*=\s*'([^']+)'" | Select-Object -First 1
    $version = if ($versionMatch) { $versionMatch.Matches[0].Groups[1].Value } else { 'dev' }
    $zip = Join-Path $OutputDirectory ("WindowsCrashDoctor-v{0}.zip" -f $version)
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    Compress-Archive -LiteralPath $payload -DestinationPath $zip -CompressionLevel Optimal

    $hash = Get-FileHash -LiteralPath $zip -Algorithm SHA256
    $hashPath = "$zip.sha256"
    ("{0}  {1}" -f $hash.Hash.ToLowerInvariant(), (Split-Path -Leaf $zip)) | Set-Content -LiteralPath $hashPath -Encoding ASCII

    Write-Host "Package: $zip" -ForegroundColor Green
    Write-Host "SHA256:  $($hash.Hash.ToLowerInvariant())"
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
