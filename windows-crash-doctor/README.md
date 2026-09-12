# Windows Crash Doctor

A small, dependency-free PowerShell diagnostic engine for evidence collected by this repository.

It is intentionally **evidence-first**: it reports what the supplied logs support, distinguishes current-machine state from inherited history, and avoids turning correlations into root-cause claims.

## Quick start

First collect a snapshot from an elevated PowerShell:

```powershell
.\scripts\collect-diagnostics.ps1
```

Then analyse the generated folder:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath "$env:USERPROFILE\Desktop\HPProBook-YYYYMMDD-HHMMSS"
```

Two files are written into the evidence folder by default:

- `crash-doctor-report.md` — human-readable findings;
- `crash-doctor-report.json` — machine-readable findings for later tooling.

To keep the report elsewhere:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath C:\Evidence\HPProBook-20260912-160000 `
  -OutputDirectory C:\Evidence\Reports
```

## What it currently detects

The first rule set covers the evidence patterns that mattered in this investigation:

- firmware-class Code 10 / `CM_PROB_FAILED_START`;
- current Firmware-class `Status: OK` as useful post-change baseline evidence;
- Sysprep/respecialised images and retained non-present-device state;
- Intel XTU component presence;
- Conexant OEM audio-stack presence;
- active BitLocker conversion as context;
- hibernation/Fast Startup disabled state;
- pagefile/crash-dump capture risk;
- storage reliability counters;
- WHEA references;
- Kernel-Power Event 41;
- volmgr Event 161.

Each finding contains severity, confidence, exact evidence, a deliberately bounded interpretation and the next diagnostic step.

The tool does **not** automatically flash firmware, remove drivers, change pagefile settings, decrypt BitLocker, uninstall XTU or alter power policy.

## Why no automatic remediation?

This repository is investigating intermittent hard hangs. Changing several variables together destroys evidence. Crash Doctor therefore stays read-only and produces a decision report rather than trying to “fix everything”.

Remediation should remain a separate, explicit action after the evidence has been preserved.

## Input contract

Crash Doctor consumes the text files produced by `scripts/collect-diagnostics.ps1`. Missing files reduce coverage but do not make the analysis fail. The report states exactly which expected inputs were present.

Binary `.evtx` files are preserved by the collector for deeper manual analysis, but the current rule engine intentionally reads the text exports first so it remains dependency-free. The collector also records OS/boot time, published drivers and a focused system-driver view so post-change snapshots can prove what is actually loaded.

## Testing

Run:

```powershell
.\windows-crash-doctor\tests\self-test.ps1 -RepositoryMode
```

The self-test creates both abnormal and quiet synthetic fixtures, confirms the important rules fire without high-severity false positives on the quiet fixture, exercises Markdown/JSON output, and runs the public-evidence secret guard.

GitHub Actions runs the same self-test on `windows-latest`.

## Safety

This tool can process logs containing serial numbers, account names, MAC addresses and other device identifiers. Generated reports should still be reviewed before being published.

The repository-level guard scans text files for BitLocker-style 48-digit recovery passwords, but it is **not** a complete secret scanner. See [`../SECURITY_NOTICE.md`](../SECURITY_NOTICE.md).

## Design principles

- Observed evidence and interpretation are separate fields.
- Absence of a log event is not treated as proof of health.
- Event 41 is aftermath evidence, not a cause.
- A reused Windows image is a confounder, not automatically the root cause.
- Firmware Code 10 is an abnormal state, not automatic proof of an SMI/SMM hang.
- One major change at a time.
- All diagnostic outputs are reproducible from a named snapshot folder.
