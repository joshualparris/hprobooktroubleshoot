# Investigation status

Snapshot date: **12 September 2026**

This file is the short operational view. `MASTER_ANALYSIS.md` contains the detailed reasoning.

## Current state

| Area | State | Evidence / next check |
|---|---|---|
| Hard-freeze symptom | Confirmed | Whole-system hangs with frozen lit display; forced power-off required |
| S4 / Fast Startup correlation | Strong | Both current incidents followed hybrid-shutdown resume within minutes |
| Fast Startup / hibernation | Disabled for A/B test | `powercfg /h off`; preserve duration and resume-cycle count before changing another major variable |
| HP N92 firmware device | Previously abnormal | N92 01.60 firmware device recorded Code 10; reported removed later, but post-removal state still needs independent capture |
| Physical BIOS | Old | N92 01.04 from 2016; direct BIOS update is a later controlled step |
| Reused/generalised Windows image | Confirmed | Sysprep Respecialize + 154 non-present devices + previous hardware nodes |
| Intel XTU stack | Present | Inspect profile/offset without changing values, then decide whether to remove it in a later isolated test |
| Current Samsung SSD | No strong failure evidence | SMART/DST/reliability data currently reassuring |
| RAM | Not fully cleared | Quick test passed; MemTest86 still required if hangs continue |
| Crash-dump reliability | Weak | Pagefile/dump setup should be corrected before treating missing dumps as diagnostic evidence |
| BitLocker | Conversion previously at 99% | Track to completion separately; do not infer causality from repeated 99% readings alone |

## Do not change yet

While a controlled stability window is being measured, avoid stacking changes to BIOS, XTU, audio drivers, storage drivers and power settings. Multiple simultaneous fixes would make a stable result much less informative.

## Success criteria for the current A/B test

A single 30-minute stable run is useful but weak. Record progressively stronger milestones:

- 30 minutes awake without a freeze;
- 2+ hours of normal use;
- multiple cold boots;
- multiple shutdown/start cycles with Fast Startup disabled;
- several sleep/wake cycles if S3 is available;
- at least 24 hours of representative use without another hard freeze.

A new freeze should end the current stage immediately: preserve the time, last visible screen/state, whether the machine had resumed recently, and the new collection output before making another major change.

## Next decision sequence

1. Capture current post-change state with `scripts/collect-baseline.ps1`.
2. Finish the no-hibernation/Fast-Startup stability window.
3. Inspect XTU settings without changing them.
4. Make pagefile/crash capture reliable.
5. Run MemTest86 if instability persists.
6. Update BIOS directly with HP's official N92 method once recovery-key safety and power are assured.
7. If freezes persist, isolate the delivered Windows image with a clean OS/live environment.
8. If updated firmware + clean OS + known-good RAM still freeze, use the return/warranty path rather than continuing indefinite software tweaks.
