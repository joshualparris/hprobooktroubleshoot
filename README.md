# HP ProBook 11 G2 hard-freeze investigation + Windows Crash Doctor

This repository serves two related purposes:

1. preserve an evidence-driven investigation of an HP ProBook 11 G2 that hard-freezes; and
2. develop **Windows Crash Doctor**, a reusable Windows crash/hang triage tool grown from that investigation.

The core rule is simple: keep **observation**, **current-machine telemetry**, **inherited image history**, **interpretation** and **causality** separate. Change one major variable at a time.

> **Engineering status:** Windows Crash Doctor is currently **0.3.0-preview.1** with engine **0.3.0**. It is an advanced preview, not yet a hardened stable release. See [`RELEASE_VERIFICATION.md`](docs/RELEASE_VERIFICATION.md) for the exact Product Gate/canary state and [`REPOSITORY_AUDIT.md`](docs/REPOSITORY_AUDIT.md) for the dated engineering audit.

## Windows Crash Doctor Desktop

Windows Crash Doctor has a native Windows WPF front end in `desktop/WindowsCrashDoctor.App`.

The current source includes:

- a dashboard with live CPU/RAM/temperature cards;
- one-click **Run Full Diagnosis** with preflight and UAC only when collection requires it;
- ranked evidence cards with severity, confidence and recommended next action;
- live diagnostic progress and logs;
- optional LibreHardwareMonitor deep sensor capture, with its JSONL data normalized into the same telemetry analysis path used for supported HWiNFO CSV evidence;
- a SQLite diagnostic run ledger with legacy JSON-history migration;
- finding/evidence fingerprints and previous comparable-run comparison (`NEW`, `RESOLVED`, `IMPROVED`, `WORSENED`, `UNCHANGED`, `UNKNOWN`);
- a canonical diagnostic registry used for coverage/provenance metadata;
- bounded process timeout/cancellation/retry behaviour for desktop PowerShell operations;
- native `.dmp` / `.mdmp` structural analysis through the Crash Doctor dump parser;
- open-source provider installation/status;
- privacy-reviewed shareable ZIP export with preview, conservative high-risk exclusions, text redaction and `export-manifest.json`;
- light and dark themes;
- a self-contained `WindowsCrashDoctor.exe` with telemetry, registry, version metadata and the required PowerShell engine resources embedded.

Some v2 architecture is still partial: the diagnostic registry does not yet drive every collector command, and per-diagnostic execution records for the monolithic collector are still partly inferred from produced evidence rather than every probe being independently timed/retried.

### Download / canary status

The rolling canary URL is:

**[WindowsCrashDoctor.exe canary](https://github.com/joshualparris/hprobooktroubleshoot/releases/download/windows-crash-doctor-desktop-latest/WindowsCrashDoctor.exe)**

**Do not assume the rolling URL is the current verified `0.3.0-preview.1` build merely because a file is present.** The Product Gate deliberately refuses to replace the canary when the packaged EXE self-test fails. Check [`docs/RELEASE_VERIFICATION.md`](docs/RELEASE_VERIFICATION.md) for the exact verified commit before installing.

The EXE is currently unsigned, so Windows SmartScreen may show **Unknown Publisher**. Current installers verify the downloaded release asset's SHA-256 before installation/activation, but hash verification is not Authenticode publisher trust.

For the GUI install path, download and run [`INSTALL-WINDOWS-CRASH-DOCTOR-GUI.cmd`](INSTALL-WINDOWS-CRASH-DOCTOR-GUI.cmd). The bootstrap and installer are designed to verify release assets before first launch.

## Project status

**Current source contains:**

- reproducible Windows diagnostic collector;
- evidence-first snapshot analyser;
- HWiNFO CSV and LibreHardwareMonitor JSONL telemetry analysis;
- Markdown + JSON reports with version/provenance metadata;
- native minidump/kernel-dump parser foundation;
- verified optional open-source provider layer;
- diagnostic registry and registry-backed coverage/provenance;
- preflight health checks;
- SQLite run history, fingerprints and previous-run comparison;
- privacy-reviewed local shareable export;
- synthetic Windows regression tests, real DbgHelp minidump smoke test and PowerShell QA;
- public-evidence/BitLocker recovery-key guard;
- hash-verifying GUI and CLI install paths;
- native WPF desktop GUI;
- a gated canary release pipeline that only publishes an already-tested artifact after the packaged EXE self-test passes;
- documented HP ProBook evidence and controlled test plan.

The **[release verification record](docs/RELEASE_VERIFICATION.md)** is the authority for whether a particular canary is actually releasable. The **[repository engineering audit](docs/REPOSITORY_AUDIT.md)** is a dated quality/risk baseline. Planned capabilities are tracked in the **[100-item roadmap](docs/ROADMAP_100.md)**, while cross-repository engineering adaptations and their current completion state are tracked in the **[GitHub Borrow Roadmap](docs/GITHUB_BORROW_ROADMAP.md)**.

## Command-line preview install

The console installer is `scripts/Install-WindowsCrashDoctor.ps1`.

The current CLI installer resolves the canary release, downloads the release-built engine ZIP and its checksum, verifies SHA-256, extracts into a staging location, runs package self-tests before activation and installs into the current user's profile. The installer itself stays in standard-user mode; the diagnostic runner requests elevation when collection actually needs it.

This remains a **canary/preview** install path. A future stable channel still needs immutable semantic releases, stronger supply-chain provenance and Authenticode signing before it should be described as hardened stable distribution.

## Manual quick start

Open an elevated Windows PowerShell prompt in a trusted local checkout of the repository.

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
.\windows-crash-doctor\tests\telemetry-self-test.ps1
.\windows-crash-doctor\tests\dump-parser-test.ps1
.\windows-crash-doctor\tests\dump-parser-real-smoke.ps1
.\windows-crash-doctor\tests\integration-self-test.ps1 -RepositoryMode
```

Treat the **Product Gate** as the release-health signal. Passing repository tests or producing an EXE is not, by itself, proof that the packaged executable and release handoff are healthy.

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
- supported HWiNFO CSV and LibreHardwareMonitor JSONL telemetry;
- sustained memory pressure, thermal state, continuity and workload-burst evidence where the provider captures those signals;
- current-window System Power Report abnormal-shutdown evidence.

Each finding keeps **severity**, **confidence**, **evidence**, **interpretation** and **next step** separate.

It does **not** silently flash firmware, remove drivers, disable security, change BitLocker, alter pagefile/dump policy or upload private diagnostic data.

## Documentation

| Document | Purpose |
|---|---|
| [`docs/RELEASE_VERIFICATION.md`](docs/RELEASE_VERIFICATION.md) | Current release-proof contract, canary status and completion audit |
| [`docs/REPOSITORY_AUDIT.md`](docs/REPOSITORY_AUDIT.md) | Dated repository-wide engineering quality/risk audit |
| [`docs/PHASE0_IMPLEMENTATION_2026-09-12.md`](docs/PHASE0_IMPLEMENTATION_2026-09-12.md) | Concrete Phase 0/P0 remediation implementation record |
| [`desktop/WindowsCrashDoctor.App/README.md`](desktop/WindowsCrashDoctor.App/README.md) | Native desktop app architecture and build |
| [`docs/README.md`](docs/README.md) | Documentation map and authority rules |
| [`windows-crash-doctor/README.md`](windows-crash-doctor/README.md) | Crash Doctor engine usage and behaviour |
| [`docs/OPEN_SOURCE_INTEGRATIONS.md`](docs/OPEN_SOURCE_INTEGRATIONS.md) | Open-source provider architecture |
| [`docs/WINDOWS_CRASH_DOCTOR_PLAN.md`](docs/WINDOWS_CRASH_DOCTOR_PLAN.md) | Product architecture and design |
| [`docs/GITHUB_BORROW_ROADMAP.md`](docs/GITHUB_BORROW_ROADMAP.md) | Cross-repository adaptation roadmap with implementation status |
| [`docs/COMPARABLE_TOOLS_RESEARCH.md`](docs/COMPARABLE_TOOLS_RESEARCH.md) | Comparator-tool research |
| [`docs/ROADMAP_100.md`](docs/ROADMAP_100.md) | 100-item capability backlog |
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
docs/                     product architecture, research, audit, release verification and roadmaps
evidence/                 evidence workflow and SHA-256 manifests
raw/                      explicitly documented raw/archive boundary
scripts/                  collection, installation, hashing and public-evidence guard
windows-crash-doctor/     Crash Doctor engine, CLI, registry, providers and tests
SECURITY_NOTICE.md        privacy/security rules
```

## Evidence and privacy

Raw logs are private by default. EVTX, ETL, WER files, dumps, `msinfo32`, SetupAPI, screenshots and memory dumps can contain usernames, hardware identifiers, network details, application state or secrets.

The desktop shareable-export path creates a reviewed/redacted derivative and leaves original evidence untouched, but no automated scanner should be treated as infallible. Never commit a BitLocker recovery password. Review [`SECURITY_NOTICE.md`](SECURITY_NOTICE.md) before publishing diagnostic artefacts.