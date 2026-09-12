Set-StrictMode -Version Latest

$script:IntegrationCatalogSchemaVersion = '1.1'
$script:MaxCatalogBytes = 1048576
$script:MaxInstallationMetadataBytes = 1048576
$script:MaxDownloadBytes = 536870912
$script:MaxArtifactSearchFiles = 10000
$script:MaxHardwareNodes = 4096
$script:MaxSensorOutputBytes = 536870912

function Get-WcdDefaultCatalogPath {
    return (Join-Path $PSScriptRoot 'integrations\catalog.json')
}

function Assert-WcdIntegrationCatalogEntry {
    param([Parameter(Mandatory = $true)]$Entry)

    foreach ($propertyName in @('id', 'name', 'repository', 'license', 'purpose', 'tier', 'risk', 'status', 'installMode', 'adapter')) {
        if ($null -eq $Entry.PSObject.Properties[$propertyName] -or [string]::IsNullOrWhiteSpace([string]$Entry.$propertyName)) {
            throw "Integration catalog entry is missing required property '$propertyName'."
        }
    }

    if ([string]$Entry.id -notmatch '^[a-z0-9][a-z0-9-]*$') {
        throw "Integration id '$($Entry.id)' is not a stable lowercase identifier."
    }
    if ([string]$Entry.repository -notmatch '^[^/\s]+/[^/\s]+$') {
        throw "Integration '$($Entry.id)' has invalid repository '$($Entry.repository)'."
    }

    $allowedModes = @(
        'github-release-zip',
        'github-release-file',
        'manual-installer-download',
        'powershell-gallery',
        'manual-boot-media',
        'manual',
        'library',
        'none'
    )
    if ([string]$Entry.installMode -notin $allowedModes) {
        throw "Integration '$($Entry.id)' has unsupported installMode '$($Entry.installMode)'."
    }

    if ([string]$Entry.installMode -in @('github-release-zip', 'github-release-file', 'manual-installer-download')) {
        foreach ($propertyName in @('releaseTag', 'releaseApi', 'assetRegex')) {
            if ($null -eq $Entry.PSObject.Properties[$propertyName] -or [string]::IsNullOrWhiteSpace([string]$Entry.$propertyName)) {
                throw "Downloadable integration '$($Entry.id)' is missing '$propertyName'."
            }
        }

        $releaseUri = $null
        if (-not [uri]::TryCreate([string]$Entry.releaseApi, [UriKind]::Absolute, [ref]$releaseUri) -or
            $releaseUri.Scheme -ne 'https' -or
            $releaseUri.Host -ne 'api.github.com') {
            throw "Integration '$($Entry.id)' releaseApi must be an HTTPS api.github.com URL."
        }

        $expectedSuffix = '/releases/tags/' + [uri]::EscapeDataString([string]$Entry.releaseTag)
        if (-not $releaseUri.AbsolutePath.EndsWith($expectedSuffix, [StringComparison]::Ordinal)) {
            throw "Integration '$($Entry.id)' releaseApi is not pinned to releaseTag '$($Entry.releaseTag)'."
        }

        if ($null -ne $Entry.PSObject.Properties['assetSHA256'] -and
            -not [string]::IsNullOrWhiteSpace([string]$Entry.assetSHA256) -and
            [string]$Entry.assetSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Integration '$($Entry.id)' has an invalid assetSHA256."
        }
    }

    if ([string]$Entry.installMode -eq 'powershell-gallery') {
        $version = [version]'0.0'
        if ($null -eq $Entry.PSObject.Properties['packageVersion'] -or
            -not [version]::TryParse([string]$Entry.packageVersion, [ref]$version)) {
            throw "PowerShell Gallery integration '$($Entry.id)' requires a valid packageVersion."
        }
    }
}

function Get-WcdIntegrationCatalog {
    [CmdletBinding()]
    param([string]$CatalogPath = (Get-WcdDefaultCatalogPath))

    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        throw "Integration catalog is missing: $CatalogPath"
    }

    $file = Get-Item -LiteralPath $CatalogPath -ErrorAction Stop
    if ($file.Length -gt $script:MaxCatalogBytes) {
        throw "Integration catalog exceeds the $script:MaxCatalogBytes-byte safety limit."
    }

    try {
        $catalog = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Integration catalog is not valid JSON: $($_.Exception.Message)"
    }

    if ([string]$catalog.schemaVersion -ne $script:IntegrationCatalogSchemaVersion) {
        throw "Unsupported integration catalog schema '$($catalog.schemaVersion)'; expected '$script:IntegrationCatalogSchemaVersion'."
    }
    if ($null -eq $catalog.PSObject.Properties['integrations']) {
        throw 'Integration catalog is missing the integrations array.'
    }

    $entries = @($catalog.integrations)
    if ($entries.Count -eq 0) {
        throw 'Integration catalog contains no integrations.'
    }

    $ids = @{}
    foreach ($entry in $entries) {
        Assert-WcdIntegrationCatalogEntry -Entry $entry
        $id = [string]$entry.id
        if ($ids.ContainsKey($id)) {
            throw "Integration catalog contains duplicate id '$id'."
        }
        $ids[$id] = $true
    }

    return $entries
}

function Get-WcdIntegration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )

    $matches = @(Get-WcdIntegrationCatalog | Where-Object { $_.id -eq $Id })
    if ($matches.Count -ne 1) {
        throw "Unknown integration id: $Id"
    }
    return $matches[0]
}

function Get-WcdToolRoot {
    param([string]$ToolRoot)

    if (-not [string]::IsNullOrWhiteSpace($ToolRoot)) {
        return [IO.Path]::GetFullPath($ToolRoot)
    }

    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = [Environment]::GetFolderPath('LocalApplicationData')
    }
    if ([string]::IsNullOrWhiteSpace($base)) {
        throw 'Unable to resolve LocalApplicationData for the Crash Doctor tool store.'
    }

    return (Join-Path $base 'WindowsCrashDoctor\Tools')
}

function Get-WcdIntegrationMetadata {
    param(
        [Parameter(Mandatory = $true)] [string]$Id,
        [string]$ToolRoot
    )

    $root = Get-WcdToolRoot -ToolRoot $ToolRoot
    $metadataPath = Join-Path (Join-Path $root $Id) 'installation.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        return $null
    }

    $file = Get-Item -LiteralPath $metadataPath -ErrorAction Stop
    if ($file.Length -gt $script:MaxInstallationMetadataBytes) {
        throw "Integration '$Id' installation metadata exceeds the safety limit."
    }

    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Integration '$Id' has invalid installation metadata: $($_.Exception.Message)"
    }

    foreach ($propertyName in @('SchemaVersion', 'Id', 'Repository', 'Tag', 'Asset', 'ActualSHA256', 'InstallMode')) {
        if ($null -eq $metadata.PSObject.Properties[$propertyName] -or [string]::IsNullOrWhiteSpace([string]$metadata.$propertyName)) {
            throw "Integration '$Id' installation metadata is missing '$propertyName'."
        }
    }
    if ([string]$metadata.Id -ne $Id -or [string]$metadata.ActualSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Integration '$Id' installation metadata failed identity/hash validation."
    }

    return $metadata
}

function Find-WcdIntegrationArtifact {
    param(
        [Parameter(Mandatory = $true)] [string]$Root,
        [Parameter(Mandatory = $true)] [string]$NameRegex
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $null
    }

    $visited = 0
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse -ErrorAction Stop) {
        $visited++
        if ($visited -gt $script:MaxArtifactSearchFiles) {
            throw "Artifact search under '$Root' exceeded $script:MaxArtifactSearchFiles files."
        }
        if ($file.Name -match $NameRegex) {
            return $file.FullName
        }
    }

    return $null
}

function Resolve-WcdIntegrationExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Id,
        [string]$ToolRoot,
        [switch]$Required
    )

    $entry = Get-WcdIntegration -Id $Id
    if ($Id -eq 'smartmontools') {
        $command = Get-Command 'smartctl.exe' -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }

        foreach ($programRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if ([string]::IsNullOrWhiteSpace($programRoot)) { continue }
            $candidate = Join-Path $programRoot 'smartmontools\bin\smartctl.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    if ($null -ne $entry.PSObject.Properties['executableRegex'] -and
        -not [string]::IsNullOrWhiteSpace([string]$entry.executableRegex)) {
        $root = Get-WcdToolRoot -ToolRoot $ToolRoot
        $match = Find-WcdIntegrationArtifact -Root (Join-Path $root $Id) -NameRegex ([string]$entry.executableRegex)
        if ($match) { return $match }
    }

    if ($Required) {
        throw "Integration '$Id' is not installed or its executable could not be found."
    }
    return $null
}

function Resolve-WcdIntegrationLibrary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Id,
        [string]$ToolRoot,
        [switch]$Required
    )

    $entry = Get-WcdIntegration -Id $Id
    if ($null -eq $entry.PSObject.Properties['libraryRegex']) {
        if ($Required) { throw "Integration '$Id' does not define a library artifact." }
        return $null
    }

    $root = Get-WcdToolRoot -ToolRoot $ToolRoot
    $match = Find-WcdIntegrationArtifact -Root (Join-Path $root $Id) -NameRegex ([string]$entry.libraryRegex)
    if ($match) { return $match }

    if ($Required) {
        throw "Integration '$Id' is not installed or its library could not be found."
    }
    return $null
}

function Get-WcdIntegrationStatus {
    [CmdletBinding()]
    param([string]$ToolRoot)

    foreach ($entry in Get-WcdIntegrationCatalog) {
        $metadata = $null
        $executable = $null
        $errors = New-Object System.Collections.Generic.List[string]

        try { $metadata = Get-WcdIntegrationMetadata -Id $entry.id -ToolRoot $ToolRoot }
        catch { $errors.Add("metadata: $($_.Exception.Message)") }
        try { $executable = Resolve-WcdIntegrationExecutable -Id $entry.id -ToolRoot $ToolRoot }
        catch { $errors.Add("executable: $($_.Exception.Message)") }

        [pscustomobject][ordered]@{
            Id            = $entry.id
            Name          = $entry.name
            Repository    = $entry.repository
            License       = $entry.license
            Tier          = $entry.tier
            Risk          = $entry.risk
            CatalogStatus = $entry.status
            Installed     = [bool]($metadata -or $executable)
            Version       = if ($metadata) { $metadata.Tag } elseif ($entry.PSObject.Properties['packageVersion']) { $entry.packageVersion } else { $null }
            Executable    = $executable
            Error         = if ($errors.Count) { $errors.ToArray() -join '; ' } else { $null }
        }
    }
}

function Get-WcdVerifiedReleaseAsset {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)]$Release,
        [switch]$AllowUnverified
    )

    if ([string]$Release.tag_name -ne [string]$Entry.releaseTag) {
        throw "Integration '$($Entry.id)' expected release '$($Entry.releaseTag)' but GitHub returned '$($Release.tag_name)'."
    }

    $assets = @($Release.assets | Where-Object { $_.name -match [string]$Entry.assetRegex })
    if ($assets.Count -ne 1) {
        throw "Expected exactly one release asset for '$($Entry.id)' matching '$($Entry.assetRegex)', found $($assets.Count)."
    }

    $asset = $assets[0]
    $downloadUri = $null
    if (-not [uri]::TryCreate([string]$asset.browser_download_url, [UriKind]::Absolute, [ref]$downloadUri) -or
        $downloadUri.Scheme -ne 'https' -or $downloadUri.Host -ne 'github.com') {
        throw "Integration '$($Entry.id)' returned an invalid GitHub asset URL."
    }

    $assetSize = [int64]0
    if ($null -ne $asset.PSObject.Properties['size']) {
        [void][int64]::TryParse([string]$asset.size, [ref]$assetSize)
    }
    if ($assetSize -gt $script:MaxDownloadBytes) {
        throw "Integration '$($Entry.id)' asset is $assetSize bytes, above the $script:MaxDownloadBytes-byte safety limit."
    }

    $catalogDigest = if ($null -ne $Entry.PSObject.Properties['assetSHA256']) { ([string]$Entry.assetSHA256).ToLowerInvariant() } else { $null }
    $githubDigest = $null
    if ($null -ne $asset.PSObject.Properties['digest'] -and [string]$asset.digest -match '^sha256:([0-9a-fA-F]{64})$') {
        $githubDigest = $Matches[1].ToLowerInvariant()
    }
    if ($catalogDigest -and $githubDigest -and $catalogDigest -ne $githubDigest) {
        throw "Integration '$($Entry.id)' catalog SHA-256 disagrees with GitHub release metadata."
    }

    $expectedDigest = if ($catalogDigest) { $catalogDigest } else { $githubDigest }
    if (-not $expectedDigest -and -not $AllowUnverified) {
        throw "No SHA-256 is published for '$($asset.name)'. Re-run with -AllowUnverified only after independently verifying the upstream asset."
    }

    return [pscustomobject][ordered]@{
        Asset          = $asset
        ExpectedSHA256 = $expectedDigest
        DeclaredBytes  = $assetSize
    }
}

function Install-WcdIntegration {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$Id,
        [string]$ToolRoot,
        [switch]$AllowUnverified
    )

    $entry = Get-WcdIntegration -Id $Id
    if ([string]$entry.installMode -notin @('github-release-zip', 'github-release-file', 'manual-installer-download')) {
        throw "Integration '$Id' is catalogued as '$($entry.installMode)' and is intentionally not auto-downloaded."
    }

    $headers = @{ 'User-Agent' = 'Windows-Crash-Doctor'; 'Accept' = 'application/vnd.github+json' }
    $release = Invoke-RestMethod -Uri ([string]$entry.releaseApi) -Headers $headers -ErrorAction Stop
    $verifiedAsset = Get-WcdVerifiedReleaseAsset -Entry $entry -Release $release -AllowUnverified:$AllowUnverified
    $asset = $verifiedAsset.Asset

    if (-not $PSCmdlet.ShouldProcess("$($entry.repository) $($entry.releaseTag)", "Download and install $($asset.name)")) {
        return
    }

    $root = Get-WcdToolRoot -ToolRoot $ToolRoot
    New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop | Out-Null
    $destination = Join-Path $root $Id
    $operationId = [guid]::NewGuid().ToString('N')
    $stage = Join-Path $root ('.stage-{0}-{1}' -f $Id, $operationId)
    $backup = Join-Path $root ('.backup-{0}-{1}' -f $Id, $operationId)
    $payload = Join-Path $stage 'payload'
    New-Item -ItemType Directory -Path $payload -Force -ErrorAction Stop | Out-Null

    $swapStarted = $false
    try {
        $download = Join-Path $stage ([string]$asset.name)
        Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -Headers $headers -OutFile $download -UseBasicParsing -ErrorAction Stop
        $downloadFile = Get-Item -LiteralPath $download -ErrorAction Stop
        if ($downloadFile.Length -gt $script:MaxDownloadBytes) {
            throw "Downloaded asset exceeds the $script:MaxDownloadBytes-byte safety limit."
        }
        if ($verifiedAsset.DeclaredBytes -gt 0 -and $downloadFile.Length -ne $verifiedAsset.DeclaredBytes) {
            throw "Downloaded asset size $($downloadFile.Length) does not match GitHub metadata $($verifiedAsset.DeclaredBytes)."
        }

        $actualHash = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($verifiedAsset.ExpectedSHA256 -and $actualHash -ne $verifiedAsset.ExpectedSHA256) {
            throw "SHA-256 mismatch for '$($asset.name)'."
        }

        if ([string]$entry.installMode -eq 'github-release-zip') {
            Expand-Archive -LiteralPath $download -DestinationPath $payload -Force -ErrorAction Stop
        }
        else {
            Copy-Item -LiteralPath $download -Destination (Join-Path $payload $asset.name) -Force -ErrorAction Stop
        }

        if ([string]$entry.installMode -eq 'github-release-zip') {
            if ($entry.PSObject.Properties['executableRegex']) {
                $artifact = Find-WcdIntegrationArtifact -Root $payload -NameRegex ([string]$entry.executableRegex)
                if (-not $artifact -and $entry.PSObject.Properties['libraryRegex']) {
                    $artifact = Find-WcdIntegrationArtifact -Root $payload -NameRegex ([string]$entry.libraryRegex)
                }
                if (-not $artifact) {
                    throw "Downloaded '$Id' package does not contain the expected executable/library artifact."
                }
            }
        }

        [pscustomobject][ordered]@{
            SchemaVersion    = '1.0'
            Id               = $Id
            Repository       = $entry.repository
            License          = $entry.license
            Tag              = $entry.releaseTag
            Asset            = $asset.name
            SourceUrl        = $asset.browser_download_url
            ExpectedSHA256   = $verifiedAsset.ExpectedSHA256
            ActualSHA256     = $actualHash
            VerifiedByDigest = [bool]$verifiedAsset.ExpectedSHA256
            InstalledAt      = (Get-Date).ToString('o')
            InstallMode      = $entry.installMode
        } | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $payload 'installation.json') -Encoding utf8 -ErrorAction Stop

        # Keep the previous known-good provider until the replacement is fully downloaded, verified and staged.
        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination $backup -ErrorAction Stop
        }
        $swapStarted = $true
        Move-Item -LiteralPath $payload -Destination $destination -ErrorAction Stop

        if (Test-Path -LiteralPath $backup) {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
        }

        return Get-WcdIntegrationStatus -ToolRoot $root | Where-Object Id -eq $Id
    }
    catch {
        if ($swapStarted -and -not (Test-Path -LiteralPath $destination) -and (Test-Path -LiteralPath $backup)) {
            Move-Item -LiteralPath $backup -Destination $destination -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $stage) {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backup) {
            if (-not (Test-Path -LiteralPath $destination)) {
                Move-Item -LiteralPath $backup -Destination $destination -ErrorAction SilentlyContinue
            }
        }
    }
}

function ConvertTo-WcdProcessArgument {
    param([Parameter(Mandatory = $true)] [AllowEmptyString()] [string]$Value)

    if ($Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-WcdExternalProcess {
    param(
        [Parameter(Mandatory = $true)] [string]$Executable,
        [string[]]$Arguments = @(),
        [ValidateRange(1, 3600)] [int]$TimeoutSeconds = 120,
        [switch]$AllowNonZeroExit
    )

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = (@($Arguments | ForEach-Object { ConvertTo-WcdProcessArgument ([string]$_) }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Failed to start external process '$([IO.Path]::GetFileName($Executable))'."
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            throw "External process '$([IO.Path]::GetFileName($Executable))' exceeded the $TimeoutSeconds-second timeout."
        }
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        if ($process.ExitCode -ne 0 -and -not $AllowNonZeroExit) {
            throw "External process '$([IO.Path]::GetFileName($Executable))' failed with exit code $($process.ExitCode)."
        }

        return [pscustomobject][ordered]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-WcdHardwareSensors {
    [CmdletBinding()]
    param([string]$ToolRoot)

    $library = Resolve-WcdIntegrationLibrary -Id 'librehardwaremonitor' -ToolRoot $ToolRoot -Required
    if (-not [Type]::GetType('LibreHardwareMonitor.Hardware.Computer, LibreHardwareMonitorLib', $false)) {
        Add-Type -Path $library -ErrorAction Stop
    }

    $computer = New-Object -TypeName 'LibreHardwareMonitor.Hardware.Computer'
    foreach ($property in @('IsCpuEnabled', 'IsGpuEnabled', 'IsMemoryEnabled', 'IsMotherboardEnabled', 'IsStorageEnabled')) {
        if ($computer.PSObject.Properties.Name -contains $property) { $computer.$property = $true }
    }

    $results = New-Object System.Collections.Generic.List[object]
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    try {
        $computer.Open()
        foreach ($hardware in @($computer.Hardware)) { $queue.Enqueue($hardware) }
        $nodes = 0
        while ($queue.Count -gt 0) {
            $nodes++
            if ($nodes -gt $script:MaxHardwareNodes) {
                throw "Hardware tree exceeds the $script:MaxHardwareNodes-node safety limit."
            }

            $hardware = $queue.Dequeue()
            $hardware.Update()
            foreach ($sensor in @($hardware.Sensors)) {
                $results.Add([pscustomobject][ordered]@{
                    Timestamp    = (Get-Date).ToString('o')
                    HardwareType = [string]$hardware.HardwareType
                    HardwareName = [string]$hardware.Name
                    SensorType   = [string]$sensor.SensorType
                    SensorName   = [string]$sensor.Name
                    Value        = $sensor.Value
                    Min          = $sensor.Min
                    Max          = $sensor.Max
                    Identifier   = [string]$sensor.Identifier
                })
            }
            foreach ($subHardware in @($hardware.SubHardware)) { $queue.Enqueue($subHardware) }
        }
    }
    finally {
        $computer.Close()
    }

    return $results.ToArray()
}

function Start-WcdSensorWatch {
    [CmdletBinding()]
    param(
        [ValidateRange(0.1, 1440)] [double]$DurationMinutes = 30,
        [ValidateRange(1, 300)] [int]$IntervalSeconds = 2,
        [string]$OutputPath,
        [string]$ToolRoot
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path (Get-Location) ('wcd-sensors-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }

    $deadline = (Get-Date).AddMinutes($DurationMinutes)
    $sample = 0
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $OutputPath -PathType Leaf) -and (Get-Item -LiteralPath $OutputPath).Length -gt $script:MaxSensorOutputBytes) {
            throw "Sensor output exceeded the $script:MaxSensorOutputBytes-byte safety limit."
        }

        $sample++
        $capturedAt = (Get-Date).ToString('o')
        try {
            foreach ($sensor in @(Get-WcdHardwareSensors -ToolRoot $ToolRoot)) {
                [pscustomobject][ordered]@{
                    Sample = $sample; CapturedAt = $capturedAt; HardwareType = $sensor.HardwareType; HardwareName = $sensor.HardwareName
                    SensorType = $sensor.SensorType; SensorName = $sensor.SensorName; Value = $sensor.Value; Min = $sensor.Min; Max = $sensor.Max; Identifier = $sensor.Identifier
                } | ConvertTo-Json -Compress -Depth 4 | Add-Content -LiteralPath $OutputPath -Encoding utf8 -ErrorAction Stop
            }
        }
        catch {
            [pscustomobject][ordered]@{ Sample = $sample; CapturedAt = $capturedAt; Error = $_.Exception.Message } |
                ConvertTo-Json -Compress | Add-Content -LiteralPath $OutputPath -Encoding utf8 -ErrorAction Stop
        }
        Start-Sleep -Seconds $IntervalSeconds
    }

    return (Resolve-Path -LiteralPath $OutputPath).Path
}

function Convert-WcdEvtx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$EvtxPath,
        [string]$OutputPath,
        [ValidateSet('json', 'jsonl', 'xml')] [string]$Format = 'jsonl',
        [ValidateRange(1, 3600)] [int]$TimeoutSeconds = 300,
        [string]$ToolRoot
    )

    if (-not (Test-Path -LiteralPath $EvtxPath -PathType Leaf)) { throw "EVTX file not found: $EvtxPath" }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = "$EvtxPath.$Format" }

    $exe = Resolve-WcdIntegrationExecutable -Id 'evtx' -ToolRoot $ToolRoot -Required
    [void](Invoke-WcdExternalProcess -Executable $exe -Arguments @('-o', $Format, '-t', '1', '-f', $OutputPath, $EvtxPath) -TimeoutSeconds $TimeoutSeconds)
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw 'evtx_dump completed without creating the requested output file.' }
    return (Resolve-Path -LiteralPath $OutputPath).Path
}

function Invoke-WcdHayabusaTimeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$EvidencePath,
        [string]$OutputPath,
        [ValidateRange(1, 3600)] [int]$TimeoutSeconds = 900,
        [string]$ToolRoot
    )

    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Container)) { throw "Evidence directory not found: $EvidencePath" }
    $evtxCount = 0
    foreach ($file in Get-ChildItem -LiteralPath $EvidencePath -Filter '*.evtx' -File -Recurse -ErrorAction Stop) {
        $evtxCount++
        if ($evtxCount -gt $script:MaxArtifactSearchFiles) { throw "EVTX search exceeded $script:MaxArtifactSearchFiles files." }
    }
    if ($evtxCount -eq 0) { throw "No EVTX files were found under: $EvidencePath" }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $EvidencePath 'hayabusa-timeline.csv' }

    $exe = Resolve-WcdIntegrationExecutable -Id 'hayabusa' -ToolRoot $ToolRoot -Required
    $oldLocation = Get-Location
    try {
        Set-Location -LiteralPath (Split-Path -Parent $exe)
        [void](Invoke-WcdExternalProcess -Executable $exe -Arguments @('csv-timeline', '-d', $EvidencePath, '-o', $OutputPath, '-C', '-q', '-O') -TimeoutSeconds $TimeoutSeconds)
    }
    finally { Set-Location -LiteralPath $oldLocation }

    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { throw 'Hayabusa completed without creating the requested timeline.' }
    return (Resolve-Path -LiteralPath $OutputPath).Path
}

function Invoke-WcdOsqueryInventory {
    [CmdletBinding()]
    param(
        [string]$OutputPath,
        [ValidateRange(1, 600)] [int]$QueryTimeoutSeconds = 60,
        [string]$ToolRoot
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path (Get-Location) ('osquery-inventory-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    $exe = Resolve-WcdIntegrationExecutable -Id 'osquery' -ToolRoot $ToolRoot -Required
    $queries = [ordered]@{
        system_info = 'select * from system_info;'; os_version = 'select * from os_version;'; drivers = 'select * from drivers;'
        services = 'select * from services;'; programs = 'select * from programs;'; processes = 'select * from processes;'
    }

    $result = [ordered]@{}
    foreach ($name in $queries.Keys) {
        try {
            $processResult = Invoke-WcdExternalProcess -Executable $exe -Arguments @('--json', $queries[$name]) -TimeoutSeconds $QueryTimeoutSeconds
            $raw = $processResult.StdOut.Trim()
            $result[$name] = if ([string]::IsNullOrWhiteSpace($raw)) { @() } else { @($raw | ConvertFrom-Json -ErrorAction Stop) }
        }
        catch {
            $result[$name] = [pscustomobject][ordered]@{ Error = $_.Exception.Message }
        }
    }

    [pscustomobject]$result | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $OutputPath -Encoding utf8 -Width 1000 -ErrorAction Stop
    return (Resolve-Path -LiteralPath $OutputPath).Path
}

function Invoke-WcdSmartctlInventory {
    [CmdletBinding()]
    param(
        [string]$OutputPath,
        [ValidateRange(1, 600)] [int]$CommandTimeoutSeconds = 120,
        [string]$ToolRoot
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path (Get-Location) ('smartctl-inventory-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    $exe = Resolve-WcdIntegrationExecutable -Id 'smartmontools' -ToolRoot $ToolRoot -Required
    $scanResult = Invoke-WcdExternalProcess -Executable $exe -Arguments @('--scan-open') -TimeoutSeconds $CommandTimeoutSeconds
    $scanLines = @($scanResult.StdOut -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($scanLines.Count -gt 256) { throw 'smartctl returned more than 256 drive scan entries.' }

    $drives = New-Object System.Collections.Generic.List[object]
    foreach ($line in $scanLines) {
        $spec = (($line -split '#', 2)[0]).Trim()
        if ([string]::IsNullOrWhiteSpace($spec)) { continue }
        $parts = @($spec -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts.Count -eq 0) { continue }

        $device = $parts[0]
        $extra = if ($parts.Count -gt 1) { @($parts[1..($parts.Count - 1)]) } else { @() }
        try {
            # smartctl uses non-zero exit bits for device-health conditions, so capture the code instead of treating every non-zero value as a process failure.
            $deviceResult = Invoke-WcdExternalProcess -Executable $exe -Arguments (@('-x', '-j') + $extra + @($device)) -TimeoutSeconds $CommandTimeoutSeconds -AllowNonZeroExit
            $data = if ([string]::IsNullOrWhiteSpace($deviceResult.StdOut)) { $null } else { $deviceResult.StdOut | ConvertFrom-Json -ErrorAction Stop }
            $drives.Add([pscustomobject][ordered]@{ Device = $device; Scan = $line; ExitCode = $deviceResult.ExitCode; Data = $data })
        }
        catch {
            $drives.Add([pscustomobject][ordered]@{ Device = $device; Scan = $line; Error = $_.Exception.Message })
        }
    }

    [pscustomobject][ordered]@{
        SchemaVersion = '1.0'; CollectedAt = (Get-Date).ToString('o'); Smartctl = $exe; Drives = $drives.ToArray()
    } | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $OutputPath -Encoding utf8 -Width 2000 -ErrorAction Stop
    return (Resolve-Path -LiteralPath $OutputPath).Path
}

Export-ModuleMember -Function @(
    'Get-WcdIntegrationCatalog', 'Get-WcdIntegration', 'Get-WcdIntegrationStatus', 'Install-WcdIntegration',
    'Resolve-WcdIntegrationExecutable', 'Resolve-WcdIntegrationLibrary', 'Get-WcdHardwareSensors', 'Start-WcdSensorWatch',
    'Convert-WcdEvtx', 'Invoke-WcdHayabusaTimeline', 'Invoke-WcdOsqueryInventory', 'Invoke-WcdSmartctlInventory'
)
