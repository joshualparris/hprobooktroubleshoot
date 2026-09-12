Set-StrictMode -Version Latest

function New-TelemetryFinding {
    param([string]$Id,[string]$Severity,[string]$Confidence,[string]$Title,[string]$Evidence,[string]$Interpretation,[string]$NextStep)
    [pscustomobject][ordered]@{Id=$Id;Severity=$Severity;Confidence=$Confidence;Title=$Title;Evidence=$Evidence;Interpretation=$Interpretation;NextStep=$NextStep}
}

function ConvertTo-Number {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    $n=0.0
    $styles=[Globalization.NumberStyles]::Float -bor [Globalization.NumberStyles]::AllowThousands
    if ([double]::TryParse([string]$Value,$styles,[Globalization.CultureInfo]::InvariantCulture,[ref]$n)) { return $n }
    $null
}

function Import-SensorCsv {
    param([string]$Path)
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
    $parser=[Microsoft.VisualBasic.FileIO.TextFieldParser]::new($Path,[Text.Encoding]::GetEncoding(28591),$true)
    $parser.TextFieldType=[Microsoft.VisualBasic.FileIO.FieldType]::Delimited
    $parser.SetDelimiters(',')
    $parser.HasFieldsEnclosedInQuotes=$true
    try {
        if ($parser.EndOfData) { return @() }
        $raw=@($parser.ReadFields()); $seen=@{}; $headers=@()
        foreach($h0 in $raw) {
            $h=[string]$h0; if([string]::IsNullOrWhiteSpace($h)){$h='Unnamed'}
            if($seen.ContainsKey($h)){$seen[$h]++;$headers+=('{0} #{1}' -f $h,$seen[$h])}else{$seen[$h]=1;$headers+=$h}
        }
        $rows=@()
        while(-not $parser.EndOfData) {
            try{$fields=@($parser.ReadFields())}catch [Microsoft.VisualBasic.FileIO.MalformedLineException]{continue}
            if($fields.Count -eq 0){continue}
            $row=[ordered]@{}; for($i=0;$i -lt $headers.Count;$i++){$row[$headers[$i]]=if($i -lt $fields.Count){$fields[$i]}else{$null}}
            $rows += [pscustomobject]$row
        }
        ,$rows
    } finally { $parser.Close() }
}

function Find-Column {
    param([object[]]$Rows,[string]$Pattern)
    if($Rows.Count -eq 0){return $null}
    $m=@($Rows[0].PSObject.Properties.Name|Where-Object{$_ -match $Pattern}|Select-Object -First 1)
    if($m.Count){[string]$m[0]}else{$null}
}

function Find-Columns {
    param([object[]]$Rows,[string]$Pattern)
    if($Rows.Count -eq 0){return @()}
    @($Rows[0].PSObject.Properties.Name|Where-Object{$_ -match $Pattern})
}

function Get-Series {
    param([object[]]$Rows,[AllowNull()][string]$Column)
    if([string]::IsNullOrWhiteSpace($Column)){return @()}
    @(foreach($r in $Rows){$n=ConvertTo-Number $r.$Column;if($null -ne $n){$n}})
}

function Get-Percentile {
    param([double[]]$Values,[double]$Percentile)
    if($Values.Count -eq 0){return $null};$s=@($Values|Sort-Object);if($s.Count -eq 1){return [double]$s[0]}
    $p=($Percentile/100)*($s.Count-1);$lo=[math]::Floor($p);$hi=[math]::Ceiling($p);if($lo -eq $hi){return [double]$s[$lo]}
    ([double]$s[$lo]*(1-($p-$lo)))+([double]$s[$hi]*($p-$lo))
}

function Get-SensorTime {
    param($Row)
    if($null -eq $Row.PSObject.Properties['Date'] -or $null -eq $Row.PSObject.Properties['Time']){return $null}
    $dt=[datetime]::MinValue;$formats=[string[]]@('d.M.yyyy H:m:s.fff','d.M.yyyy H:m:s','dd.MM.yyyy HH:mm:ss.fff','yyyy-MM-dd HH:mm:ss.fff')
    if([datetime]::TryParseExact(('{0} {1}' -f $Row.Date,$Row.Time),$formats,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AllowWhiteSpaces,[ref]$dt)){$dt}else{$null}
}

function Get-SensorTelemetry {
    param([string]$EvidencePath)
    $file=@(Get-ChildItem -LiteralPath $EvidencePath -File -ErrorAction SilentlyContinue|Where-Object{$_.Name -match '(?i)^(sensors?|hwinfo).*\.csv$'}|Sort-Object LastWriteTime -Descending|Select-Object -First 1)
    if(-not $file.Count){return [pscustomobject]@{Available=$false;SourceFile=$null;Summary=$null;Findings=@()}}
    $rows=@(Import-SensorCsv $file[0].FullName);if(-not $rows.Count){return [pscustomobject]@{Available=$false;SourceFile=$file[0].Name;Summary=$null;Findings=@()}}

    $memCol=Find-Column $rows '^Physical Memory Load \[%\]$';$availCol=Find-Column $rows '^Physical Memory Available \[MB\]$'
    $vmCol=Find-Column $rows '^Virtual Memory Load \[%\]$';$pfTotalCol=Find-Column $rows '^Page File Total \[MB\]$';$pfUsedCol=Find-Column $rows '^Page File Used \[MB\]$'
    $cpuCol=Find-Column $rows '^Total CPU Usage \[%\]$';$tempCol=Find-Column $rows '^CPU Package \[';$wheaCol=Find-Column $rows '^(?:WHEA )?Total Errors \[\]$'
    $lifeCol=Find-Column $rows '^Drive Remaining Life \[%\]$';$failCol=Find-Column $rows '^Drive Failure(?: \[Yes/No\])?$';$warnCol=Find-Column $rows '^Drive Warning(?: \[Yes/No\])?$';$diskCol=Find-Column $rows '^Total Activity \[%\]$'
    $thermalCols=Find-Columns $rows '(?i)Thermal Throttling|Critical Temperature|PROCHOT';$limitCols=Find-Columns $rows '(?i)^GT Limit Reasons|^GT: Fuses limit|^Ring Limit Reasons|^RING: Max VR Voltage'
    $mem=@(Get-Series $rows $memCol);$avail=@(Get-Series $rows $availCol);$vm=@(Get-Series $rows $vmCol);$pfTotal=@(Get-Series $rows $pfTotalCol);$pfUsed=@(Get-Series $rows $pfUsedCol);$cpu=@(Get-Series $rows $cpuCol);$temp=@(Get-Series $rows $tempCol);$whea=@(Get-Series $rows $wheaCol);$life=@(Get-Series $rows $lifeCol);$disk=@(Get-Series $rows $diskCol)
    $times=@(foreach($r in $rows){$t=Get-SensorTime $r;if($null -ne $t){$t}})
    $gap=$null;if($times.Count -gt 1){$g=@();for($i=1;$i -lt $times.Count;$i++){$d=($times[$i]-$times[$i-1]).TotalSeconds;if($d -ge 0){$g+=$d}};if($g.Count){$gap=($g|Measure-Object -Maximum).Maximum}}
    $thermalYes=0;$limitYes=0;$driveFail=0;$driveWarn=0;$burst=0;$firstBurst=$null
    foreach($r in $rows){
        $hit=$false;foreach($c in $thermalCols){if([string]$r.$c -match '^(?i:Yes|True|1)$'){$hit=$true;break}};if($hit){$thermalYes++}
        $hit=$false;foreach($c in $limitCols){if([string]$r.$c -match '^(?i:Yes|True|1)$'){$hit=$true;break}};if($hit){$limitYes++}
        if($failCol -and [string]$r.$failCol -match '^(?i:Yes|True|1)$'){$driveFail++};if($warnCol -and [string]$r.$warnCol -match '^(?i:Yes|True|1)$'){$driveWarn++}
        if($memCol -and $cpuCol -and $diskCol){$m=ConvertTo-Number $r.$memCol;$c=ConvertTo-Number $r.$cpuCol;$d=ConvertTo-Number $r.$diskCol;if($null -ne $m -and $null -ne $c -and $null -ne $d -and $m -ge 90 -and $c -ge 95 -and $d -ge 50){$burst++;if($null -eq $firstBurst){$firstBurst=Get-SensorTime $r}}}
    }
    $s=[pscustomobject][ordered]@{
        SampleCount=$times.Count;Start=if($times.Count){$times[0].ToString('o')}else{$null};End=if($times.Count){$times[-1].ToString('o')}else{$null};DurationMinutes=if($times.Count -gt 1){[math]::Round(($times[-1]-$times[0]).TotalMinutes,1)}else{$null};MaxSampleGapSeconds=if($null -ne $gap){[math]::Round($gap,3)}else{$null}
        PhysicalMemoryLoadMedianPct=if($mem.Count){[math]::Round((Get-Percentile $mem 50),1)}else{$null};PhysicalMemoryLoadP95Pct=if($mem.Count){[math]::Round((Get-Percentile $mem 95),1)}else{$null};PhysicalMemoryLoadMaxPct=if($mem.Count){[math]::Round(($mem|Measure-Object -Maximum).Maximum,1)}else{$null};PhysicalMemoryAvailableMinMB=if($avail.Count){[math]::Round(($avail|Measure-Object -Minimum).Minimum,0)}else{$null}
        VirtualMemoryLoadMaxPct=if($vm.Count){[math]::Round(($vm|Measure-Object -Maximum).Maximum,1)}else{$null};PageFileTotalMaxMB=if($pfTotal.Count){[math]::Round(($pfTotal|Measure-Object -Maximum).Maximum,0)}else{$null};PageFileUsedMaxMB=if($pfUsed.Count){[math]::Round(($pfUsed|Measure-Object -Maximum).Maximum,0)}else{$null};CpuUsageP95Pct=if($cpu.Count){[math]::Round((Get-Percentile $cpu 95),1)}else{$null};CpuUsageMaxPct=if($cpu.Count){[math]::Round(($cpu|Measure-Object -Maximum).Maximum,1)}else{$null};CpuPackageTempMaxC=if($temp.Count){[math]::Round(($temp|Measure-Object -Maximum).Maximum,1)}else{$null}
        ThermalThrottleSampleCount=$thermalYes;WheaTotalErrorsMax=if($whea.Count){[math]::Round(($whea|Measure-Object -Maximum).Maximum,0)}else{$null};DriveRemainingLifeMinPct=if($life.Count){[math]::Round(($life|Measure-Object -Minimum).Minimum,1)}else{$null};DriveFailureSampleCount=$driveFail;DriveWarningSampleCount=$driveWarn;DiskActivityMaxPct=if($disk.Count){[math]::Round(($disk|Measure-Object -Maximum).Maximum,1)}else{$null};GpuRingLimitSampleCount=$limitYes;CombinedWorkloadBurstCount=$burst;FirstCombinedWorkloadBurst=if($null -ne $firstBurst){$firstBurst.ToString('o')}else{$null}
    }
    $f=New-Object Collections.Generic.List[object]
    if($mem.Count -and (($s.PhysicalMemoryLoadMedianPct -ge 80) -or ($s.PhysicalMemoryAvailableMinMB -lt 512) -or ($s.PhysicalMemoryLoadMaxPct -ge 90))){$sev=if(($s.PhysicalMemoryLoadP95Pct -ge 90) -or ($s.PhysicalMemoryAvailableMinMB -lt 256)){'High'}else{'Medium'};$f.Add((New-TelemetryFinding 'sensor-sustained-memory-pressure' $sev 'High' 'Sensor capture shows sustained physical-memory pressure' "Median RAM load=$($s.PhysicalMemoryLoadMedianPct)%; P95=$($s.PhysicalMemoryLoadP95Pct)%; max=$($s.PhysicalMemoryLoadMaxPct)%; minimum available=$($s.PhysicalMemoryAvailableMinMB) MB." 'This supports paging pressure and user-visible stalls. It does not by itself prove the mechanism of a hard reset or total machine lock.' 'Correlate future hangs with RAM/pagefile pressure and repeat representative workload with more physical RAM if practical.'))}
    if($temp.Count -or $thermalCols.Count){if($thermalYes -gt 0 -or ($null -ne $s.CpuPackageTempMaxC -and $s.CpuPackageTempMaxC -ge 95)){$f.Add((New-TelemetryFinding 'sensor-thermal-pressure-present' 'High' 'High' 'Sensor capture contains thermal-limit evidence' "CPU package max=$($s.CpuPackageTempMaxC) C; throttle-positive samples=$thermalYes." 'Thermal pressure is present in this interval.' 'Inspect cooling and exact throttle timestamps before unrelated changes.'))}elseif($null -ne $s.CpuPackageTempMaxC){$f.Add((New-TelemetryFinding 'sensor-no-thermal-throttle-evidence' 'Info' 'High' 'No CPU thermal-throttling evidence appears in the sensor capture' "CPU package max=$($s.CpuPackageTempMaxC) C; throttle-positive samples=0." 'This weakens overheating for this captured interval only.' 'Keep thermal failure lower unless a future incident capture shows a temperature/throttle excursion.'))}}
    if($whea.Count){if($s.WheaTotalErrorsMax -gt 0){$f.Add((New-TelemetryFinding 'sensor-whea-errors-present' 'High' 'High' 'HWiNFO reports WHEA hardware errors' "Maximum WHEA Total Errors=$($s.WheaTotalErrorsMax)." 'This raises CPU, memory, PCIe and motherboard priority.' 'Inspect matching WHEA-Logger events.'))}else{$f.Add((New-TelemetryFinding 'sensor-whea-counter-clean' 'Info' 'High' 'HWiNFO WHEA counter remained at zero' 'WHEA Total Errors stayed at 0 for all numeric sensor samples.' 'This is bounded negative evidence for the capture, not a hardware guarantee.' 'Preserve longer captures if the machine fails again.'))}}
    if($failCol -or $warnCol -or $life.Count){if($driveFail -or $driveWarn){$f.Add((New-TelemetryFinding 'sensor-drive-health-warning' 'High' 'High' 'Drive health warning appears in the sensor capture' "Drive Failure samples=$driveFail; Drive Warning samples=$driveWarn; minimum remaining life=$($s.DriveRemainingLifeMinPct)%." 'Storage should move up the suspect order.' 'Run vendor/UEFI storage diagnostics and preserve SMART data.'))}else{$f.Add((New-TelemetryFinding 'sensor-drive-health-reassuring' 'Info' 'Medium' 'Sensor drive-health flags are reassuring' "Drive Failure samples=0; Drive Warning samples=0; minimum remaining life=$($s.DriveRemainingLifeMinPct)%." 'This weakens a straightforward failing-drive theory but cannot rule out intermittent faults.' 'Keep storage lower unless new timeouts, SMART changes or diagnostic failures appear.'))}}
    if($null -ne $gap){if($gap -le 5){$f.Add((New-TelemetryFinding 'sensor-capture-continuous' 'Info' 'High' 'Sensor sampling remained continuous' "Maximum sample gap=$($s.MaxSampleGapSeconds) seconds across $($s.SampleCount) samples." 'No long logger pause is visible; a hidden freeze during this exact capture is unlikely.' 'Use the same logging method across the next incident window.'))}elseif($gap -gt 10){$f.Add((New-TelemetryFinding 'sensor-capture-gap' 'Medium' 'Medium' 'Sensor capture contains a significant sampling gap' "Maximum sample gap=$($s.MaxSampleGapSeconds) seconds." 'A gap can reflect a stall, sleep or logger interruption.' 'Correlate the gap with events and user-observed timing.'))}}
    if($limitYes -gt 0 -and $thermalYes -eq 0){$f.Add((New-TelemetryFinding 'sensor-transient-gpu-ring-limits' 'Low' 'Medium' 'Transient GPU/ring limit reasons occurred without thermal throttling' "GT/ring limit-positive samples=$limitYes; thermal-positive samples=0." 'These can occur during normal power management and are a lead, not a GPU-failure diagnosis.' 'Elevate only if future failures align with the same flags or graphics errors.'))}
    if($burst -gt 0){$f.Add((New-TelemetryFinding 'sensor-combined-workload-burst' 'Low' 'High' 'A combined CPU, memory and disk workload burst was captured' "CPU>=95%, RAM>=90%, disk>=50% samples=$burst; first=$($s.FirstCombinedWorkloadBurst)." 'This is a real stress point; continuous sampling means it was not a captured hard freeze.' 'Add process-level capture around future bursts.'))}
    [pscustomobject][ordered]@{Available=$true;SourceFile=$file[0].Name;Summary=$s;Findings=@($f)}
}

function Get-PowerTelemetry {
    param([string]$EvidencePath)
    $file=@(Get-ChildItem -LiteralPath $EvidencePath -File -ErrorAction SilentlyContinue|Where-Object{$_.Name -match '(?i)^(systempower|sleepstudy)-report.*\.html$'}|Sort-Object LastWriteTime -Descending|Select-Object -First 1)
    if(-not $file.Count){return [pscustomobject]@{Available=$false;SourceFile=$null;Summary=$null;Findings=@()}}
    $html=Get-Content -LiteralPath $file[0].FullName -Raw;$m=[regex]::Match($html,'(?s)var\s+LocalSprData\s*=\s*(\{.*?\});\s*(?:var\s+|</script>)')
    if(-not $m.Success){return [pscustomobject]@{Available=$false;SourceFile=$file[0].Name;Summary=$null;Findings=@()}}
    $json=[regex]::Replace($m.Groups[1].Value,":\s*'([^']*)'",': "$1"');try{$data=$json|ConvertFrom-Json -ErrorAction Stop}catch{return [pscustomobject]@{Available=$false;SourceFile=$file[0].Name;Summary=$null;Findings=@()}}
    $ri=$data.ReportInformation;$start=[datetime]::Parse([string]$ri.ReportStartTime).ToUniversalTime();$scan=[datetime]::Parse([string]$ri.ScanTime).ToUniversalTime();$ab=@();$bug=@();$stale=0
    foreach($x in @($data.ScenarioInstances)){if([int]$x.Type -notin @(9,10)){continue};$t=[datetime]::Parse([string]$x.EntryTimestamp).ToUniversalTime();if($t -lt $start -or $t -gt $scan){$stale++;continue};if([int]$x.Type -eq 9){$ab+=$x}else{$bug+=$x}}
    $s=[pscustomobject][ordered]@{ReportStartUtc=$start.ToString('o');ScanTimeUtc=$scan.ToString('o');UtcOffsetMinutes=[int]$ri.UtcOffset;InWindowAbnormalShutdownCount=$ab.Count;InWindowBugcheckCount=$bug.Count;OutOfWindowFailureRecordCount=$stale;LatestAbnormalShutdownLocal=$null;LatestAbnormalShutdownOnAc=$null;LatestBugcheckLocal=$null;LatestBugcheckCode=$null}
    if($ab.Count){$x=@($ab|Sort-Object EntryTimestamp|Select-Object -Last 1)[0];$s.LatestAbnormalShutdownLocal=[string]$x.EntryTimestampLocal;$s.LatestAbnormalShutdownOnAc=[bool]$x.OnAc}
    if($bug.Count){$x=@($bug|Sort-Object EntryTimestamp|Select-Object -Last 1)[0];$s.LatestBugcheckLocal=[string]$x.EntryTimestampLocal;if($null -ne $x.PSObject.Properties['Metadata']){foreach($v in @($x.Metadata.Values)){if([string]$v.Key -eq 'EventLog.BugcheckCode'){$s.LatestBugcheckCode=[string]$v.Value;break}}}}
    $f=New-Object Collections.Generic.List[object]
    if($ab.Count){$power=if($s.LatestAbnormalShutdownOnAc){'AC'}else{'battery'};$f.Add((New-TelemetryFinding 'power-report-abnormal-shutdown' 'Medium' 'High' 'System power report confirms an abnormal shutdown in the report window' "In-window abnormal shutdowns=$($ab.Count); latest=$($s.LatestAbnormalShutdownLocal); power source=$power." 'This precisely confirms an unclean incident boundary; it records the outcome rather than proving cause.' 'Correlate with final pre-incident System events and any sensor/ETW capture.'))}
    if($bug.Count){$f.Add((New-TelemetryFinding 'power-report-bugcheck' 'High' 'High' 'System power report contains an in-window bugcheck' "In-window bugchecks=$($bug.Count); latest=$($s.LatestBugcheckLocal); code=$($s.LatestBugcheckCode)." 'A true bugcheck provides a stronger diagnostic path than a generic reset.' 'Preserve and analyse the matching dump.'))}
    if($stale -gt 0){$f.Add((New-TelemetryFinding 'power-report-stale-failure-records' 'Info' 'High' 'Power report contains failure records outside its declared report window' "Failure records outside $($ri.ReportStartTime) to $($ri.ScanTime): $stale." 'Historical, cloned-image or clock-corrupted records can contaminate naive crash counts; Crash Doctor excludes them.' 'Use the report window and current-machine timestamps as hard boundaries.'))}
    [pscustomobject][ordered]@{Available=$true;SourceFile=$file[0].Name;Summary=$s;Findings=@($f)}
}

function Invoke-CrashDoctorTelemetryAnalysis {
    [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$EvidencePath)
    if(-not(Test-Path -LiteralPath $EvidencePath -PathType Container)){throw "Evidence path does not exist or is not a directory: $EvidencePath"}
    $sensor=Get-SensorTelemetry $EvidencePath;$power=Get-PowerTelemetry $EvidencePath
    [pscustomobject][ordered]@{Available=($sensor.Available -or $power.Available);Sensor=$sensor;Power=$power;Findings=@($sensor.Findings)+@($power.Findings)}
}

function Add-CrashDoctorTelemetryToReport {
    [CmdletBinding()]param([Parameter(Mandatory=$true)]$Report,[Parameter(Mandatory=$true)]$Telemetry)
    $Report|Add-Member -NotePropertyName Telemetry -NotePropertyValue ([pscustomobject]@{Sensor=$Telemetry.Sensor;Power=$Telemetry.Power}) -Force
    if(@($Telemetry.Findings).Count){$order=@{Critical=0;High=1;Medium=2;Low=3;Info=4};$Report.Findings=@(@($Report.Findings)+@($Telemetry.Findings)|Sort-Object @{Expression={$order[$_.Severity]}},@{Expression={$_.Id}})}
    $Report
}

function ConvertTo-CrashDoctorTelemetryMarkdownSection {
    [CmdletBinding()]param([Parameter(Mandatory=$true)]$Telemetry)
    if(-not $Telemetry.Available){return ''};$l=New-Object Collections.Generic.List[string];$l.Add('## Telemetry summary');$l.Add('')
    if($Telemetry.Sensor.Available){$s=$Telemetry.Sensor.Summary;$l.Add("Sensor source: ``$($Telemetry.Sensor.SourceFile)``");$l.Add('');$l.Add('| Metric | Value |');$l.Add('|---|---:|');$l.Add("| Samples | $($s.SampleCount) |");$l.Add("| Duration (min) | $($s.DurationMinutes) |");$l.Add("| Maximum sample gap (s) | $($s.MaxSampleGapSeconds) |");$l.Add("| RAM load median / P95 / max | $($s.PhysicalMemoryLoadMedianPct)% / $($s.PhysicalMemoryLoadP95Pct)% / $($s.PhysicalMemoryLoadMaxPct)% |");$l.Add("| Minimum physical RAM available | $($s.PhysicalMemoryAvailableMinMB) MB |");$l.Add("| CPU usage P95 / max | $($s.CpuUsageP95Pct)% / $($s.CpuUsageMaxPct)% |");$l.Add("| CPU package max | $($s.CpuPackageTempMaxC) C |");$l.Add("| Thermal-throttle-positive samples | $($s.ThermalThrottleSampleCount) |");$l.Add("| WHEA total errors max | $($s.WheaTotalErrorsMax) |");$l.Add("| Drive remaining life min | $($s.DriveRemainingLifeMinPct)% |");$l.Add('')}
    if($Telemetry.Power.Available){$p=$Telemetry.Power.Summary;$l.Add("Power-report source: ``$($Telemetry.Power.SourceFile)``");$l.Add('');$l.Add("- In-window abnormal shutdowns: **$($p.InWindowAbnormalShutdownCount)**");$l.Add("- In-window bugchecks: **$($p.InWindowBugcheckCount)**");$l.Add("- Out-of-window failure records ignored: **$($p.OutOfWindowFailureRecordCount)**");if($p.LatestAbnormalShutdownLocal){$l.Add("- Latest abnormal shutdown: **$($p.LatestAbnormalShutdownLocal)**")};$l.Add('')}
    $l -join [Environment]::NewLine
}

Export-ModuleMember -Function Invoke-CrashDoctorTelemetryAnalysis,Add-CrashDoctorTelemetryToReport,ConvertTo-CrashDoctorTelemetryMarkdownSection
