# HP ProBook investigation status

Snapshot date: **12 September 2026**

This is the short operational source of truth for the ProBook case. Detailed reasoning remains in [`MASTER_ANALYSIS.md`](MASTER_ANALYSIS.md); the 12 September forensic update is in [`FORENSIC_UPDATE_2026-09-12.md`](FORENSIC_UPDATE_2026-09-12.md). Product development belongs under [`../docs/`](../docs/README.md).

## Current machine state

| Area | State | Evidence / next check |
|---|---|---|
| Hard-freeze / forced-shutdown symptom | Confirmed | Whole-system hang history; System Power Report now confirms an abnormal shutdown at **14:15:59 on 12 Sep 2026**, on battery |
| S4 / Fast Startup correlation | Strong, not causal proof | Current September incidents cluster shortly after hibernate/hybrid-shutdown resume; preserve the no-Fast-Startup A/B window |
| Fast Startup / hibernation | Disabled for controlled A/B test | Preserve stable hours and shutdown/start cycles before another major change |
| HP N92 firmware resource | **Fresh failed-start state confirmed** | New MSINFO32 capture shows **HP N92 System Firmware 01.60** cannot start; physical BIOS remains 01.04 |
| Physical BIOS | Very old | N92 01.04 from 2016; HP later published N92 01.60 for this platform |
| Windows/platform support | Compatibility risk | Windows 11 24H2 is running on a 6th-gen i3-6100U; Microsoft’s supported Windows 11 Intel list begins with newer Core generations. Unsupported status is a risk factor, not proof of the freezes |
| Reused/generalised Windows image | Confirmed | Sysprep Respecialize, large non-present-device history and stale/future-dated event/power records |
| Sensor capture | Reassuring for heat/WHEA; concerning for RAM pressure | ~46 min HWiNFO capture: CPU package ~38–52 C, no thermal-throttle samples, WHEA counter 0, continuous ~2 s sampling; RAM mostly ~80–86% and peaked >92%, with ~311 MB free at the low point |
| Memory pressure | Confirmed performance stressor | 4 GB installed; MSINFO32 showed only ~330 MB available and the sensor log independently reproduced severe pressure. This can cause paging/stalls but does not prove the hard-reset mechanism |
| Storage | No strong current failure evidence | Sensor drive failure/warning flags stayed clear; remaining-life field ~86%; no convincing incident-time storage fault signature in the supplied logs |
| Battery / power path | Still a hypothesis, not a diagnosis | The 14:15:59 abnormal shutdown happened on battery, but post-reboot battery state remained high and there is no clear battery-collapse signature. Capacity telemetry is internally inconsistent |
| Intel XTU stack | Present | Presence is confirmed; active non-default tuning is not |
| Conexant / OEM stack | Present, low-priority lead | Repeated CxMonSvc polling exists but there is no direct incident-time failure signature in the supplied capture |
| Crash-dump reliability | Weak / needs verification | Pagefile size changed between snapshots and historical volmgr/dump evidence is not sufficient to trust missing dumps yet |
| Privacy of raw logs | Sensitive | Security/audit EVTX includes account data; raw binary evidence must stay out of the public repository unless reviewed/redacted |

## Current working model

The best-supported problem **family** is now:

**firmware / power-state / unsupported-platform interaction on a reused refurb Windows image, with severe 4 GB memory pressure acting as a likely stall amplifier**

This is still **not a confirmed root cause**. The strongest fresh low-level abnormality is the failed HP N92 01.60 firmware resource while the physical BIOS remains at 01.04. The sensor log materially weakens overheating and a simple SSD-failure theory for the captured interval.

## 12 September incident boundary

The Windows System Power Report gives a useful anchor:

- **14:15:59 local:** abnormal shutdown, on battery;
- **14:16:33 local:** new active session after reboot;
- **14:33:14 local:** active session changes to AC power;
- **14:56:16 local:** report generated;
- **15:07:27–15:53:24 local:** later HWiNFO sensor capture remains continuous and does not contain a hard freeze.

Do not treat a future-dated 2042 bugcheck record found in the power-report data as a current crash. It lies outside the report’s declared seven-day window and is now explicitly filtered by Windows Crash Doctor.

## What to capture now

From an elevated PowerShell prompt:

```powershell
.\scripts\collect-diagnostics.ps1
```

If an HWiNFO CSV has already been recorded:

```powershell
.\scripts\collect-diagnostics.ps1 `
  -SensorCsvPath "$env:USERPROFILE\Desktop\sensors.CSV"
```

Then analyse the new folder:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath "$env:USERPROFILE\Desktop\HPProBook-YYYYMMDD-HHMMSS"
```

Keep the collector folder even if Crash Doctor produces no high-severity finding. Missing evidence is not proof of health.

## Do not stack changes

During a controlled stability window, do not simultaneously change BIOS, XTU, audio, storage drivers, RAM and power configuration. If the machine becomes stable after six changes, the result does not identify which variable mattered.

## Stability milestones

Treat stability as progressively stronger evidence:

- 30 minutes awake;
- 2+ hours of normal use;
- multiple cold boots;
- multiple shutdown/start cycles with Fast Startup disabled;
- several sleep/wake cycles if S3 is available;
- 24+ hours of representative use.

A new freeze ends the current stage. Record:
- exact/approximate time;
- last visible screen and task;
- whether the machine resumed recently;
- AC/battery state;
- attached devices;
- the first post-reboot collector snapshot;
- the HWiNFO CSV if logging was active.

## Next decision sequence

1. Preserve this 12 September evidence set and continue the no-hibernation/Fast-Startup stability window.
2. Make pagefile/crash-dump capture trustworthy so a future failure has a chance of producing useful kernel evidence.
3. Inspect XTU settings without changing values and record whether any offset/custom profile is active.
4. With BitLocker recovery-key safety, reliable AC power and rollback planning in place, update the physical HP N92 BIOS using HP’s official method rather than relying on the failed Windows firmware device path.
5. After the BIOS change, confirm both the physical BIOS version and the Firmware-class PnP device state, then run a fresh collector snapshot.
6. Repeat representative use with HWiNFO logging. A clean run should again show whether heat/WHEA stay quiet and whether memory pressure remains extreme.
7. If instability persists, test memory properly and consider the practical 4 GB RAM limitation separately from the crash mechanism.
8. If updated firmware + reliable dump capture + known-good RAM still freeze, isolate the supplied Windows image with a clean supported OS/live environment where practical.
9. If low-level freezes survive firmware, RAM and clean-OS isolation, use the warranty/return path instead of indefinite software tweaking.

See [`TEST_PLAN.md`](TEST_PLAN.md) for the staged procedure.

## Tooling status

Windows Crash Doctor now analyses its normal collector snapshot **plus optional HWiNFO sensor CSVs and Windows System Power Reports**. The telemetry layer detects sustained memory pressure, thermal/WHEA state, drive-health flags, sampling gaps, combined workload bursts and in-window abnormal shutdowns while excluding stale/future failure records.

The broader product roadmap — dump symbols, ETW, proactive capture, WER ingestion, incident history and 100 concrete upgrades — remains in [`../docs/ROADMAP_100.md`](../docs/ROADMAP_100.md).
