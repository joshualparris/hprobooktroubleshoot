[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'WindowsCrashDoctor\App'),

    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$CommitSha,

    [switch]$InstallOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Repository = 'joshualparris/hprobooktroubleshoot'
$script:MaxArchiveBytes = 67108864

function Assert-WcdCommandLineSafePath {
    param([Parameter(Mandatory = $true)] [string]$Path)
    if ($Path.Contains('"')) {
        throw "Path cannot contain a double-quote character: $Path"
    }
}

function Resolve-WcdInstallCommit {
    param([AllowNull()] [string]$RequestedSha)

    if (-not [string]::IsNullOrWhiteSpace($RequestedSha)) {
        if ($RequestedSha -notmatch '^[0-9a-fA-F]{40}$') {
            throw 'CommitSha must be a full 40-character hexadecimal Git commit SHA.'
        }
        return $RequestedSha.ToLowerInvariant()
    }

    $headers = @{ 'User-Agent' = 'Windows-Crash-Doctor'; 'Accept' = 'application/vnd.github+json' }
    $commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$script:Repository/commits/main" -Headers $headers -TimeoutSec 30 -ErrorAction Stop
    $resolved = [string]$commit.sha
    if ($resolved -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'GitHub returned an invalid main commit SHA.'
    }
    return $resolved.ToLowerInvariant()
}

function Get-WcdExtractedRepositoryRoot {
    param([Parameter(Mandatory = $true)] [string]$ExtractRoot)

    $directories = @(Get-ChildItem -LiteralPath $ExtractRoot -Directory -Force -ErrorAction Stop)
    if ($directories.Count -ne 1) {
        throw "Expected exactly one repository root in the downloaded archive; found $($directories.Count)."
    }
    return $directories[0].FullName
}

function Assert-WcdStagedApplication {
    param([Parameter(Mandatory = $true)] [string]$StagingRoot)

    $requiredFiles = @(
        'windows-crash-doctor\Run-WindowsCrashDoctor.ps1',
        'windows-crash-doctor\Invoke-CrashDoctor.ps1',
        'windows-crash-doctor\CrashDoctor.psm1',
        'windows-crash-doctor\FindingModel.psm1',
        'windows-crash-doctor\Reporting.psm1',
        'windows-crash-doctor\TelemetryAnalysis.psm1',
        'windows-crash-doctor\tests\self-test.ps1',
        'windows-crash-doctor\tests\integration-self-test.ps1',
        'windows-crash-doctor\tests\telemetry-self-test.ps1',
        'windows-crash-doctor\tests\dump-parser-test.ps1',
        'scripts\collect-diagnostics.ps1'
    )
    foreach ($relativePath in $requiredFiles) {
        $path = Join-Path $StagingRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Staged installation is incomplete; missing: $relativePath"
        }
    }
}

function Invoke-WcdStagedTest {
    param(
        [Parameter(Mandatory = $true)] [string]$ScriptPath,
        [string[]]$Arguments = @(),
        [ValidateRange(1, 900)] [int]$TimeoutSeconds = 300
    )

    Assert-WcdCommandLineSafePath -Path $ScriptPath
    $argumentText = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $ScriptPath)
    ) + $Arguments

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList ($argumentText -join ' ') -PassThru -NoNewWindow -ErrorAction Stop
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        throw "Installation self-test '$([IO.Path]::GetFileName($ScriptPath))' exceeded the $TimeoutSeconds-second timeout."
    }
    if ($process.ExitCode -ne 0) {
        throw "Installation self-test '$([IO.Path]::GetFileName($ScriptPath))' failed with exit code $($process.ExitCode)."
    }
}

function Test-WcdStagedApplication {
    param([Parameter(Mandatory = $true)] [string]$StagingRoot)

    Assert-WcdStagedApplication -StagingRoot $StagingRoot
    $testRoot = Join-Path $StagingRoot 'windows-crash-doctor\tests'
    Invoke-WcdStagedTest -ScriptPath (Join-Path $testRoot 'self-test.ps1') -Arguments @('-RepositoryMode')
    Invoke-WcdStagedTest -ScriptPath (Join-Path $testRoot 'integration-self-test.ps1')
    Invoke-WcdStagedTest -ScriptPath (Join-Path $testRoot 'telemetry-self-test.ps1')
    Invoke-WcdStagedTest -ScriptPath (Join-Path $testRoot 'dump-parser-test.ps1')
    Invoke-WcdStagedTest -ScriptPath (Join-Path $testRoot 'dump-parser-real-smoke.ps1')
}

function Install-WcdStagedApplication {
    param(
        [Parameter(Mandatory = $true)] [string]$StagingRoot,
        [Parameter(Mandatory = $true)] [string]$InstallRoot
    )

    $installParent = Split-Path -Parent $InstallRoot
    $backup = Join-Path $installParent ('App.backup-' + [guid]::NewGuid().ToString('N'))
    $oldMoved = $false
    try {
        # The existing known-good install is retained until the new staging tree has already passed its tests.
        if (Test-Path -LiteralPath $InstallRoot) {
            Move-Item -LiteralPath $InstallRoot -Destination $backup -ErrorAction Stop
            $oldMoved = $true
        }
        Move-Item -LiteralPath $StagingRoot -Destination $InstallRoot -ErrorAction Stop
        if ($oldMoved) {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
        }
    }
    catch {
        if (-not (Test-Path -LiteralPath $InstallRoot) -and $oldMoved -and (Test-Path -LiteralPath $backup)) {
            Move-Item -LiteralPath $backup -Destination $InstallRoot -ErrorAction SilentlyContinue
        }
        throw
    }
}

function New-WcdLaunchers {
    param([Parameter(Mandatory = $true)] [string]$InstallRoot)

    $runner = Join-Path $InstallRoot 'windows-crash-doctor\Run-WindowsCrashDoctor.ps1'
    $desktop = [Environment]::GetFolderPath('Desktop')
    $cmdPath = Join-Path $desktop 'Windows Crash Doctor.cmd'
    $cmd = @"
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$runner"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" echo Windows Crash Doctor exited with code %EXITCODE%.
echo Press any key to close this window.
pause >nul
exit /b %EXITCODE%
"@
    Set-Content -LiteralPath $cmdPath -Value $cmd -Encoding ASCII -ErrorAction Stop

    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $shortcutPath = Join-Path $startMenu 'Windows Crash Doctor.lnk'
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runner)
        $shortcut.WorkingDirectory = $InstallRoot
        $shortcut.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
        $shortcut.Description = 'Collect and analyse Windows crash/hang diagnostics'
        $shortcut.Save()
    }
    catch {
        Write-Warning "Start Menu shortcut could not be created: $($_.Exception.Message)"
    }

    return $cmdPath
}

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    throw 'InstallRoot cannot be empty.'
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$installParent = Split-Path -Parent $InstallRoot
New-Item -ItemType Directory -Path $installParent -Force -ErrorAction Stop | Out-Null

$resolvedCommit = Resolve-WcdInstallCommit -RequestedSha $CommitSha
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('WindowsCrashDoctorInstall-' + [guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tempRoot ('WindowsCrashDoctor-{0}.zip' -f $resolvedCommit)
$extractRoot = Join-Path $tempRoot 'extract'
$staging = Join-Path $installParent ('App.staging-' + [guid]::NewGuid().ToString('N'))
$archiveUrl = "https://github.com/$script:Repository/archive/$resolvedCommit.zip"

Write-Host ''
Write-Host 'Windows Crash Doctor installer' -ForegroundColor Cyan
Write-Host '==============================' -ForegroundColor Cyan
Write-Host "Commit: $resolvedCommit"
Write-Host "Install location: $InstallRoot"
Write-Host ''

New-Item -ItemType Directory -Path $tempRoot, $extractRoot, $staging -Force -ErrorAction Stop | Out-Null

try {
    Write-Host '1/6 Downloading the pinned source archive...'
    Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
    $archiveFile = Get-Item -LiteralPath $zipPath -ErrorAction Stop
    if ($archiveFile.Length -gt $script:MaxArchiveBytes) {
        throw "Downloaded source archive is $($archiveFile.Length) bytes, above the $script:MaxArchiveBytes-byte safety limit."
    }
    $archiveSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

    Write-Host '2/6 Extracting and validating the repository shape...'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force -ErrorAction Stop
    $source = Get-WcdExtractedRepositoryRoot -ExtractRoot $extractRoot
    foreach ($item in Get-ChildItem -LiteralPath $source -Force -ErrorAction Stop) {
        Copy-Item -LiteralPath $item.FullName -Destination $staging -Recurse -Force -ErrorAction Stop
    }
    Assert-WcdStagedApplication -StagingRoot $staging

    Write-Host '3/6 Running staged regression tests before replacing the current install...'
    Test-WcdStagedApplication -StagingRoot $staging

    [pscustomobject][ordered]@{
        SchemaVersion  = '1.0'
        Repository     = $script:Repository
        CommitSha      = $resolvedCommit
        ArchiveSHA256  = $archiveSha256
        InstalledAt    = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 4 | Out-File -LiteralPath (Join-Path $staging 'installation.json') -Encoding UTF8 -ErrorAction Stop

    Write-Host '4/6 Atomically installing the tested build...'
    Install-WcdStagedApplication -StagingRoot $staging -InstallRoot $InstallRoot

    Write-Host '5/6 Creating user launchers...'
    $cmdPath = New-WcdLaunchers -InstallRoot $InstallRoot

    Write-Host '6/6 Verifying installed identity...'
    $installedMetadata = Get-Content -LiteralPath (Join-Path $InstallRoot 'installation.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$installedMetadata.CommitSha -ne $resolvedCommit) {
        throw 'Installed metadata does not match the commit that passed staging tests.'
    }

    Write-Host ''
    Write-Host 'INSTALL PASS' -ForegroundColor Green
    Write-Host "Desktop launcher: $cmdPath" -ForegroundColor Green
    Write-Host "Installed app: $InstallRoot" -ForegroundColor Green
    Write-Host "Installed commit: $resolvedCommit" -ForegroundColor Green

    if (-not $InstallOnly) {
        Write-Host ''
        Write-Host 'Starting the first real diagnostic run...' -ForegroundColor Cyan
        & (Join-Path $InstallRoot 'windows-crash-doctor\Run-WindowsCrashDoctor.ps1')
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}
