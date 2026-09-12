Set-StrictMode -Version Latest

function Get-CrashDoctorFileText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$EvidencePath,
        [Parameter(Mandatory = $true)] [string]$Name
    )

    $path = Join-Path $EvidencePath $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return ''
    }

    return Get-Content -LiteralPath $path -Raw -ErrorAction Stop
}

function Get-CrashDoctorFirstValue {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string]$Text,
        [Parameter(Mandatory = $true)] [string]$Pattern,
        [int]$Group = 1
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[$Group].Value.Trim()
}

function New-CrashDoctorFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Id,
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')] [string]$Severity = 'Info',
        [ValidateSet('High', 'Medium', 'Low')] [string]$Confidence = 'Medium',
        [Parameter(Mandatory = $true)] [string]$Title,
        [Parameter(Mandatory = $true)] [string]$Evidence,
        [Parameter(Mandatory = $true)] [string]$Interpretation,
        [Parameter(Mandatory = $true)] [string]$NextStep
    )

    [pscustomobject][ordered]@{
        Id             = $Id
        Severity       = $Severity
        Confidence     = $Confidence
        Title          = $Title
        Evidence       = $Evidence
        Interpretation = $Interpretation
        NextStep       = $NextStep
    }
}

function Get-CrashDoctorMaxNumber {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string]$Text,
        [Parameter(Mandatory = $true)] [string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $values = @(
        [regex]::Matches(
            $Text,
            $Pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        ) | ForEach-Object {
            [int64]$_.Groups[1].Value
        }
    )

    if ($values.Count -eq 0) {
        return $null
    }

    return ($values | Measure-Object -Maximum).Maximum
}

function Get-CrashDoctorSumNumber {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string]$Text,
        [Parameter(Mandatory = $true)] [string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $values = @(
        [regex]::Matches(
            $Text,
            $Pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        ) | ForEach-Object {
            [int64]$_.Groups[1].Value
        }
    )

    if ($values.Count -eq 0) {
        return $null
    }

    return ($values | Measure-Object -Sum).Sum
}

function Invoke-CrashDoctorAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$EvidencePath
    )

    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Container)) {
        throw "Evidence path does not exist or is not a directory: $EvidencePath"
    }

    $resolvedPath = (Resolve-Path -LiteralPath $EvidencePath).Path
    $knownFiles = @(
        'computer-system.txt',
        'os.txt',
        'baseboard.txt',
        'bios.txt',
        'cpu.txt',
        'memory.txt',
        'pagefile-and-dumps.txt',
        'physical-disks.txt',
        'storage-reliability.txt',
        'powercfg-a.txt',
        'powercfg-lastwake.txt',
        'powercfg-waketimers.txt',
        'bitlocker-status.txt',
        'problem-devices.txt',
        'firmware-devices.txt',
        'interesting-services.txt',
        'interesting-drivers.txt',
        'recent-system-events.txt',
        'recent-application-events.txt',
        'setupapi.dev.log',
        'collection-metadata.txt'
    )

    $text = @{}
    $presentFiles = New-Object System.Collections.Generic.List[string]
    $missingFiles = New-Object System.Collections.Generic.List[string]

    foreach ($name in $knownFiles) {
        $value = Get-CrashDoctorFileText -EvidencePath $resolvedPath -Name $name
        $text[$name] = $value
        if ([string]::IsNullOrWhiteSpace($value)) {
            $missingFiles.Add($name)
        }
        else {
            $presentFiles.Add($name)
        }
    }

    $findings = New-Object System.Collections.Generic.List[object]

    $computer = $text['computer-system.txt']
    $bios = $text['bios.txt']
    $memory = $text['memory.txt']
    $pagefile = $text['pagefile-and-dumps.txt']
    $storage = $text['storage-reliability.txt']
    $power = $text['powercfg-a.txt']
    $bitlocker = $text['bitlocker-status.txt']
    $problems = $text['problem-devices.txt']
    $firmware = $text['firmware-devices.txt']
    $services = $text['interesting-services.txt']
    $drivers = $text['interesting-drivers.txt']
    $systemEvents = $text['recent-system-events.txt']
    $applicationEvents = $text['recent-application-events.txt']
    $setupApi = $text['setupapi.dev.log']

    $model = Get-CrashDoctorFirstValue -Text $computer -Pattern '(?im)^\s*Model\s*:\s*(.+)$'
    if (-not $model) {
        $model = Get-CrashDoctorFirstValue -Text $setupApi -Pattern '(?im)^\s*set:\s+System Product Name:\s*(.+)$'
    }

    $biosVersion = Get-CrashDoctorFirstValue -Text $bios -Pattern '(?im)^\s*SMBIOSBIOSVersion\s*:\s*(.+)$'
    if (-not $biosVersion) {
        $biosVersion = Get-CrashDoctorFirstValue -Text $bios -Pattern '(?im)^\s*Name\s*:\s*(N\d+\s+Ver\.\s+.+)$'
    }

    $physicalMemoryBytes = Get-CrashDoctorSumNumber -Text $memory -Pattern '(?im)^\s*Capacity\s*:\s*(\d+)\s*$'
    $physicalMemoryGiB = $null
    if ($physicalMemoryBytes) {
        $physicalMemoryGiB = [math]::Round($physicalMemoryBytes / 1GB, 2)
    }

    if ($problems -match '(?is)(Class Name:\s*Firmware|Class\s*:\s*Firmware).*?(Problem Code:\s*10\b|CM_PROB_FAILED_START|0xC0000001)') {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'firmware-device-failed-start' `
            -Severity 'High' `
            -Confidence 'High' `
            -Title 'Firmware-class device is in a failed-start state' `
            -Evidence 'The problem-device capture contains a Firmware-class device with Code 10 / CM_PROB_FAILED_START / 0xC0000001.' `
            -Interpretation 'This is a real low-level abnormality. It is relevant to firmware troubleshooting, but it does not by itself prove that firmware caused a hard hang.' `
            -NextStep 'Preserve the exact device identity and driver package, then retest after one controlled firmware-state change.'))
    }

    if (($firmware -match '(?im)^\s*Status\s*:\s*OK\s*$') -and
        ($firmware -match '(?i)UEFI\\RES_|Firmware')) {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'firmware-resource-currently-ok' `
            -Severity 'Info' `
            -Confidence 'High' `
            -Title 'Firmware resource currently reports OK' `
            -Evidence 'The current Firmware-class PnP capture contains Status: OK.' `
            -Interpretation 'This is useful post-change state evidence. It does not erase an earlier Code 10 record, and stability still needs to be measured after the change.' `
            -NextStep 'Preserve this snapshot as the post-change baseline and continue the controlled stability window before making another major change.'))
    }

    if ($setupApi -match '(?im)Sysprep Respecialize') {
        $nonPresent = Get-CrashDoctorMaxNumber -Text $setupApi -Pattern 'Devices non-present:\s*(\d+)'
        $evidence = 'SetupAPI contains a Sysprep Respecialize section.'
        if ($null -ne $nonPresent) {
            $evidence += " The largest recorded non-present-device count is $nonPresent."
        }

        $findings.Add((New-CrashDoctorFinding `
            -Id 'generalised-or-reused-windows-image' `
            -Severity 'Medium' `
            -Confidence 'High' `
            -Title 'Windows image was generalised/respecialised and retains prior device state' `
            -Evidence $evidence `
            -Interpretation 'This supports a refurb/deployment-image history. It raises the chance of stale OEM/device state, but image reuse is not proof of freeze causality.' `
            -NextStep 'Keep current-machine evidence separate from inherited history. Use a clean OS/live environment later if the fault survives lower-risk tests.'))
    }

    if (($services -match '(?i)\bXTU\b|Intel.*Tuning') -or
        ($drivers -match '(?i)\bXTU\b|Intel.*Tuning') -or
        ($setupApi -match '(?i)XTUComponent|PROVIDER_Intel_COMPONENT_XTU')) {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'intel-xtu-stack-present' `
            -Severity 'Medium' `
            -Confidence 'High' `
            -Title 'Intel XTU components are present in the current Windows image' `
            -Evidence 'The service/device evidence contains Intel XTU / XTUComponent references.' `
            -Interpretation 'XTU is capable of changing voltage/power behaviour. Presence alone does not prove an undervolt or unstable tuning profile.' `
            -NextStep 'Inspect current XTU settings without changing them; record any voltage offset or custom profile before removal/reset is considered.'))
    }

    if (($services -match '(?i)Conexant|CxMon|CxUtil|MicTray') -or
        ($drivers -match '(?i)Conexant|CxMon|CxUtil|MicTray') -or
        ($applicationEvents -match '(?i)Conexant|CxMonSvc|CxUtilSvc|MicTray')) {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'conexant-stack-present' `
            -Severity 'Low' `
            -Confidence 'High' `
            -Title 'Conexant OEM audio stack is present in the evidence' `
            -Evidence 'Service/application evidence contains Conexant/CxMon/CxUtil/MicTray components.' `
            -Interpretation 'Old OEM audio services can participate in power notifications. Their presence is a lead, not a root-cause finding.' `
            -NextStep 'Only isolate/remove the audio stack in its own test stage if higher-priority firmware/power tests do not resolve the hangs.'))
    }

    if ($bitlocker -match '(?im)Conversion Status:\s*Encryption in Progress') {
        $percentage = Get-CrashDoctorFirstValue -Text $bitlocker -Pattern '(?im)Percentage Encrypted:\s*([0-9.]+%)'
        $evidence = 'BitLocker reports Encryption in Progress.'
        if ($percentage) {
            $evidence += " Reported percentage: $percentage."
        }

        $findings.Add((New-CrashDoctorFinding `
            -Id 'bitlocker-conversion-active' `
            -Severity 'Info' `
            -Confidence 'High' `
            -Title 'BitLocker conversion is/was still active in this snapshot' `
            -Evidence $evidence `
            -Interpretation 'Conversion activity is relevant context for storage load and firmware changes. A repeated percentage reading over a short interval does not establish a storage stall.' `
            -NextStep 'Track conversion to a stable state separately from freeze-cause testing and preserve recovery-key safety before firmware work.'))
    }

    if ($power -match '(?is)Fast Startup.*Hibernation is not available' -or
        $power -match '(?is)Hibernate.*Hibernation has not been enabled') {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'fast-startup-disabled' `
            -Severity 'Info' `
            -Confidence 'High' `
            -Title 'Hibernation/Fast Startup is disabled or unavailable' `
            -Evidence 'powercfg /a reports hibernation/Fast Startup unavailable.' `
            -Interpretation 'This creates a useful A/B condition for faults that cluster after S4/Fast Startup transitions.' `
            -NextStep 'Measure stability duration and shutdown/start cycles before changing another major variable.'))
    }

    $crashDumpEnabled = Get-CrashDoctorFirstValue -Text $pagefile -Pattern '(?im)^\s*CrashDumpEnabled\s*:\s*(\d+)\s*$'
    $allocatedPagefileMb = Get-CrashDoctorMaxNumber -Text $pagefile -Pattern '(?im)^\s*AllocatedBaseSize\s*:\s*(\d+)\s*$'
    if (($crashDumpEnabled -eq '0') -or ($null -ne $allocatedPagefileMb -and $allocatedPagefileMb -lt 2048)) {
        $evidence = @()
        if ($crashDumpEnabled -eq '0') {
            $evidence += 'CrashDumpEnabled is 0.'
        }
        if ($null -ne $allocatedPagefileMb -and $allocatedPagefileMb -lt 2048) {
            $evidence += "Allocated pagefile is $allocatedPagefileMb MB."
        }

        $findings.Add((New-CrashDoctorFinding `
            -Id 'crash-dump-capture-risk' `
            -Severity 'Medium' `
            -Confidence 'High' `
            -Title 'Crash-dump capture may be unreliable' `
            -Evidence ($evidence -join ' ') `
            -Interpretation 'A missing dump cannot safely be interpreted as evidence that the storage stack or kernel never reached the dump path when dump/pagefile configuration is inadequate.' `
            -NextStep 'Use a system-managed pagefile and an appropriate kernel/automatic memory-dump setting before relying on future dump absence.'))
    }

    $readErrorsTotal = Get-CrashDoctorMaxNumber -Text $storage -Pattern '(?im)^\s*ReadErrorsTotal\s*:\s*(\d+)\s*$'
    $readErrorsUncorrected = Get-CrashDoctorMaxNumber -Text $storage -Pattern '(?im)^\s*ReadErrorsUncorrected\s*:\s*(\d+)\s*$'
    if (($null -ne $readErrorsUncorrected -and $readErrorsUncorrected -gt 0) -or
        ($null -ne $readErrorsTotal -and $readErrorsTotal -gt 0)) {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'storage-read-errors-present' `
            -Severity 'High' `
            -Confidence 'High' `
            -Title 'Storage reliability counters contain read errors' `
            -Evidence "ReadErrorsTotal=$readErrorsTotal; ReadErrorsUncorrected=$readErrorsUncorrected." `
            -Interpretation 'Current storage error counters materially increase the priority of SSD/controller investigation.' `
            -NextStep 'Preserve SMART/reliability data, back up important data and run vendor/UEFI storage diagnostics before destructive testing.'))
    }
    elseif ($null -ne $readErrorsTotal -or $null -ne $readErrorsUncorrected) {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'storage-counters-reassuring' `
            -Severity 'Info' `
            -Confidence 'Medium' `
            -Title 'Captured storage reliability counters do not show read errors' `
            -Evidence "ReadErrorsTotal=$readErrorsTotal; ReadErrorsUncorrected=$readErrorsUncorrected." `
            -Interpretation 'This weakens a straightforward failing-SSD theory but cannot rule out every intermittent controller or device fault.' `
            -NextStep 'Keep storage lower in the suspect order unless new errors, timeouts or SMART changes appear.'))
    }

    $wheaCount = [regex]::Matches($systemEvents, '(?i)WHEA-Logger').Count
    $kernelPower41Count = [regex]::Matches(
        $systemEvents,
        '(?is)Id\s*:\s*41\b.*?ProviderName\s*:\s*Microsoft-Windows-Kernel-Power'
    ).Count
    $volmgr161Count = [regex]::Matches(
        $systemEvents,
        '(?is)Id\s*:\s*161\b.*?ProviderName\s*:\s*volmgr'
    ).Count

    if ($wheaCount -gt 0) {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'whea-events-present' `
            -Severity 'High' `
            -Confidence 'Medium' `
            -Title 'WHEA hardware-error events are present in the captured window' `
            -Evidence "WHEA-Logger references found: $wheaCount." `
            -Interpretation 'WHEA evidence increases the priority of CPU, memory, PCIe and motherboard hardware investigation. Exact event contents still matter.' `
            -NextStep 'Inspect the WHEA event IDs and error records before making further software changes.'))
    }
    elseif (-not [string]::IsNullOrWhiteSpace($systemEvents)) {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'no-whea-in-window' `
            -Severity 'Info' `
            -Confidence 'Low' `
            -Title 'No WHEA-Logger reference was found in the captured event window' `
            -Evidence 'The text event export contains no WHEA-Logger provider name.' `
            -Interpretation 'This is absence of evidence within a limited collection window, not proof that hardware is healthy.' `
            -NextStep 'Keep intermittent RAM/mainboard faults in reserve until longer memory testing and controlled OS/firmware tests are complete.'))
    }

    if ($kernelPower41Count -gt 0) {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'kernel-power-41-present' `
            -Severity 'Info' `
            -Confidence 'High' `
            -Title 'Unexpected/forced shutdown evidence is present' `
            -Evidence "Kernel-Power Event 41 records found in the captured text window: $kernelPower41Count." `
            -Interpretation 'Event 41 confirms an unclean shutdown; it normally records the aftermath rather than the root cause.' `
            -NextStep 'Correlate each Event 41 with the final pre-hang events and the user-observed freeze time.'))
    }

    if ($volmgr161Count -gt 0) {
        $findings.Add((New-CrashDoctorFinding `
            -Id 'volmgr-161-present' `
            -Severity 'Low' `
            -Confidence 'High' `
            -Title 'Dump-file creation failures are present' `
            -Evidence "volmgr Event 161 records found in the captured text window: $volmgr161Count." `
            -Interpretation 'This says dump capture failed; by itself it does not identify why the computer hung.' `
            -NextStep 'Fix pagefile/dump capture first, then use any future Event 161 as a separate diagnostic signal.'))
    }

    $severityOrder = @{
        Critical = 0
        High     = 1
        Medium   = 2
        Low      = 3
        Info     = 4
    }

    $sortedFindings = @(
        $findings |
            Sort-Object @{ Expression = { $severityOrder[$_.Severity] } }, @{ Expression = { $_.Id } }
    )

    [pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        GeneratedAt   = (Get-Date).ToString('o')
        EvidencePath  = $resolvedPath
        Coverage      = [pscustomobject][ordered]@{
            PresentFiles  = @($presentFiles)
            MissingFiles  = @($missingFiles)
            PresentCount  = $presentFiles.Count
            ExpectedCount = $knownFiles.Count
            Percent       = [math]::Round((100.0 * $presentFiles.Count) / $knownFiles.Count, 0)
        }
        Inventory     = [pscustomobject][ordered]@{
            Model             = $model
            BIOS              = $biosVersion
            PhysicalMemoryGiB = $physicalMemoryGiB
        }
        EventSummary  = [pscustomobject][ordered]@{
            WHEAReferences       = $wheaCount
            KernelPower41Records = $kernelPower41Count
            Volmgr161Records     = $volmgr161Count
        }
        Findings      = $sortedFindings
    }
}

function ConvertTo-CrashDoctorMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Windows Crash Doctor report')
    $lines.Add('')
    $lines.Add("Generated: **$($Report.GeneratedAt)**")
    $lines.Add('')
    $lines.Add("Evidence directory: ``$($Report.EvidencePath)``")
    $lines.Add('')
    $lines.Add('> This report ranks evidence signals. It does not claim that a detected abnormality is the root cause unless independent evidence proves that link.')
    $lines.Add('')
    $lines.Add('## Coverage')
    $lines.Add('')
    $lines.Add("- Files present: **$($Report.Coverage.PresentCount) / $($Report.Coverage.ExpectedCount)** ($($Report.Coverage.Percent)%)")
    if ($Report.Coverage.MissingFiles.Count -gt 0) {
        $lines.Add("- Missing/empty inputs: $($Report.Coverage.MissingFiles -join ', ')")
    }
    else {
        $lines.Add('- All expected text inputs are present.')
    }
    $lines.Add('')
    $lines.Add('## Inventory')
    $lines.Add('')
    $lines.Add('| Field | Value |')
    $lines.Add('|---|---|')
    $lines.Add("| Model | $($Report.Inventory.Model) |")
    $lines.Add("| BIOS | $($Report.Inventory.BIOS) |")
    $lines.Add("| Physical memory (GiB) | $($Report.Inventory.PhysicalMemoryGiB) |")
    $lines.Add('')
    $lines.Add('## Event summary')
    $lines.Add('')
    $lines.Add('| Signal | Count |')
    $lines.Add('|---|---:|')
    $lines.Add("| WHEA references | $($Report.EventSummary.WHEAReferences) |")
    $lines.Add("| Kernel-Power 41 records | $($Report.EventSummary.KernelPower41Records) |")
    $lines.Add("| volmgr 161 records | $($Report.EventSummary.Volmgr161Records) |")
    $lines.Add('')
    $lines.Add('## Findings')
    $lines.Add('')

    if ($Report.Findings.Count -eq 0) {
        $lines.Add('No rule fired from the supplied text evidence. This does **not** mean the machine is healthy; it may mean the evidence set is incomplete.')
    }
    else {
        $lines.Add('| Severity | Confidence | ID | Finding |')
        $lines.Add('|---|---|---|---|')
        foreach ($finding in $Report.Findings) {
            $safeTitle = $finding.Title.Replace('|', '\|')
            $lines.Add("| $($finding.Severity) | $($finding.Confidence) | ``$($finding.Id)`` | $safeTitle |")
        }

        foreach ($finding in $Report.Findings) {
            $lines.Add('')
            $lines.Add("### $($finding.Title)")
            $lines.Add('')
            $lines.Add("- **Severity:** $($finding.Severity)")
            $lines.Add("- **Confidence:** $($finding.Confidence)")
            $lines.Add("- **Evidence:** $($finding.Evidence)")
            $lines.Add("- **Interpretation:** $($finding.Interpretation)")
            $lines.Add("- **Next step:** $($finding.NextStep)")
        }
    }

    $lines.Add('')
    $lines.Add('## Interpretation rules')
    $lines.Add('')
    $lines.Add('- Event 41 is aftermath evidence, not a root-cause label.')
    $lines.Add('- Missing WHEA/BSOD evidence does not clear intermittent hardware.')
    $lines.Add('- A stale/reused Windows image is a diagnostic confounder, not automatically the cause.')
    $lines.Add('- Firmware Code 10 is real evidence of an abnormal firmware-device state, but the mechanism of a hard hang must still be demonstrated.')
    $lines.Add('- Make one major change at a time and preserve the before/after snapshot.')

    return ($lines -join [Environment]::NewLine)
}

Export-ModuleMember -Function Invoke-CrashDoctorAnalysis, ConvertTo-CrashDoctorMarkdown
