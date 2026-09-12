# HP ProBook investigation status

Snapshot date: **12 September 2026**

This is the short operational source of truth for the ProBook case. Detailed reasoning remains in [`MASTER_ANALYSIS.md`](MASTER_ANALYSIS.md). Product development belongs under [`../docs/`](../docs/README.md).

## Current machine state

| Area | State | Evidence / next check |
|---|---|---|
| Hard-freeze symptom | Confirmed | Whole-system hang, frozen lit display, forced power-off required |
| S4 / Fast Startup correlation | Strong | Current September incidents occurred within minutes of hybrid-shutdown resume |
| Fast Startup / hibernation | Disabled for controlled A/B test | Preserve stable hours and shutdown/start cycles before another major change |
| HP N92 firmware resource | Previously abnormal | N92 01.60 firmware device recorded Code 10; current state requires fresh independent capture |
| Physical BIOS | Old | N92 01.04 from 2016 |
| Reused/generalised Windows image | Confirmed | Sysprep Respecialize, 154 non-present devices and previous-hardware nodes |
| Intel XTU stack | Present | Presence is confirmed; active non-default tuning is not |
| Samsung SSD | No strong current failure evidence | SMART/DST/reliability evidence is currently reassuring |
| RAM | Not fully cleared | Quick test passed; MemTest86 remains a later isolation step |
| Crash-dump reliability | Weak | Pagefile/dump configuration must be made trustworthy before missing dumps mean much |
| BitLocker | Conversion previously observed at 99% | Track separately; repeated short-interval 99% readings do not prove a stall |

## Current working model

The best-supported problem **family** is:

**firmware / power-state / low-level OEM-driver interaction on a reused refurb Windows image**

This is not a confirmed root cause. The failed firmware resource is real evidence; the mechanism linking it to a hard freeze remains unproven.

## What to capture now

From an elevated PowerShell prompt:

```powershell
.\scripts\collect-diagnostics.ps1
```

Then analyse the new folder:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath "$env:USERPROFILE\Desktop\HPProBook-YYYYMMDD-HHMMSS"
```

Keep the collector folder even if Crash Doctor produces no high-severity finding. Missing evidence is not proof of health.

## Do not stack changes

During a controlled stability window, do not simultaneously change BIOS, XTU, audio, storage drivers and power configuration. If the machine becomes stable after five changes, the result does not identify which variable mattered.

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
- the first post-reboot collector snapshot.

## Next decision sequence

1. Capture current post-change state.
2. Finish the no-hibernation/Fast-Startup stability window.
3. Inspect XTU settings without changing values.
4. Make pagefile/crash capture reliable.
5. Run MemTest86 if instability persists.
6. Update BIOS directly with HP's official N92 method once recovery-key safety and reliable power are assured.
7. If freezes persist, isolate the supplied Windows image with a clean OS/live environment.
8. If updated firmware + clean OS + known-good RAM still freeze, use the warranty/return path instead of indefinite software tweaking.

See [`TEST_PLAN.md`](TEST_PLAN.md) for the staged procedure.

## Tooling status

Windows Crash Doctor currently analyses collector snapshots. The broader product roadmap — dump symbols, ETW, proactive capture, WER ingestion, incident history and 100 concrete upgrades — is tracked in [`../docs/ROADMAP_100.md`](../docs/ROADMAP_100.md).
