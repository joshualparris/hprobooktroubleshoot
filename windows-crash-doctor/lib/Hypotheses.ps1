function Get-WcdEventCount {
    param($Evidence, [int[]]$Ids, [string]$ProviderPattern)
    $rows = @($Evidence.Events | Where-Object {
        ($Ids -contains [int]$_.Id) -and ((-not $ProviderPattern) -or ($_.Provider -match $ProviderPattern))
    })
    return $rows.Count
}

function New-WcdHypothesis {
    param(
        [string]$Id,
        [string]$Title,
        [int]$Score,
        [string[]]$Supporting,
        [string[]]$Contradicting,
        [string[]]$Unknowns,
        [string]$NextTest
    )
    if ($Score -lt 0) { $Score = 0 }
    if ($Score -gt 100) { $Score = 100 }
    $confidence = 'Low'
    if ($Score -ge 70) { $confidence = 'High' }
    elseif ($Score -ge 45) { $confidence = 'Medium' }

    [pscustomobject]@{
        Id = $Id
        Title = $Title
        Score = $Score
        Confidence = $confidence
        SupportingEvidence = @($Supporting)
        ContradictingEvidence = @($Contradicting)
        Unknowns = @($Unknowns)
        NextDiscriminatingTest = $NextTest
    }
}

function Get-WcdHypotheses {
    param([Parameter(Mandatory=$true)]$Evidence)

    $hypotheses = New-Object System.Collections.Generic.List[object]
    $events = @($Evidence.Events)
    $kernelPower = @($events | Where-Object { $_.Id -eq 41 -or $_.Id -eq 6008 }).Count
    $powerTransitions = @($events | Where-Object { $_.Id -eq 42 -or ($_.Provider -match 'Power-Troubleshooter' -and $_.Id -eq 1) }).Count
    $storageEvents = @($events | Where-Object { $_.Id -in @(7,11,51,55,129,153) -and $_.Provider -match 'disk|stor|ntfs' }).Count
    $displayEvents = @($events | Where-Object { $_.Id -eq 4101 -or $_.Provider -match 'Display|igfx|Graphics' }).Count
    $wheaEvents = @($events | Where-Object { $_.Provider -match 'WHEA' -and $_.Id -in @(17,18,19,20,47) }).Count
    $volmgrEvents = @($events | Where-Object { $_.Provider -match 'volmgr' -and $_.Id -eq 161 }).Count

    $s = 20; $support=@(); $against=@(); $unknown=@()
    if ($kernelPower -gt 0) { $s += 15; $support += "$kernelPower unexpected-shutdown / Kernel-Power events exist in the analysis window." }
    if ($powerTransitions -gt 0) { $s += 20; $support += "$powerTransitions sleep/resume or power-transition events exist near the incident window." }
    if ($kernelPower -eq 0) { $against += 'No recent Kernel-Power 41 or EventLog 6008 event was found.' }
    $unknown += 'A hard freeze may leave no final event immediately before the hang; the canary timeline is the stronger discriminator.'
    $hypotheses.Add((New-WcdHypothesis 'power-state' 'Power-state / resume interaction' $s $support $against $unknown 'Run a controlled cold-boot vs resume/Fast Startup A/B test with one variable changed.'))

    $s=20; $support=@(); $against=@(); $unknown=@()
    if ($Evidence.Machine.BiosAgeYears -and $Evidence.Machine.BiosAgeYears -ge 5) { $s += 25; $support += "BIOS is approximately $($Evidence.Machine.BiosAgeYears) years old." }
    $firmwareProblems = @($Evidence.DriverResidue.ProblemDevices | Where-Object { $_.Class -match 'Firmware' }).Count
    if ($firmwareProblems -gt 0) { $s += 30; $support += "$firmwareProblems firmware-class PnP problem device(s) are present." }
    if ($firmwareProblems -eq 0) { $against += 'No current firmware-class PnP problem device was found.' }
    $unknown += 'Installed BIOS age alone does not prove that firmware caused a freeze.'
    $hypotheses.Add((New-WcdHypothesis 'firmware' 'Firmware / BIOS interaction' $s $support $against $unknown 'Compare installed BIOS with the exact OEM model support page, then update through the official path if appropriate.'))

    $s=15; $support=@(); $against=@(); $unknown=@()
    if ($Evidence.DriverResidue.SuspiciousLowLevelDriverCount -gt 0) {
        $s += [Math]::Min(40, ($Evidence.DriverResidue.SuspiciousLowLevelDriverCount * 10))
        $support += "$($Evidence.DriverResidue.SuspiciousLowLevelDriverCount) low-level tuning/OEM driver or service entries matched the watch list."
    } else { $against += 'No watched low-level tuning/OEM drivers were detected.' }
    if ($Evidence.DriverResidue.ProblemDeviceCount -gt 0) { $s += 10; $support += "$($Evidence.DriverResidue.ProblemDeviceCount) PnP devices report a non-OK state." }
    $unknown += 'Presence of a driver is not proof that it was active at the freeze.'
    $hypotheses.Add((New-WcdHypothesis 'low-level-driver' 'Low-level OEM / tuning driver interaction' $s $support $against $unknown 'Inspect matched services and remove or update one unsupported low-level component at a time.'))

    $s=10; $support=@(); $against=@(); $unknown=@()
    if ($Evidence.DriverResidue.SetupApiSysprepMentions -gt 0) { $s += 30; $support += 'SetupAPI contains Sysprep/respecialisation evidence.' }
    if ($null -ne $Evidence.DriverResidue.DisconnectedDeviceCount -and $Evidence.DriverResidue.DisconnectedDeviceCount -gt 50) {
        $s += 30; $support += "$($Evidence.DriverResidue.DisconnectedDeviceCount) disconnected device nodes were enumerated."
    } elseif ($null -ne $Evidence.DriverResidue.DisconnectedDeviceCount) {
        $against += "Only $($Evidence.DriverResidue.DisconnectedDeviceCount) disconnected device nodes were enumerated."
    } else { $unknown += 'Disconnected-device enumeration was unavailable.' }
    $unknown += 'Image reuse is a system-quality risk but not automatically the crash mechanism.'
    $hypotheses.Add((New-WcdHypothesis 'reused-image' 'Reused / migrated Windows image' $s $support $against $unknown 'If freezes persist after firmware and driver isolation, compare with a clean Windows or live-environment installation.'))

    $s=15; $support=@(); $against=@(); $unknown=@()
    if ($storageEvents -gt 0) { $s += [Math]::Min(45,$storageEvents*8); $support += "$storageEvents storage-reset/error event(s) were found." }
    $badReliability = @($Evidence.Storage | Where-Object {
        ($_.ReadErrorsUncorrected -gt 0) -or ($_.WriteErrorsUncorrected -gt 0) -or ($_.HealthStatus -and $_.HealthStatus -ne 'Healthy')
    }).Count
    if ($badReliability -gt 0) { $s += 35; $support += "$badReliability physical disk(s) report concerning health/reliability values." }
    if ($storageEvents -eq 0 -and $badReliability -eq 0 -and @($Evidence.Storage).Count -gt 0) {
        $s -= 10; $against += 'No selected storage reset/error events or uncorrected reliability errors were found.'
    }
    $hypotheses.Add((New-WcdHypothesis 'storage' 'Storage / controller failure' $s $support $against @('A hard controller lock can occasionally leave sparse event evidence.') 'Back up first, then correlate storage events with incident time and run the OEM/SMART extended test if evidence increases.'))

    $s=15; $support=@(); $against=@(); $unknown=@()
    if ($displayEvents -gt 0) { $s += [Math]::Min(45,$displayEvents*8); $support += "$displayEvents display/graphics event(s) were found." }
    else { $against += 'No selected display/GPU reset events were found.' }
    $hypotheses.Add((New-WcdHypothesis 'graphics' 'Graphics driver / GPU hang' $s $support $against @('A full-system graphics-triggered lock may prevent a TDR event from being written.') 'Correlate GPU telemetry and Display/graphics events with the final canary samples.'))

    $s=15; $support=@(); $against=@(); $unknown=@()
    if ($wheaEvents -gt 0) { $s += [Math]::Min(50,$wheaEvents*10); $support += "$wheaEvents WHEA hardware-error event(s) were found." }
    else { $against += 'No selected WHEA hardware-error events were found.' }
    $unknown += 'Absence of WHEA does not exclude RAM, motherboard or CPU faults during a hard lock.'
    $hypotheses.Add((New-WcdHypothesis 'hardware-memory' 'RAM / motherboard / CPU hardware' $s $support $against $unknown 'Run MemTest86 or OEM extended memory diagnostics if instability persists.'))

    $s=10; $support=@(); $against=@(); $unknown=@()
    if ($Evidence.CurrentSample.TemperatureC -and $Evidence.CurrentSample.TemperatureC -ge 90) {
        $s += 55; $support += "Current ACPI thermal-zone reading is $($Evidence.CurrentSample.TemperatureC) C."
    } elseif ($Evidence.CurrentSample.TemperatureC) {
        $against += "Current ACPI thermal-zone reading is $($Evidence.CurrentSample.TemperatureC) C."
    } else { $unknown += 'ACPI temperature telemetry is unavailable or unreliable on this model.' }
    $hypotheses.Add((New-WcdHypothesis 'thermal' 'Thermal instability' $s $support $against $unknown 'Compare sustained sensor logging immediately before an incident.'))

    $s=5; $support=@(); $against=@(); $unknown=@()
    if ($Evidence.CrashCapture.Status -eq 'NotReady') {
        $s=90; $support += 'Crash capture is currently not ready.'
    } elseif ($Evidence.CrashCapture.Status -eq 'Review') {
        $s=65; $support += 'Crash capture configuration needs review.'
    } else {
        $against += 'Crash capture appears likely ready.'
    }
    if ($volmgrEvents -gt 0) { $s = [Math]::Max($s,80); $support += "$volmgrEvents volmgr 161 dump-creation failure event(s) were found." }
    $hypotheses.Add((New-WcdHypothesis 'capture-gap' 'Crash-capture gap (diagnostic blocker)' $s $support $against $unknown 'Fix dump/pagefile readiness before treating missing dumps as evidence about the root cause.'))

    return @($hypotheses | Sort-Object Score -Descending)
}

