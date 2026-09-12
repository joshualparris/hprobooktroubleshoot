# HP ProBook 11 G2 hard-freeze investigation

Evidence-driven troubleshooting of an HP ProBook 11 G2 that began hard-freezing immediately after purchase in September 2026.

The goal is not to tell the most convincing story. It is to separate **observed evidence**, **current-machine telemetry**, **inherited Windows-image history** and **mechanism hypotheses**, then change one major variable at a time.

## Current machine

- HP ProBook 11 G2 / board 818F
- Intel Core i3-6100U, 2C/4T, 2.30 GHz
- Intel HD Graphics 520
- 4 GB SK Hynix HMA451S6AFR8N-TF DDR4-2133, single-channel
- Samsung MZNTY128HDHP-000H1 128 GB SATA SSD
- BIOS N92 Ver. 01.04, 2 Nov 2016
- Windows 11 Pro 24H2 on an unsupported CPU/TPM configuration

## Symptom

The machine has produced genuine whole-system hard hangs with the display still lit/frozen and no recorded BSOD. Recovery required holding the power button. The two current September incidents occurred within minutes of resuming from S4 / Fast Startup-style hybrid shutdown sessions.

## What is established

1. HP quick memory test passed; SSD SMART and Short DST passed.
2. Windows storage reliability counters show no current read/uncorrected-read error evidence and normal SSD temperature.
3. Physical BIOS is still N92 01.04 from 2016.
4. Windows recorded an `HP N92 System Firmware 01.60` device in Code 10 / failed-start state. A later transcript reports that package was removed and the firmware resource returned to OK, but that post-removal state still needs an independent capture.
5. SetupAPI proves the delivered Windows installation was Sysprep-respecialised on this ProBook and retained 154 non-present devices, including previous HP hardware and multiple prior storage devices.
6. Intel XTU components are present and started on the current installation; a non-default voltage/tuning state has **not** yet been proven.
7. Conexant OEM audio services have substantial historical crash noise and participate in resume/power handling, but they are not proven to cause the kernel-level hang.
8. `powercfg /h off` has disabled hibernation and Fast Startup for the current controlled A/B test.
9. `volmgr 161` dump failures are not good evidence of storage failure while pagefile/dump configuration is inadequate.

## Current working model

The best-supported problem family is **firmware / power-state / low-level OEM-driver interaction on a reused refurb Windows image**.

That is deliberately broader than saying “the failed firmware capsule is the root cause”. The capsule abnormality is real, but the specific SMI/SMM-hang mechanism remains a hypothesis rather than a logged fact.

See [`analysis/MASTER_ANALYSIS.md`](analysis/MASTER_ANALYSIS.md) for the full reasoning and [`analysis/STATUS.md`](analysis/STATUS.md) for the short operational view.

## Current test sequence

The investigation follows one-major-variable-at-a-time testing:

1. capture current post-change state;
2. measure stability with hibernation/Fast Startup disabled;
3. inspect XTU settings without changing them;
4. make crash-dump capture trustworthy;
5. run MemTest86 if instability persists;
6. update BIOS directly using HP's official N92 path once recovery-key safety and power are assured;
7. isolate the delivered Windows image with a clean OS/live environment if needed;
8. if updated firmware + clean OS + known-good RAM still hard-freeze, use the return/warranty path.

The detailed decision rules are in [`analysis/TEST_PLAN.md`](analysis/TEST_PLAN.md).

## Reproducible collection

Run from an elevated PowerShell prompt when possible:

```powershell
.\scripts\collect-baseline.ps1
```

This writes a timestamped local `collection-*` directory containing hardware, firmware, problem-device, storage, pagefile/dump, BitLocker, power-state and recent event-log evidence. Those folders are gitignored because raw diagnostics can contain sensitive data.

To hash a private evidence folder and identify duplicates:

```powershell
.\scripts\hash-evidence.ps1 -InputPath .\evidence\raw -OutputCsv .\evidence\manifests\evidence-manifest.csv
```

Review [`SECURITY_NOTICE.md`](SECURITY_NOTICE.md) before publishing any raw logs, screenshots or reports.

## Repository layout

```text
analysis/
  MASTER_ANALYSIS.md       detailed evidence synthesis
  STATUS.md                current state and next decision
  HYPOTHESIS_REGISTER.md   evidence for/against each candidate cause
  EVIDENCE_TIMELINE.md     current vs inherited-history timeline
  CLAUDE_COMPARISON.md     reconciliation with the other analysis session
  TEST_PLAN.md             staged one-variable-at-a-time test plan

evidence/
  README.md                evidence handling and provenance workflow
  raw/                     private/unreviewed originals (gitignored)
  manifests/               generated hashes/manifests when available
  extracts/                reviewed/redacted text extracts when available

scripts/
  collect-baseline.ps1     repeatable non-destructive state capture
  hash-evidence.ps1        SHA-256 manifest + duplicate detection

SECURITY_NOTICE.md          public-repository privacy/redaction rules
```

## Important evidence corrections

- Historical `BootAppStatus = 0xC000007B` records do not prove the current September hang was caused by a firmware boot-app failure; the 12 Sep abnormal-shutdown session records `BootAppStatus = 0x0`.
- `volmgr 161` dump-creation failures do not by themselves prove storage wedged; pagefile size/configuration can independently prevent useful dump capture.
- Repeated `manage-bde` readings at 99% over a short interval do not prove BitLocker caused the hangs.
- Battery evidence does not fit a simple power cut; the lit frozen display and forced-power recovery fit a true hang better.
- The reused-image finding is concrete, but image reuse itself is not proof of causality.

## Raw evidence policy

Raw EVTX files, reports, screenshots and conversation exports are **not assumed to be safe for a public Git repository**. Keep untouched originals privately, hash them, publish only reviewed/redacted derivatives where possible, and preserve provenance in a manifest.

**Never commit the exposed BitLocker recovery password or any replacement recovery key.**
