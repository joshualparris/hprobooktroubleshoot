# HP ProBook 11 G2 hard-freeze investigation

Evidence-driven troubleshooting of an HP ProBook 11 G2 that began hard-freezing immediately after purchase in September 2026.

The goal is to separate **observed evidence**, **current-machine telemetry**, **inherited Windows-image history** and **mechanism hypotheses**, then change one major variable at a time.

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
2. Windows storage reliability counters do not currently show convincing SSD failure evidence.
3. Physical BIOS is still N92 01.04 from 2016.
4. Windows recorded an `HP N92 System Firmware 01.60` device in Code 10 / failed-start state. A later transcript reports that package was removed and the firmware resource returned to OK, but that post-removal state still needs an independent capture.
5. SetupAPI proves the delivered Windows installation was Sysprep-respecialised on this ProBook and retained 154 non-present devices, including previous HP hardware and multiple prior storage devices.
6. Intel XTU components are present and started on the current installation; a non-default voltage/tuning state has **not** yet been proven.
7. `powercfg /h off` has disabled hibernation and Fast Startup for the current controlled A/B test.
8. `volmgr 161` dump failures are not good evidence of storage failure while pagefile/dump configuration is inadequate.

## Current working model

The best-supported problem family is **firmware / power-state / low-level OEM-driver interaction on a reused refurb Windows image**.

That is deliberately broader than saying “the failed firmware capsule is the root cause”. The capsule abnormality is real, but the specific SMI/SMM-hang mechanism remains a hypothesis rather than a logged fact.

See [`analysis/MASTER_ANALYSIS.md`](analysis/MASTER_ANALYSIS.md) for the detailed reasoning and [`analysis/STATUS.md`](analysis/STATUS.md) for the short operational view.

## Current test sequence

1. Capture current post-change state.
2. Measure stability with hibernation/Fast Startup disabled.
3. Inspect XTU settings without changing them.
4. Make crash-dump capture trustworthy.
5. Run MemTest86 if instability persists.
6. Update BIOS directly using HP's official N92 path once recovery-key safety and power are assured.
7. Isolate the delivered Windows image with a clean OS/live environment if needed.
8. If updated firmware + clean OS + known-good RAM still hard-freeze, use the return/warranty path.

The detailed staged plan is in [`analysis/TEST_PLAN.md`](analysis/TEST_PLAN.md).

## Windows Crash Doctor

This repository now contains a reusable Windows hard-freeze diagnostic app built from the ProBook investigation.

Windows Crash Doctor adds:

- a persistent pre-freeze canary;
- automatic abnormal-reboot incident reconstruction;
- correlated Windows event timelines;
- crash-dump/pagefile readiness checks;
- driver, firmware and reused-image diagnostics;
- hardware/storage evidence;
- explainable hypothesis ranking;
- one-variable-at-a-time A/B experiment tracking;
- a staged remediation/verification plan;
- an HP ProBook 11 G2 machine profile;
- deterministic offline analysis of previously collected snapshots;
- Windows CI plus an installable ZIP build.

Install from the extracted repository in an elevated PowerShell window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-crash-doctor\install.ps1
```

Or download and run the reviewed bootstrap:

```powershell
$u = 'https://raw.githubusercontent.com/joshualparris/hprobooktroubleshoot/main/windows-crash-doctor/bootstrap.ps1'
$p = Join-Path $env:TEMP 'wcd-bootstrap.ps1'
Invoke-WebRequest -UseBasicParsing $u -OutFile $p
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p
```

After installation, a previously collected diagnostic folder can also be analysed offline:

```powershell
& "$env:ProgramFiles\WindowsCrashDoctor\wcd.cmd" snapshot `
  -EvidencePath "$env:USERPROFILE\Desktop\HPProBook-YYYYMMDD-HHMMSS"
```

See [`windows-crash-doctor/README.md`](windows-crash-doctor/README.md) for operation and [`docs/WINDOWS_CRASH_DOCTOR_PLAN.md`](docs/WINDOWS_CRASH_DOCTOR_PLAN.md) for the full architecture and the ten diagnostic improvements.

## Reproducible collection

Run from an elevated PowerShell prompt for the most complete snapshot:

```powershell
.\scripts\collect-diagnostics.ps1
```

The collector writes a timestamped folder on the Desktop by default with hardware, firmware, problem-device, storage, pagefile/dump, BitLocker, power-state, SetupAPI, battery/system-power reports and recent Windows event evidence. It does not deliberately change machine settings.

To hash a private evidence folder and identify duplicates:

```powershell
.\scripts\hash-evidence.ps1 -InputPath .\evidence\raw -OutputCsv .\evidence\manifests\evidence-manifest.csv
```

The current supplied-file inventory is committed at [`evidence/manifests/evidence-manifest.csv`](evidence/manifests/evidence-manifest.csv). It records filenames, sizes, SHA-256 hashes and duplicate groups; the large raw binary originals are not part of this public repo.

Review [`SECURITY_NOTICE.md`](SECURITY_NOTICE.md) before publishing any logs, screenshots or reports.

## Repository layout

```text
analysis/
  MASTER_ANALYSIS.md       detailed evidence synthesis
  STATUS.md                current state and next decision
  HYPOTHESIS_REGISTER.md   evidence for/against candidate causes
  EVIDENCE_TIMELINE.md     current vs inherited-history timeline
  CLAUDE_COMPARISON.md     reconciliation with the other analysis session
  TEST_PLAN.md             staged one-variable-at-a-time test plan
  RAW_EVIDENCE_STATUS.md   what is committed vs archived outside Git

conversation/
  README.md                integrity/archive status for conversation records

evidence/
  README.md                evidence handling and provenance workflow
  manifests/
    evidence-manifest.csv  committed SHA-256 inventory/duplicate mapping
  raw/                     private/unreviewed originals (gitignored)
  extracts/                reviewed/redacted extracts when deliberately added

raw/
  README.md                complete archive names/hashes and upload boundary
  battery-report.html.gz   small directly committed raw-report sample

windows-crash-doctor/
  WindowsCrashDoctor.psm1  live diagnostic/hypothesis engine
  CrashDoctor.psm1         deterministic offline snapshot analyser
  windows-crash-doctor.ps1 unified CLI
  canary.ps1               persistent pre-freeze telemetry
  install.ps1              SYSTEM startup-task installer
  profiles/                machine-specific guidance profiles
  tests/                   Windows regression/self-tests

docs/
  WINDOWS_CRASH_DOCTOR_PLAN.md  architecture + ten improvements

scripts/
  collect-diagnostics.ps1       canonical deep diagnostic snapshot
  hash-evidence.ps1             SHA-256 manifest + duplicate detection
  check-public-evidence.ps1     public-repo recovery-key guard
  package-windows-crash-doctor.ps1  installable ZIP builder

SECURITY_NOTICE.md          public-repository privacy/redaction rules
```

## Important evidence corrections

- Historical `BootAppStatus = 0xC000007B` records do not prove the current September hang was caused by a firmware boot-app failure; the 12 Sep abnormal-shutdown session records `BootAppStatus = 0x0`.
- `volmgr 161` dump-creation failures do not by themselves prove storage wedged; pagefile size/configuration can independently prevent useful dump capture.
- Repeated `manage-bde` readings at 99% over a short interval do not prove BitLocker caused the hangs.
- Battery evidence does not fit a simple power cut; the lit frozen display and forced-power recovery fit a true hang better.
- The reused-image finding is concrete, but image reuse itself is not proof of causality.

## Raw evidence policy

Raw EVTX files, reports, screenshots and conversation exports are **not assumed safe for a public Git repository**. The committed manifest preserves byte-level provenance without requiring those large/private originals to be public. [`raw/README.md`](raw/README.md) records the complete archive names and SHA-256 hashes, while [`analysis/RAW_EVIDENCE_STATUS.md`](analysis/RAW_EVIDENCE_STATUS.md) documents the archive boundary explicitly.

**Never commit the exposed BitLocker recovery password or any replacement recovery key.**
