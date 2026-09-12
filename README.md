# HP ProBook 11 G2 hard-freeze investigation + Windows Crash Doctor

This repository serves two related purposes:

1. preserve an evidence-driven investigation of an HP ProBook 11 G2 that hard-freezes; and
2. develop **Windows Crash Doctor**, a reusable Windows crash/hang triage tool grown from that investigation.

The core rule is simple: keep **observation**, **current-machine telemetry**, **inherited image history**, **interpretation** and **causality** separate. Change one major variable at a time.

## Windows Crash Doctor Desktop

Windows Crash Doctor now has a native Windows desktop front end in `desktop/WindowsCrashDoctor.App`.

The desktop preview includes:

- a polished dashboard with live CPU/RAM/temperature cards;
- one-click **Run Full Diagnosis**;
- ranked evidence cards with severity and recommended next action;
- live diagnostic progress and logs;
- optional 30-minute LibreHardwareMonitor deep sensor capture;
- local diagnostic-run history;
- native `.dmp` / `.mdmp` analysis through the Crash Doctor dump parser;
- open-source provider installation/status;
- privacy-aware diagnostic ZIP export;
- light and dark themes;
- a self-contained `WindowsCrashDoctor.exe` build with the PowerShell engine embedded.

### Download the desktop EXE

The rolling desktop preview release is built by GitHub Actions:

**[Download WindowsCrashDoctor.exe](https://github.com/joshualparris/hprobooktroubleshoot/releases/download/windows-crash-doctor-desktop-latest/WindowsCrashDoctor.exe)**

The EXE is currently unsigned, so Windows SmartScreen may show **Unknown Publisher**. A SHA-256 file is published beside the EXE for verification.

For a one-click install that creates a Desktop shortcut, download and double-click [`INSTALL-WINDOWS-CRASH-DOCTOR-GUI.cmd`](INSTALL-WINDOWS-CRASH-DOCTOR-GUI.cmd).

## Project status

**Current `main`:**

- reproducible Windows diagnostic collector;
- evidence-first Crash Doctor snapshot analyser;
- Markdown + JSON reports;
- native minidump/kernel-dump parser foundation;
- verified open-source provider layer;
- synthetic Windows regression tests and PowerShell QA;
- public-evidence/BitLocker recovery-key guard;
- command-line one-click launcher;
- native WPF desktop GUI and automated EXE release pipeline;
- documented HP ProBook evidence and controlled test plan.

The remaining gaps are tracked individually in the **[100-item Windows Crash Doctor roadmap](docs/ROADMAP_100.md)**. Cross-repository engineering upgrades identified from Josh's other GitHub projects are tracked separately in the **[GitHub Borrow Roadmap](docs/GITHUB_BORROW_ROADMAP.md)**.

## Command-line one-click install

If you prefer the original PowerShell/console workflow, open ordinary PowerShell and paste:

```powershell
$p="$env:TEMP\Install-WindowsCrashDoctor.ps1"; Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/joshualparris/hprobooktroubleshoot/main/scripts/Install-WindowsCrashDoctor.ps1" -OutFile $p; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p
```

That installer creates **Windows Crash Doctor.cmd** on the Desktop and runs the tested command-line collector/analyser workflow.

## Manual quick start

Open an elevated Windows PowerShell prompt in the repository.

### 1. Collect a snapshot

```powershell
.\scripts\collect-diagnostics.ps1
```

### 2. Analyse it

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath "$env:USERPROFILE\Desktop\HPProBook-YYYYMMDD-HHMMSS"
```

### 3. Analyse a dump

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -DumpPath C:\Windows\Minidump\example.dmp `
  -OutputDirectory C:\Evidence\DumpReport
```

### 4. Run regression tests

```powershell
.\windows-crash-doctor\tests\self-test.ps1 -RepositoryMode
.\windows-crash-doctor\tests\dump-parser-test.ps1
```

## Windows Crash Doctor today

The rule engine understands evidence relevant to this case, including:

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
- volmgr Event 161;
- HWiNFO-style sensor CSV telemetry and sustained memory pressure;
- current-window System Power Report abnormal-shutdown evidence.

Each finding keeps **severity**, **confidence**, **evidence**, **interpretation** and **next step** separate.

It does **not** silently flash firmware, remove drivers, disable security, change BitLocker, alter pagefile/dump policy or upload private diagnostic data.

## Documentation

| Document | Purpose |
|---|---|
| [`desktop/WindowsCrashDoctor.App/README.md`](desktop/WindowsCrashDoctor.App/README.md) | Native desktop app architecture and build |
| [`docs/README.md`](docs/README.md) | Documentation map and authority rules |
| [`windows-crash-doctor/README.md`](windows-crash-doctor/README.md) | Crash Doctor engine usage and behaviour |
| [`docs/OPEN_SOURCE_INTEGRATIONS.md`](docs/OPEN_SOURCE_INTEGRATIONS.md) | Open-source provider architecture |
| [`docs/WINDOWS_CRASH_DOCTOR_PLAN.md`](docs/WINDOWS_CRASH_DOCTOR_PLAN.md) | Product architecture and design |
| [`docs/GITHUB_BORROW_ROADMAP.md`](docs/GITHUB_BORROW_ROADMAP.md) | Adapt reusable diagnostics/reliability/security patterns from Josh's other repositories |
| [`docs/COMPARABLE_TOOLS_RESEARCH.md`](docs/COMPARABLE_TOOLS_RESEARCH.md) | Comparator-tool research |
| [`docs/ROADMAP_100.md`](docs/ROADMAP_100.md) | Canonical 100-item upgrade backlog |
| [`analysis/STATUS.md`](analysis/STATUS.md) | Current ProBook operational status |
| [`analysis/FORENSIC_UPDATE_2026-09-12.md`](analysis/FORENSIC_UPDATE_2026-09-12.md) | Latest sensor/power forensic correlation |
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

The machine has produced whole-system hard hangs with the display still lit/frozen and no useful recorded BSOD. Recovery required holding the power button. The current September incidents clustered around low-level power-state/resume behaviour.

### Strongest established facts

- HP quick memory testing and SSD SMART/Short DST passed.
- Current Windows storage counters do not provide strong evidence of straightforward SSD failure.
- A later ~46-minute HWiNFO capture materially weakens overheating during that captured window and confirms persistent severe 4 GB memory pressure.
- Physical BIOS is old.
- Windows recorded an HP N92 firmware device in a failed-start/Code 10 state.
- SetupAPI proves the delivered Windows image was Sysprep-respecialised and retained substantial previous-hardware state.
- Intel XTU components are present; a non-default tuning state has not yet been proven.
- Hibernation/Fast Startup was disabled as a controlled A/B test.
- Existing `volmgr 161` failures cannot be treated as storage proof while dump/pagefile configuration is inadequate.

The current working problem family remains **firmware/power-state/low-level OEM-driver interaction on a reused refurb Windows image**, with severe memory pressure as a proven contributing performance constraint. That is a hypothesis family, not a confirmed root cause.

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
desktop/                  native Windows Crash Doctor WPF app
docs/                     product architecture, research and roadmap
evidence/                 evidence workflow and SHA-256 manifests
raw/                      explicitly documented raw/archive boundary
scripts/                  collection, installation, hashing and public-evidence guard
windows-crash-doctor/     Crash Doctor engine, CLI, providers and tests
SECURITY_NOTICE.md        privacy/security rules
```

## Evidence and privacy

Raw logs are private by default. EVTX, ETL, WER files, dumps, `msinfo32`, SetupAPI, screenshots and memory dumps can contain usernames, hardware identifiers, network details, application state or secrets.

Never commit a BitLocker recovery password. Review [`SECURITY_NOTICE.md`](SECURITY_NOTICE.md) before publishing diagnostic artefacts.