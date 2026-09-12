[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$OutputCsv = 'evidence-manifest.csv'
)

$root = (Resolve-Path $InputPath).Path.TrimEnd('\')
$outputFullPath = [System.IO.Path]::GetFullPath($OutputCsv)
$prefix = $root + '\'

$files = Get-ChildItem -Path $root -File -Recurse | Where-Object {
    $_.FullName -ne $outputFullPath
}

$rows = foreach ($file in $files) {
    $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256
    $relative = if ($file.FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $file.FullName.Substring($prefix.Length)
    }
    else {
        $file.Name
    }

    [pscustomobject]@{
        RelativePath     = $relative
        Bytes            = $file.Length
        LastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
        SHA256           = $hash.Hash.ToLowerInvariant()
        DuplicateGroup   = ''
    }
}

$duplicateIndex = 1
$groups = @($rows | Group-Object SHA256 | Where-Object Count -gt 1)
foreach ($group in $groups) {
    $label = 'dup-{0:d3}' -f $duplicateIndex
    foreach ($row in $group.Group) {
        $row.DuplicateGroup = $label
    }
    $duplicateIndex++
}

$rows |
    Sort-Object RelativePath |
    Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding utf8

Write-Host "Hashed $(@($rows).Count) file(s) from: $root"
Write-Host "Manifest written to: $OutputCsv"
if ($groups.Count -gt 0) {
    Write-Host "Duplicate-content groups found: $($groups.Count)"
}
