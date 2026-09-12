[CmdletBinding()]
param(
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'WindowsCrashDoctor.psm1'
Import-Module $modulePath -Force

try {
    Remove-WcdExpiredData
    Invoke-WcdCanaryLoop -Once:$Once
} catch {
    try {
        $paths = Initialize-WcdDataRoot
        $log = Join-Path $paths.Logs ("canary-error-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
        $message = "[{0}] {1}`r`n{2}`r`n" -f ([DateTime]::UtcNow.ToString('o')), $_.Exception.Message, $_.ScriptStackTrace
        Add-Content -LiteralPath $log -Value $message -Encoding UTF8
    } catch {}
    throw
}
