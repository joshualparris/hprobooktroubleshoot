# HP ProBook 11 G2 hard-freeze investigation + Windows Crash Doctor

This repository serves two related purposes:

1. preserve an evidence-driven investigation of an HP ProBook 11 G2 that hard-freezes; and
2. develop **Windows Crash Doctor**, a reusable Windows crash/hang triage tool grown from that investigation.

The core rule is simple: keep **observation**, **current-machine telemetry**, **inherited image history**, **interpretation** and **causality** separate. Change one major variable at a time.

## Project status

**Current `main`:**
- reproducible Windows diagnostic collector;
- read-only Crash Doctor snapshot analyser;
- Markdown + JSON reports;
- synthetic Windows regression tests;
- public-evidence/BitLocker recovery-key guard;
- one-command installer plus desktop double-click launcher;
- documented HP ProBook evidence and controlled test plan.

**Not yet implemented on `main`:**
- native dump parsing and symbol resolution;
- ETW/WPR-style tracing;
- trigger-based process dump capture;
- persistent incident database/deduplication;
- graphical timeline;
- remote retracing/reporting integrations.

Those gaps are now tracked individually in the **[100-item Windows Crash Doctor roadmap](docs/ROADMAP_100.md)**, derived from a benchmark against ten established diagnostic tools.

## Easiest install on the ProBook

Open ordinary PowerShell and paste this single line:

```powershell
$p="$env:TEMP\Install-WindowsCrashDoctor.ps1"; Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/joshualparris/hprobooktroubleshoot/main/scripts/Install-WindowsCrashDoctor.ps1" -OutFile $p; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p
```

The installer requests Administrator rights through the normal UAC prompt, downloads the current `main` build, installs it under `%LOCALAPPDATA%\WindowsCrashDoctor\App`, creates **Windows Crash Doctor.cmd** on the Desktop, runs the built-in regression/integration self-tests, then immediately performs the first real diagnostic collection and analysis.

For a double-click install instead, download [`INSTALL-WINDOWS-CRASH-DOCTOR.cmd`](INSTALL-WINDOWS-CRASH-DOCTOR.cmd) and run it. After installation, double-click **Windows Crash Doctor.cmd** on the Desktop whenever you want a fresh diagnostic run.

Each one-click run creates a timestamped folder under **Windows Crash Doctor Results** on the Desktop, runs the self-tests, collects current machine evidence, generates `crash-doctor-report.md` and `crash-doctor-report.json`, records optional-provider status, then opens the result folder and report.

## Manual quick start

Open an elevated Windows PowerShell prompt in the repository.

### 1. Collect a snapshot

```powershell
.\scripts\collect-diagnostics.ps1
```

The collector creates a timestamped `HPProBook-*` folder on the Desktop by default. It is designed to collect evidence, not change system settings.

### 2. Analyse it

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath "$env:USERPROFILE\Desktop\HPProBook-YYYYMMDD-HHMMSS"
```

Crash Doctor writes:

- `crash-doctor-report.md` — human-readable findings;
- `crash-doctor-report.json` — machine-readable output.

### 3. Run the regression test

```powershell
.\windows-crash-doctor\tests\self-test.ps1 -RepositoryMode
```

## Windows Crash Doctor today

The current rule engine understands evidence relevant to this case, including:

- firmware-class failed-start / Code 10 state;
- current firmware resource state;
- Sysprep/generalised/reused-image history;
- retained non-present devices;
- Intel XTU and Conexant stack presence;
- BitLocker conversion context;
- hibernation/Fast Startup state;
- pagefile/crash-dump capture readiness;
- Windows storage reliability counters;
- WHEA references;
- Kernel-Power Event 41;
- volmgr Event 161.

Each finding keeps **severity**, **confidence**, **evidence**, **interpretation** and **next step** separate.

It does **not** silently flash firmware, remove drivers, disable security, change BitLocker, alter pagefile/dump policy or upload private diagnostic data.

## Documentation

| Document | Purpose |
|---|---|
| [`docs/README.md`](docs/README.md) | Documentation map and authority rules |
| [`windows-crash-doctor/README.md`](windows-crash-doctor/README.md) | Current Crash Doctor usage and behaviour |
| [`docs/WINDOWS_CRASH_DOCTOR_PLAN.md`](docs/WINDOWS_CRASH_DOCTOR_PLAN.md) | Architecture and product design |
| [`docs/COMPARABLE_TOOLS_RESEARCH.md`](docs/COMPARABLE_TOOLS_RESEARCH.md) | Ten-tool benchmark and research sources |
| [`docs/ROADMAP_100.md`](docs/ROADMAP_100.md) | Canonical 100-item upgrade backlog |
| [`analysis/STATUS.md`](analysis/STATUS.md) | Current ProBook operational status |
| [`analysis/TEST_PLAN.md`](analysis/TEST_PLAN.md) | One-variable-at-a-time ProBook test sequence |
| [`analysis/MASTER_ANALYSIS.md`](analysis/MASTER_ANALYSIS.md) | Detailed investigation reasoning |
| [`evidence/README.md`](evidence/README.md) | Evidence provenance/redaction workflow |
| [`SECURITY_NOTICE.md`](SECURITY_NOTICE.md) | Security and privacy requirements |

## HP ProBook case

### Machine

- HP ProBook 11 G2 / board 818F
- Intel Core i3-6100U
- Intel HD Graphics 520
- 4 GB DDR4-2133
- Samsung 128 GB SATA SSD
- BIOS N92 01.04 dated 2 November 2016
- Windows 11 Pro 24H2 on an unsupported CPU/TPM configuration

### Symptom

The machine has produced whole-system hard hangs with the display still lit/frozen and no useful recorded BSOD. Recovery required holding the power button. The current September incidents clustered soon after S4/Fast Startup-style resume.

### Strongest established facts

- HP quick memory testing and SSD SMART/Short DST passed.
- Current Windows storage counters do not provide strong evidence of straightforward SSD failure.
- Physical BIOS is old.
- Windows recorded an HP N92 firmware device in a failed-start/Code 10 state.
- SetupAPI proves the delivered Windows image was Sysprep-respecialised and retained substantial previous-hardware state.
- Intel XTU components are present; a non-default tuning state has not yet been proven.
- Hibernation/Fast Startup was disabled as a controlled A/B test.
- Existing `volmgr 161` failures cannot be treated as storage proof while dump/pagefile configuration is inadequate.

The current working problem family remains **firmware/power-state/low-level OEM-driver interaction on a reused refurb Windows image**. That is a hypothesis family, not a confirmed root cause.

## Current ProBook test order

1. Capture current post-change state.
2. Measure stability with hibernation/Fast Startup disabled.
3. Inspect XTU without changing values.
4. Make crash-dump capture trustworthy.
5. Run MemTest86 if instability persists.
6. Update BIOS through HP's official N92 path once recovery-key safety and power are assured.
7. Isolate the supplied Windows image with a clean OS/live environment if required.
8. If updated firmware + clean OS + known-good RAM still freeze, use the return/warranty path.

See [`analysis/TEST_PLAN.md`](analysis/TEST_PLAN.md) before changing anything.

## Repository layout

```text
analysis/                 ProBook case reasoning, status and controlled test plan
conversation/             conversation-archive provenance notes
docs/                     product architecture, research and roadmap
evidence/                 evidence workflow and SHA-256 manifests
raw/                      explicitly documented raw/archive boundary
scripts/                  collection, installation, hashing and public-evidence guard
windows-crash-doctor/     current Crash Doctor engine, CLI, runner and tests
INSTALL-WINDOWS-CRASH-DOCTOR.cmd  double-click bootstrap installer
SECURITY_NOTICE.md        privacy/security rules
```

## Evidence and privacy

Raw logs are private by default. EVTX, ETL, WER files, dumps, `msinfo32`, SetupAPI, screenshots and memory dumps can contain usernames, hardware identifiers, network details, application state or secrets.

Never commit a BitLocker recovery password. Review [`SECURITY_NOTICE.md`](SECURITY_NOTICE.md) before publishing diagnostic artefacts.
