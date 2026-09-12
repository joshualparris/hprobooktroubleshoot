# Windows Crash Doctor

A small PowerShell diagnostic engine for evidence collected by this repository.

It is intentionally **evidence-first**: it reports what the supplied logs support, distinguishes current-machine state from inherited history, and avoids turning correlations into root-cause claims.

The core snapshot analyser remains dependency-free. Optional open-source providers can now add deeper sensor, SMART, EVTX, timeline and inventory evidence without copying third-party source or binaries into this repository.

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

## Optional open-source providers

See what Crash Doctor knows about and what is installed:

```powershell
.\windows-crash-doctor\Manage-Integrations.ps1 -Action status
```

The high-value providers currently wired into the app are:

- **LibreHardwareMonitor** — live temperatures, clocks, loads, voltages and other available sensors;
- **smartmontools** — deep `smartctl` storage evidence when already installed;
- **evtx / evtx_dump** — raw EVTX to ordered JSONL/XML conversion;
- **Hayabusa** — opt-in Windows event forensics timeline;
- **osquery** — structured read-only system, driver, service and software inventory;
- **PerfView** — verified download/status support for later manual ETW tracing;
- **Pester** and **PSScriptAnalyzer** — CI regression/static-analysis gates.

Crash Doctor downloads selected official release assets only after an explicit `-Action install`. If GitHub publishes a SHA-256 digest for the release asset it must match before the tool is activated. Third-party binaries stay outside Git under `%LOCALAPPDATA%\WindowsCrashDoctor\Tools` by default.

Example:

```powershell
# Hardware sensor provider
.\windows-crash-doctor\Manage-Integrations.ps1 -Action install -Id librehardwaremonitor
.\windows-crash-doctor\Manage-Integrations.ps1 -Action sensors `
  -DurationMinutes 30 -IntervalSeconds 2 -OutputPath .\sensor-run.jsonl

# Fast EVTX parser
.\windows-crash-doctor\Manage-Integrations.ps1 -Action install -Id evtx
.\windows-crash-doctor\Manage-Integrations.ps1 -Action evtx `
  -Path .\System.evtx -OutputPath .\System.evtx.jsonl
```

The complete reviewed list, licence/risk decisions and commands are documented in [`../docs/OPEN_SOURCE_INTEGRATIONS.md`](../docs/OPEN_SOURCE_INTEGRATIONS.md).

## What the snapshot engine currently detects

The core rule set covers the evidence patterns that mattered in this investigation:

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

The same rule applies to optional integrations: downloading a provider is separate from running it, PerfView capture is never silently started, CHIPSEC is never auto-run, and Memtest86+ remains a manual boot-environment test.

## Input contract

Crash Doctor consumes the text files produced by `scripts/collect-diagnostics.ps1`. Missing files reduce coverage but do not make the analysis fail. The report states exactly which expected inputs were present.

Binary `.evtx` files are preserved by the collector. They can now be converted with the optional `evtx_dump` provider for deeper analysis, while the core rule engine continues to read the collector's text exports first so a normal snapshot remains portable and dependency-free. The collector also records OS/boot time, published drivers and a focused system-driver view so post-change snapshots can prove what is actually loaded.

## Testing

Run the dependency-free regression suites:

```powershell
.\windows-crash-doctor\tests\self-test.ps1 -RepositoryMode
.\windows-crash-doctor\tests\integration-self-test.ps1 -RepositoryMode
```

The first self-test creates both abnormal and quiet synthetic fixtures, confirms the important rules fire without high-severity false positives on the quiet fixture, exercises Markdown/JSON output, and runs the public-evidence secret guard. The integration test validates the provider catalogue and ensures privileged/manual tools cannot be silently installed.

GitHub Actions additionally installs **Pester** and **PSScriptAnalyzer**, runs static-analysis errors as a gate, and executes the Pester integration tests on `windows-latest`.

## Safety

This tool can process logs containing serial numbers, account names, MAC addresses and other device identifiers. Generated reports and integration outputs should still be reviewed before being published.

The repository-level guard scans text files for BitLocker-style 48-digit recovery passwords, but it is **not** a complete secret scanner. See [`../SECURITY_NOTICE.md`](../SECURITY_NOTICE.md).

## Design principles

- Observed evidence and interpretation are separate fields.
- Absence of a log event is not treated as proof of health.
- Event 41 is aftermath evidence, not a cause.
- A reused Windows image is a confounder, not automatically the root cause.
- Firmware Code 10 is an abnormal state, not automatic proof of an SMI/SMM hang.
- Third-party output is evidence, not automatically a root-cause verdict.
- One major change at a time.
- All diagnostic outputs are reproducible from a named snapshot folder.
