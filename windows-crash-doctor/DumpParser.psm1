Set-StrictMode -Version Latest

$script:MiniDumpSignature = 0x504d444d # 'MDMP'
$script:KernelDumpSignature = 0x45474150 # 'PAGE'
$script:KernelDumpValid32 = 0x504d5544 # 'DUMP'
$script:KernelDumpValid64 = 0x34365544 # 'DU64'

$script:MiniDumpStreamNames = @{
    0  = 'UnusedStream'
    1  = 'ReservedStream0'
    2  = 'ReservedStream1'
    3  = 'ThreadListStream'
    4  = 'ModuleListStream'
    5  = 'MemoryListStream'
    6  = 'ExceptionStream'
    7  = 'SystemInfoStream'
    8  = 'ThreadExListStream'
    9  = 'Memory64ListStream'
    10 = 'CommentStreamA'
    11 = 'CommentStreamW'
    12 = 'HandleDataStream'
    13 = 'FunctionTableStream'
    14 = 'UnloadedModuleListStream'
    15 = 'MiscInfoStream'
    16 = 'MemoryInfoListStream'
    17 = 'ThreadInfoListStream'
    18 = 'HandleOperationListStream'
    19 = 'TokenStream'
    20 = 'JavaScriptDataStream'
    21 = 'SystemMemoryInfoStream'
    22 = 'ProcessVmCountersStream'
    23 = 'IptTraceStream'
    24 = 'ThreadNamesStream'
}

function Read-CrashDoctorBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [System.IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)] [Int64]$Offset,
        [Parameter(Mandatory = $true)] [int]$Count
    )

    if ($Offset -lt 0 -or $Count -lt 0 -or ($Offset + $Count) -gt $Stream.Length) {
        throw "Requested dump range is outside the file: offset=$Offset count=$Count length=$($Stream.Length)"
    }

    $buffer = New-Object byte[] $Count
    $null = $Stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
    $read = 0
    while ($read -lt $Count) {
        $n = $Stream.Read($buffer, $read, $Count - $read)
        if ($n -le 0) { throw "Unexpected end of dump file at offset $($Offset + $read)." }
        $read += $n
    }
    return $buffer
}

function Get-CrashDoctorUInt16 {
    param([byte[]]$Bytes, [int]$Offset)
    if ($Offset -lt 0 -or ($Offset + 2) -gt $Bytes.Length) { throw 'Truncated dump structure while reading UInt16.' }
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Get-CrashDoctorUInt32 {
    param([byte[]]$Bytes, [int]$Offset)
    if ($Offset -lt 0 -or ($Offset + 4) -gt $Bytes.Length) { throw 'Truncated dump structure while reading UInt32.' }
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Get-CrashDoctorUInt64 {
    param([byte[]]$Bytes, [int]$Offset)
    if ($Offset -lt 0 -or ($Offset + 8) -gt $Bytes.Length) { throw 'Truncated dump structure while reading UInt64.' }
    return [BitConverter]::ToUInt64($Bytes, $Offset)
}

function Get-CrashDoctorInt64 {
    param([byte[]]$Bytes, [int]$Offset)
    if ($Offset -lt 0 -or ($Offset + 8) -gt $Bytes.Length) { throw 'Truncated dump structure while reading Int64.' }
    return [BitConverter]::ToInt64($Bytes, $Offset)
}

function Get-CrashDoctorMachineName {
    param([uint32]$MachineType)
    switch ($MachineType) {
        0x014c { 'x86' }
        0x0200 { 'IA64' }
        0x8664 { 'x64' }
        0x01c0 { 'ARM' }
        0xaa64 { 'ARM64' }
        default { ('0x{0:X4}' -f $MachineType) }
    }
}

function Get-CrashDoctorProcessorArchitectureName {
    param([uint16]$Architecture)
    switch ($Architecture) {
        0 { 'x86' }
        5 { 'ARM' }
        6 { 'IA64' }
        9 { 'x64' }
        12 { 'ARM64' }
        0xffff { 'Unknown' }
        default { $Architecture.ToString() }
    }
}

function Read-CrashDoctorMiniDumpString {
    param(
        [System.IO.FileStream]$Stream,
        [uint32]$Rva,
        [int]$MaximumBytes = 65536
    )

    if ($Rva -eq 0) { return $null }
    $lengthBytes = Read-CrashDoctorBytes -Stream $Stream -Offset $Rva -Count 4
    $byteLength = [int](Get-CrashDoctorUInt32 -Bytes $lengthBytes -Offset 0)
    if ($byteLength -gt $MaximumBytes -or ($byteLength % 2) -ne 0) {
        throw "Invalid MINIDUMP_STRING length $byteLength at RVA $Rva."
    }
    if ($byteLength -eq 0) { return '' }
    $bytes = Read-CrashDoctorBytes -Stream $Stream -Offset ($Rva + 4) -Count $byteLength
    return [Text.Encoding]::Unicode.GetString($bytes)
}

function Get-CrashDoctorMiniDumpStreamName {
    param([uint32]$StreamType)
    if ($script:MiniDumpStreamNames.ContainsKey([int]$StreamType)) {
        return $script:MiniDumpStreamNames[[int]$StreamType]
    }
    return "StreamType$StreamType"
}

function Read-CrashDoctorMiniDumpSystemInfo {
    param([System.IO.FileStream]$Stream, $Directory)
    if ($Directory.DataSize -lt 24) { return $null }
    $bytes = Read-CrashDoctorBytes -Stream $Stream -Offset $Directory.Rva -Count ([Math]::Min([int]$Directory.DataSize, 64))
    $arch = Get-CrashDoctorUInt16 -Bytes $bytes -Offset 0
    $csdRva = if ($bytes.Length -ge 28) { Get-CrashDoctorUInt32 -Bytes $bytes -Offset 24 } else { 0 }
    $csd = $null
    if ($csdRva -ne 0) {
        try { $csd = Read-CrashDoctorMiniDumpString -Stream $Stream -Rva $csdRva } catch { $csd = $null }
    }

    return [pscustomobject][ordered]@{
        ProcessorArchitecture = Get-CrashDoctorProcessorArchitectureName -Architecture $arch
        ProcessorArchitectureValue = $arch
        ProcessorLevel = Get-CrashDoctorUInt16 -Bytes $bytes -Offset 2
        ProcessorRevision = Get-CrashDoctorUInt16 -Bytes $bytes -Offset 4
        NumberOfProcessors = [int]$bytes[6]
        ProductType = [int]$bytes[7]
        MajorVersion = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 8
        MinorVersion = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 12
        BuildNumber = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 16
        PlatformId = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 20
        ServicePack = $csd
    }
}

function Read-CrashDoctorMiniDumpException {
    param([System.IO.FileStream]$Stream, $Directory)
    if ($Directory.DataSize -lt 40) { return $null }
    $bytes = Read-CrashDoctorBytes -Stream $Stream -Offset $Directory.Rva -Count ([Math]::Min([int]$Directory.DataSize, 168))
    $parameterCount = [Math]::Min([int](Get-CrashDoctorUInt32 -Bytes $bytes -Offset 32), 15)
    $parameters = @()
    for ($i = 0; $i -lt $parameterCount; $i++) {
        $offset = 40 + ($i * 8)
        if (($offset + 8) -le $bytes.Length) {
            $parameters += Get-CrashDoctorUInt64 -Bytes $bytes -Offset $offset
        }
    }

    return [pscustomobject][ordered]@{
        ThreadId = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 0
        ExceptionCode = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 8
        ExceptionFlags = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 12
        ExceptionAddress = Get-CrashDoctorUInt64 -Bytes $bytes -Offset 24
        NumberParameters = $parameterCount
        Parameters = $parameters
    }
}

function Read-CrashDoctorMiniDumpModules {
    param([System.IO.FileStream]$Stream, $Directory)
    if ($Directory.DataSize -lt 4) { return @() }
    $countBytes = Read-CrashDoctorBytes -Stream $Stream -Offset $Directory.Rva -Count 4
    $count = [int](Get-CrashDoctorUInt32 -Bytes $countBytes -Offset 0)
    if ($count -gt 4096) { throw "Unreasonable MINIDUMP_MODULE count: $count" }
    $entrySize = 108
    $available = [Math]::Floor(([int64]$Directory.DataSize - 4) / $entrySize)
    if ($count -gt $available) { throw "Truncated MINIDUMP_MODULE_LIST: expected $count entries, only $available fit." }

    $modules = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $count; $i++) {
        $offset = [int64]$Directory.Rva + 4 + ($i * $entrySize)
        $bytes = Read-CrashDoctorBytes -Stream $Stream -Offset $offset -Count $entrySize
        $nameRva = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 20
        $name = $null
        if ($nameRva -ne 0) {
            try { $name = Read-CrashDoctorMiniDumpString -Stream $Stream -Rva $nameRva } catch { $name = $null }
        }
        $modules.Add([pscustomobject][ordered]@{
            BaseOfImage = Get-CrashDoctorUInt64 -Bytes $bytes -Offset 0
            SizeOfImage = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 8
            Checksum = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 12
            TimeDateStamp = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 16
            Name = $name
        })
    }
    return $modules.ToArray()
}

function Read-CrashDoctorMiniDumpCountStream {
    param([System.IO.FileStream]$Stream, $Directory)
    if ($Directory.DataSize -lt 4) { return $null }
    $bytes = Read-CrashDoctorBytes -Stream $Stream -Offset $Directory.Rva -Count 4
    return [int](Get-CrashDoctorUInt32 -Bytes $bytes -Offset 0)
}

function Read-CrashDoctorMiniDumpMemory64Summary {
    param([System.IO.FileStream]$Stream, $Directory)
    if ($Directory.DataSize -lt 16) { return $null }
    $header = Read-CrashDoctorBytes -Stream $Stream -Offset $Directory.Rva -Count 16
    $count = Get-CrashDoctorUInt64 -Bytes $header -Offset 0
    if ($count -gt 10000000) { throw "Unreasonable MINIDUMP_MEMORY64_LIST range count: $count" }
    $available = [Math]::Floor(([int64]$Directory.DataSize - 16) / 16)
    if ($count -gt $available) { throw "Truncated MINIDUMP_MEMORY64_LIST: expected $count ranges, only $available fit." }
    $total = [uint64]0
    for ($i = 0; $i -lt [int]$count; $i++) {
        $entry = Read-CrashDoctorBytes -Stream $Stream -Offset ([int64]$Directory.Rva + 16 + ($i * 16)) -Count 16
        $total += Get-CrashDoctorUInt64 -Bytes $entry -Offset 8
    }
    return [pscustomobject][ordered]@{
        RangeCount = $count
        BaseRva = Get-CrashDoctorUInt64 -Bytes $header -Offset 8
        TotalMemoryBytes = $total
    }
}

function Read-CrashDoctorMiniDumpMemoryInfoSummary {
    param([System.IO.FileStream]$Stream, $Directory)
    if ($Directory.DataSize -lt 16) { return $null }
    $bytes = Read-CrashDoctorBytes -Stream $Stream -Offset $Directory.Rva -Count 16
    return [pscustomobject][ordered]@{
        HeaderSize = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 0
        EntrySize = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 4
        EntryCount = Get-CrashDoctorUInt64 -Bytes $bytes -Offset 8
    }
}

function Read-CrashDoctorMiniDump {
    param([System.IO.FileStream]$Stream, [string]$ResolvedPath)

    $header = Read-CrashDoctorBytes -Stream $Stream -Offset 0 -Count 32
    $streamCount = [int](Get-CrashDoctorUInt32 -Bytes $header -Offset 8)
    $directoryRva = Get-CrashDoctorUInt32 -Bytes $header -Offset 12
    if ($streamCount -gt 4096) { throw "Unreasonable MINIDUMP stream count: $streamCount" }
    $directoryBytes = [int64]$streamCount * 12
    if (($directoryRva + $directoryBytes) -gt $Stream.Length) { throw 'MINIDUMP stream directory extends beyond the file.' }

    $directories = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $streamCount; $i++) {
        $bytes = Read-CrashDoctorBytes -Stream $Stream -Offset ([int64]$directoryRva + ($i * 12)) -Count 12
        $streamType = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 0
        $dataSize = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 4
        $rva = Get-CrashDoctorUInt32 -Bytes $bytes -Offset 8
        if (($rva + [int64]$dataSize) -gt $Stream.Length) { throw "MINIDUMP stream $streamType extends beyond the file." }
        $directories.Add([pscustomobject][ordered]@{
            StreamType = $streamType
            Name = Get-CrashDoctorMiniDumpStreamName -StreamType $streamType
            DataSize = $dataSize
            Rva = $rva
        })
    }

    $byType = @{}
    foreach ($directory in $directories) {
        if (-not $byType.ContainsKey([int]$directory.StreamType)) { $byType[[int]$directory.StreamType] = $directory }
    }

    $systemInfo = if ($byType.ContainsKey(7)) { Read-CrashDoctorMiniDumpSystemInfo -Stream $Stream -Directory $byType[7] } else { $null }
    $exception = if ($byType.ContainsKey(6)) { Read-CrashDoctorMiniDumpException -Stream $Stream -Directory $byType[6] } else { $null }
    $modules = if ($byType.ContainsKey(4)) { Read-CrashDoctorMiniDumpModules -Stream $Stream -Directory $byType[4] } else { @() }
    $threadCount = if ($byType.ContainsKey(3)) { Read-CrashDoctorMiniDumpCountStream -Stream $Stream -Directory $byType[3] } else { $null }
    $memoryRangeCount = if ($byType.ContainsKey(5)) { Read-CrashDoctorMiniDumpCountStream -Stream $Stream -Directory $byType[5] } else { $null }
    $memory64 = if ($byType.ContainsKey(9)) { Read-CrashDoctorMiniDumpMemory64Summary -Stream $Stream -Directory $byType[9] } else { $null }
    $memoryInfo = if ($byType.ContainsKey(16)) { Read-CrashDoctorMiniDumpMemoryInfoSummary -Stream $Stream -Directory $byType[16] } else { $null }

    return [pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        Path = $ResolvedPath
        FileSize = $Stream.Length
        Format = 'MiniDump'
        Architecture = if ($systemInfo) { $systemInfo.ProcessorArchitecture } else { $null }
        Header = [pscustomobject][ordered]@{
            Signature = 'MDMP'
            Version = Get-CrashDoctorUInt32 -Bytes $header -Offset 4
            NumberOfStreams = $streamCount
            StreamDirectoryRva = $directoryRva
            Checksum = Get-CrashDoctorUInt32 -Bytes $header -Offset 16
            TimeDateStamp = Get-CrashDoctorUInt32 -Bytes $header -Offset 20
            Flags = Get-CrashDoctorUInt64 -Bytes $header -Offset 24
        }
        SystemInfo = $systemInfo
        Exception = $exception
        ModuleCount = $modules.Count
        Modules = $modules
        ThreadCount = $threadCount
        MemoryRangeCount = $memoryRangeCount
        Memory64 = $memory64
        MemoryInfo = $memoryInfo
        Streams = $directories.ToArray()
        ParseCoverage = 'Header, stream directory, system info, exception, modules, thread count and memory summaries'
    }
}

function Get-CrashDoctorKernelDumpTypeName {
    param([uint32]$DumpType)
    switch ($DumpType) {
        0 { 'Unknown' }
        1 { 'Full' }
        2 { 'Summary' }
        3 { 'Header' }
        4 { 'Triage' }
        5 { 'BitmapFull' }
        6 { 'BitmapKernel' }
        7 { 'Automatic' }
        default { "DumpType$DumpType" }
    }
}

function Read-CrashDoctorKernelDump64 {
    param([System.IO.FileStream]$Stream, [string]$ResolvedPath)
    if ($Stream.Length -lt 8192) { throw '64-bit kernel dump is smaller than the 8192-byte DUMP_HEADER64.' }
    $header = Read-CrashDoctorBytes -Stream $Stream -Offset 0 -Count 8192
    $dumpType = Get-CrashDoctorUInt32 -Bytes $header -Offset 3992
    return [pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        Path = $ResolvedPath
        FileSize = $Stream.Length
        Format = 'KernelCrashDump'
        Architecture = Get-CrashDoctorMachineName -MachineType (Get-CrashDoctorUInt32 -Bytes $header -Offset 48)
        Header = [pscustomobject][ordered]@{
            Signature = 'PAGE'
            ValidDump = 'DU64'
            MajorVersion = Get-CrashDoctorUInt32 -Bytes $header -Offset 8
            MinorVersion = Get-CrashDoctorUInt32 -Bytes $header -Offset 12
            DirectoryTableBase = Get-CrashDoctorUInt64 -Bytes $header -Offset 16
            PfnDataBase = Get-CrashDoctorUInt64 -Bytes $header -Offset 24
            PsLoadedModuleList = Get-CrashDoctorUInt64 -Bytes $header -Offset 32
            PsActiveProcessHead = Get-CrashDoctorUInt64 -Bytes $header -Offset 40
            MachineImageType = Get-CrashDoctorUInt32 -Bytes $header -Offset 48
            NumberProcessors = Get-CrashDoctorUInt32 -Bytes $header -Offset 52
            BugCheckCode = Get-CrashDoctorUInt32 -Bytes $header -Offset 56
            BugCheckParameter1 = Get-CrashDoctorUInt64 -Bytes $header -Offset 64
            BugCheckParameter2 = Get-CrashDoctorUInt64 -Bytes $header -Offset 72
            BugCheckParameter3 = Get-CrashDoctorUInt64 -Bytes $header -Offset 80
            BugCheckParameter4 = Get-CrashDoctorUInt64 -Bytes $header -Offset 88
            KdDebuggerDataBlock = Get-CrashDoctorUInt64 -Bytes $header -Offset 128
            DumpType = $dumpType
            DumpTypeName = Get-CrashDoctorKernelDumpTypeName -DumpType $dumpType
            RequiredDumpSpace = Get-CrashDoctorInt64 -Bytes $header -Offset 4000
            SystemTimeFileTime = Get-CrashDoctorInt64 -Bytes $header -Offset 4008
            SystemUpTime100ns = Get-CrashDoctorInt64 -Bytes $header -Offset 4144
            MiniDumpFields = Get-CrashDoctorUInt32 -Bytes $header -Offset 4152
            SecondaryDataState = Get-CrashDoctorUInt32 -Bytes $header -Offset 4156
            ProductType = Get-CrashDoctorUInt32 -Bytes $header -Offset 4160
            SuiteMask = Get-CrashDoctorUInt32 -Bytes $header -Offset 4164
            WriterStatus = Get-CrashDoctorUInt32 -Bytes $header -Offset 4168
        }
        ParseCoverage = 'DUMP_HEADER64 metadata only; physical memory pages are not yet traversed'
    }
}

function Read-CrashDoctorKernelDump32 {
    param([System.IO.FileStream]$Stream, [string]$ResolvedPath)
    if ($Stream.Length -lt 4096) { throw '32-bit kernel dump is smaller than a crash-dump header page.' }
    $header = Read-CrashDoctorBytes -Stream $Stream -Offset 0 -Count ([Math]::Min(4096, [int]$Stream.Length))
    return [pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        Path = $ResolvedPath
        FileSize = $Stream.Length
        Format = 'KernelCrashDump'
        Architecture = Get-CrashDoctorMachineName -MachineType (Get-CrashDoctorUInt32 -Bytes $header -Offset 32)
        Header = [pscustomobject][ordered]@{
            Signature = 'PAGE'
            ValidDump = 'DUMP'
            MajorVersion = Get-CrashDoctorUInt32 -Bytes $header -Offset 8
            MinorVersion = Get-CrashDoctorUInt32 -Bytes $header -Offset 12
            DirectoryTableBase = Get-CrashDoctorUInt32 -Bytes $header -Offset 16
            PfnDataBase = Get-CrashDoctorUInt32 -Bytes $header -Offset 20
            PsLoadedModuleList = Get-CrashDoctorUInt32 -Bytes $header -Offset 24
            PsActiveProcessHead = Get-CrashDoctorUInt32 -Bytes $header -Offset 28
            MachineImageType = Get-CrashDoctorUInt32 -Bytes $header -Offset 32
            NumberProcessors = Get-CrashDoctorUInt32 -Bytes $header -Offset 36
            BugCheckCode = Get-CrashDoctorUInt32 -Bytes $header -Offset 40
            BugCheckParameter1 = Get-CrashDoctorUInt32 -Bytes $header -Offset 44
            BugCheckParameter2 = Get-CrashDoctorUInt32 -Bytes $header -Offset 48
            BugCheckParameter3 = Get-CrashDoctorUInt32 -Bytes $header -Offset 52
            BugCheckParameter4 = Get-CrashDoctorUInt32 -Bytes $header -Offset 56
        }
        ParseCoverage = 'DUMP_HEADER32 core metadata only; physical memory pages are not yet traversed'
    }
}

function Get-CrashDoctorDumpInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Dump file does not exist: $Path"
    }

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $stream = [System.IO.File]::Open(
        $resolved,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    )
    try {
        if ($stream.Length -lt 8) { throw 'Dump file is too small to identify.' }
        $prefix = Read-CrashDoctorBytes -Stream $stream -Offset 0 -Count 8
        $signature = Get-CrashDoctorUInt32 -Bytes $prefix -Offset 0
        $validDump = Get-CrashDoctorUInt32 -Bytes $prefix -Offset 4

        if ($signature -eq $script:MiniDumpSignature) {
            return Read-CrashDoctorMiniDump -Stream $stream -ResolvedPath $resolved
        }
        if ($signature -eq $script:KernelDumpSignature -and $validDump -eq $script:KernelDumpValid64) {
            return Read-CrashDoctorKernelDump64 -Stream $stream -ResolvedPath $resolved
        }
        if ($signature -eq $script:KernelDumpSignature -and $validDump -eq $script:KernelDumpValid32) {
            return Read-CrashDoctorKernelDump32 -Stream $stream -ResolvedPath $resolved
        }

        $ascii = [Text.Encoding]::ASCII.GetString($prefix)
        throw "Unsupported or unrecognized dump format. First 8 bytes: '$ascii'."
    }
    finally {
        $stream.Dispose()
    }
}

Export-ModuleMember -Function Get-CrashDoctorDumpInfo