[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'DumpParser.psm1') -Force

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

if (-not ('CrashDoctorDbgHelp' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CrashDoctorDbgHelp
{
    [DllImport("Dbghelp.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool MiniDumpWriteDump(
        IntPtr hProcess,
        uint processId,
        IntPtr hFile,
        uint dumpType,
        IntPtr exceptionParam,
        IntPtr userStreamParam,
        IntPtr callbackParam);
}
'@
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('WcdRealDump-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$dumpPath = Join-Path $temp 'powershell-real-minidump.dmp'

try {
    $process = [Diagnostics.Process]::GetCurrentProcess()
    $file = [IO.File]::Open(
        $dumpPath,
        [IO.FileMode]::Create,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::Read
    )
    try {
        # MiniDumpNormal = 0. This is intentionally a safe user-mode dump of the test process,
        # not a deliberate crash and not a kernel crash dump.
        $ok = [CrashDoctorDbgHelp]::MiniDumpWriteDump(
            $process.Handle,
            [uint32]$process.Id,
            $file.SafeFileHandle.DangerousGetHandle(),
            0,
            [IntPtr]::Zero,
            [IntPtr]::Zero,
            [IntPtr]::Zero
        )
        if (-not $ok) {
            $win32 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "MiniDumpWriteDump failed with Win32 error $win32."
        }
        $file.Flush()
    }
    finally {
        $file.Dispose()
    }

    Assert-True ((Get-Item -LiteralPath $dumpPath).Length -gt 32) 'DbgHelp minidump should be non-empty'

    $report = Get-CrashDoctorDumpInfo -Path $dumpPath
    Assert-True ($report.Format -eq 'MiniDump') 'real DbgHelp file should be detected as a minidump'
    Assert-True ($report.Header.NumberOfStreams -gt 0) 'real minidump should contain streams'
    Assert-True (-not [string]::IsNullOrWhiteSpace($report.Architecture)) 'real minidump should expose processor architecture'
    Assert-True ($report.ModuleCount -gt 0) 'real minidump should expose at least one loaded module'
    Assert-True ($report.ThreadCount -gt 0) 'real minidump should expose at least one thread'
    Assert-True (@($report.Streams | Where-Object Name -eq 'SystemInfoStream').Count -eq 1) 'real minidump should contain SystemInfoStream'
    Assert-True (@($report.Streams | Where-Object Name -eq 'ModuleListStream').Count -eq 1) 'real minidump should contain ModuleListStream'
    Assert-True (@($report.Streams | Where-Object Name -eq 'ThreadListStream').Count -eq 1) 'real minidump should contain ThreadListStream'

    Write-Host "Real DbgHelp minidump parsed: $($report.ModuleCount) modules, $($report.ThreadCount) threads, $($report.Header.NumberOfStreams) streams."
    Write-Host 'Windows Crash Doctor real minidump smoke test: PASS'
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
