# Windows Crash Doctor

Windows Crash Doctor is an evidence-first Windows crash/hang triage engine. Current source identity is product **0.3.0-preview.1**, engine **0.3.0**. Whether a particular packaged canary is verified is tracked separately in [`../docs/RELEASE_VERIFICATION.md`](../docs/RELEASE_VERIFICATION.md).

The project has two core analysis paths:

- **snapshot analysis** — consumes a reproducible collector folder, evaluates bounded diagnostic rules and can correlate supported HWiNFO CSV, LibreHardwareMonitor JSONL and Windows System Power Report telemetry;
- **dump analysis** — parses supported Windows crash-dump structures directly and emits Markdown + JSON.

The WPF desktop app layers preflight, registry-backed coverage/provenance, SQLite run history, fingerprints/comparison and privacy-reviewed export around those engine paths.

## What problem it solves

Windows failure investigations commonly mix together:

- the failure itself;
- events written only after reboot;
- old or future-dated events inherited from a cloned/refurb image;
- speculation about a suspicious driver;
- several simultaneous “fixes”.

Crash Doctor tries to stop that. A finding must distinguish:

- **evidence** — what was actually captured;
- **interpretation** — what that evidence reasonably supports;
- **confidence** — how reliable that interpretation is;
- **severity** — how urgently it matters;
- **next step** — the smallest useful follow-up action.

## Requirements

- Windows 10/11 or Windows Server capable of running Windows PowerShell 5.1+.
- Administrator rights are recommended for the collector; analysis can run with ordinary file access to the evidence/dump.
- No third-party PowerShell modules are required at runtime by the snapshot, telemetry or native dump parser.

## Snapshot-analysis quick start

From the repository root in an elevated PowerShell session:

```powershell
.\scripts\collect-diagnostics.ps1
```

Then:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath "$env:USERPROFILE\Desktop\HPProBook-YYYYMMDD-HHMMSS"
```

To include an existing HWiNFO sensor export in the same snapshot:

```powershell
.\scripts\collect-diagnostics.ps1 `
  -SensorCsvPath "$env:USERPROFILE\Desktop\sensors.CSV"
```

The collector copies the supplied CSV to `sensors.csv`; it does not start, configure or modify HWiNFO.

The desktop deep-capture path writes LibreHardwareMonitor JSONL. Crash Doctor's telemetry layer can consume supported `sensor*.jsonl` / `wcd-sensors*.jsonl` evidence through the same bounded finding model used for HWiNFO. Provider-specific absence remains **unknown**: for example, a LibreHardwareMonitor capture does not invent a clean WHEA or drive-health result if those signals were not captured.

To place reports elsewhere:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath C:\Evidence\HPProBook-20260912-160000 `
  -OutputDirectory C:\Evidence\Reports
```

## Dump-analysis quick start

To parse an individual Windows dump:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -DumpPath C:\Windows\Minidump\example.dmp
```

Optional output directory:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -DumpPath C:\Evidence\example.dmp `
  -OutputDirectory C:\Evidence\Reports
```

Dump mode writes:

- `crash-doctor-dump-report.md`;
- `crash-doctor-dump-report.json`.

## WCD-001 native dump parser status

**WCD-001 is in progress, not complete.** The current foundation is intentionally useful without overstating coverage.

### Implemented

For `MDMP` minidumps Crash Doctor currently parses:

- header + stream directory with bounds validation;
- processor architecture and Windows build information;
- exception thread/code/address/parameters when present;
- loaded-module list and module names;
- thread count;
- `MemoryList`, `Memory64List` and `MemoryInfoList` summary metadata;
- known stream names while retaining unknown stream IDs.

For Windows kernel crash-dump containers Crash Doctor currently recognises:

- 64-bit `PAGE` / `DU64` headers;
- 32-bit `PAGE` / `DUMP` headers;
- machine architecture;
- processor count;
- bugcheck code and four parameters;
- key dump-header pointers/metadata;
- 64-bit dump-type/size/time metadata where available.

### Still required before WCD-001 is complete

- validated traversal of kernel/full-memory dump page data;
- broader coverage of dump variants across Windows versions/architectures;
- real kernel/full-memory fixtures, not only synthetic headers;
- additional corruption/truncation fuzz cases;
- a stable documented dump JSON schema once the native structures settle.

Symbol resolution, stack unwinding and source mapping are deliberately separate roadmap items (`WCD-002`, `WCD-004`, `WCD-005`, `WCD-009`).

## Snapshot outputs

### `crash-doctor-report.md`

Designed for a person investigating the machine. It contains inventory/coverage, findings, severity/confidence, bounded interpretation, next diagnostic action and telemetry summary when supported evidence is present.

When run through the current desktop workflow, the report is enriched with run identity, preflight state, registry provenance, evidence fingerprint, degraded-coverage information and previous-run comparison.

### `crash-doctor-report.json`

The machine-readable automation boundary for snapshot analysis. External tooling should consume JSON rather than scrape Markdown.

Current schema identity is recorded in `version.json`; breaking schema changes must increment it. The desktop enrichment path adds run/preflight/collector/comparison/registry metadata and per-finding fingerprint/rule/source/comparison fields.

## Current snapshot rule families

| Area | Current capability |
|---|---|
| Firmware | Detect firmware-class failed-start/Code 10 and current OK state |
| Image provenance | Detect Sysprep/respecialisation and retained non-present-device state |
| OEM/tuning | Detect XTU and Conexant-related evidence without claiming causality |
| BitLocker | Report conversion context without treating repeated percentages as proof of a stall |
| Power | Identify hibernation/Fast Startup state from collected evidence |
| Crash capture | Identify weak pagefile/dump configuration |
| Storage | Interpret current Windows storage reliability counters conservatively |
| Events | Summarise WHEA, Kernel-Power 41 and volmgr 161 |
| Sensor telemetry | Parse supported HWiNFO CSV and LibreHardwareMonitor JSONL and assess only signals actually available from that provider |
| System Power Report | Parse `LocalSprData`, count only failure records inside the report's declared time window and exclude stale/future failure records |
| Reporting | Markdown + JSON with version/provenance identity |

## Telemetry interpretation

Sensor and power-report data is time-bounded evidence:

- sustained high RAM load can explain paging/stalls without proving a hard-reset mechanism;
- low temperatures and zero throttle flags weaken overheating only for the captured interval;
- a zero HWiNFO WHEA counter is bounded negative evidence, not a hardware guarantee;
- provider-specific missing sensors are unknown, not healthy;
- brief GPU/ring electrical-limit flags remain low-priority unless they line up with failures;
- a continuous sensor log argues against a hidden freeze during that exact capture;
- System Power Report failure sessions are filtered to `ReportStartTime..ScanTime` before being counted.

The final rule matters on reused/refurbished images where inherited or clock-corrupted records can otherwise create false crash histories.

## Diagnostic registry and coverage

`diagnostics/registry.json` is the canonical registry for current diagnostic IDs, names, categories, evidence-file expectations, administrator metadata, default timeouts, retry policy, sensitivity, failure mode and rule version. Both PowerShell and desktop code validate registry identity/uniqueness and attach registry provenance to reports.

The registry is **not yet a complete execution dispatcher**. The collector still contains command implementation knowledge, so the v2 roadmap goal of “add a diagnostic once and automatically drive every collector/CLI/UI path from the registry” remains partial.

## Desktop preflight, run ledger and comparison

The WPF desktop currently adds:

- preflight for platform, elevation, engine extraction, registry, output/free space, SQLite health, PowerShell, CIM, Event Log, dump readiness, debugger/symbols and sensor provider;
- local SQLite `history.db` with run, finding, collector-execution and comparison tables;
- legacy `history.json` migration with visible warning on failure;
- SHA-256 device/finding/evidence-bundle fingerprints;
- comparison with the latest comparable run using `NEW`, `RESOLVED`, `IMPROVED`, `WORSENED`, `UNCHANGED` and `UNKNOWN` states;
- coverage-aware resolution so incomplete new evidence does not automatically mark an older finding resolved.

This is a **diagnostic run ledger**, not yet the broader always-on crash/incident catalogue described by later ABRT/systemd-coredump roadmap items.

## Execution resilience

Desktop PowerShell operations use a structured runner with:

- start/finish time and duration;
- exit code and stdout/stderr;
- completed/warning/cancelled/timed-out/retryable/permanent/unavailable states;
- linked cancellation;
- bounded timeout;
- process-tree termination;
- bounded exponential retry/backoff for explicitly retryable transient work;
- redacted failure logging.

The current collector is still largely one process. Per-diagnostic execution records are partly derived from expected evidence-file outcomes, so true independent timeout/retry timing for each registry probe remains post-P0/v2 follow-up work.

## Privacy-reviewed shareable export

The desktop export path is no longer a blind ZIP with a warning. It:

1. builds an export plan before writing the ZIP;
2. shows inclusion/exclusion/redaction/sensitive-match counts;
3. excludes high-risk opaque artefacts such as dumps, EVTX/ETL, packet captures, screenshots and unknown unscannable binaries by default;
4. excludes text containing private-key material;
5. redacts supported secret/identifier patterns from text derivatives;
6. records pattern metadata without exposing the matched secret;
7. reclassifies before copy;
8. writes `export-manifest.json`;
9. leaves original evidence unchanged.

The scanner is intentionally conservative and is **not** claimed to identify every possible secret or personal identifier.

## Current limitations

Crash Doctor still does **not**:

- resolve Microsoft symbols or unwind native/kernel call stacks;
- inspect dump-time locks/deadlocks;
- fully traverse arbitrary kernel/full-memory dump pages;
- fully decode arbitrary binary `.evtx` files inside the snapshot rule engine;
- record ETW/WPR traces;
- monitor process exceptions/hangs continuously;
- maintain an always-on crash/incident catalogue with lifecycle state (the desktop does have a SQLite diagnostic **run** ledger);
- deduplicate repeated crashes using stable crash/stack signatures across a long-running incident catalogue;
- show an interactive timeline;
- ingest the complete WER report store;
- send reports to a bug tracker or vendor;
- provide Authenticode signing or a hardened stable release channel.

These remain tracked in [`../docs/ROADMAP_100.md`](../docs/ROADMAP_100.md) and the post-P0 sections of [`../docs/RELEASE_VERIFICATION.md`](../docs/RELEASE_VERIFICATION.md).

## Safety boundary

The analysis path is read-only. Diagnostic recommendations are not the same as authorised remediation.

Crash Doctor must not silently:

- flash BIOS/UEFI;
- install/uninstall drivers;
- disable BitLocker or security controls;
- change dump/pagefile policy;
- disable hibernation;
- run Driver Verifier;
- upload dump files, ETL traces, sensor logs or private evidence.

Crash dumps can contain process memory, credentials, document fragments and identifiers. Event logs and diagnostic snapshots can also contain user/account information. Parsing is local-only by default; generated reports still require judgement before publication even when using the privacy-reviewed export path.

## Input contract

The canonical collector remains:

```powershell
.\scripts\collect-diagnostics.ps1
```

Crash Doctor treats missing evidence as **unknown**, not healthy. A partial collection should reduce `Coverage` rather than generate confident negative findings.

Optional snapshot telemetry inputs include:

- `sensors.csv`, `sensor*.csv` or `hwinfo*.csv` — supported HWiNFO-style sensor export;
- `sensor*.jsonl` or `wcd-sensors*.jsonl` — Windows Crash Doctor / LibreHardwareMonitor deep capture;
- `systempower-report*.html` or `sleepstudy-report*.html` — Windows System Power Report/SleepStudy data.

Desktop deep captures stored beside a snapshot may only be associated inside the bounded incident-time window used by the telemetry adapter, reducing stale-capture contamination.

The collector already generates `systempower-report.html`. Binary EVTX files are preserved locally for deeper work; the current snapshot core still primarily consumes its text event exports.

Dump mode accepts one local file path and rejects unknown signatures, impossible ranges and truncated structures rather than silently guessing.

## Testing and QA

Repository QA currently includes:

- Windows PowerShell parser checks across `.ps1`/`.psm1` sources;
- PSScriptAnalyzer error gate;
- snapshot-analysis synthetic self-test;
- HWiNFO/LibreHardwareMonitor telemetry regression coverage, including array/cardinality and bounded-negative-evidence cases;
- WCD-001 synthetic binary minidump/x64-kernel/x86-kernel fixtures;
- invalid/truncated dump rejection;
- dump CLI Markdown/JSON integration check;
- a real Windows DbgHelp `MiniDumpWriteDump` smoke test;
- integration self-test and Pester integration suite;
- public-evidence/recovery-key guard;
- desktop `--self-test` coverage for embedded-engine extraction/provenance, registry-backed coverage, timeout classification/process cleanup, run-comparison basics and privacy-export safety.

Useful local commands:

```powershell
.\windows-crash-doctor\tests\self-test.ps1 -RepositoryMode
.\windows-crash-doctor\tests\telemetry-self-test.ps1
.\windows-crash-doctor\tests\dump-parser-test.ps1
.\windows-crash-doctor\tests\dump-parser-real-smoke.ps1
.\windows-crash-doctor\tests\integration-self-test.ps1 -RepositoryMode
```

A test pass in the checkout is not enough for release publication. The Product Gate must also build and successfully run the actual `WindowsCrashDoctor.exe --self-test`, then create and re-verify the release manifest/hash artifact before the canary is replaced. See [`../docs/RELEASE_VERIFICATION.md`](../docs/RELEASE_VERIFICATION.md).

There is no browser UI, so Playwright is not the appropriate whole-app runner. The product surface now includes a native WPF desktop app as well as the PowerShell CLI/reports; broader WPF UI automation and accessibility testing remain future work.

## Design principles

1. Understand before changing.
2. One concept, one source of truth.
3. Collection and remediation are separate.
4. Missing data is unknown, not proof of health.
5. Event 41 and abnormal-shutdown records are aftermath evidence, not root-cause labels.
6. Historical Windows-image state is not automatically current-machine state.
7. A suspicious component is a hypothesis until discriminating evidence supports it.
8. Prefer controlled A/B tests over batches of changes.
9. Every finding should be reproducible from named evidence.
10. Privacy, retention and provenance are diagnostic features, not documentation afterthoughts.

## Where the project is going

The ten-tool benchmark in [`../docs/COMPARABLE_TOOLS_RESEARCH.md`](../docs/COMPARABLE_TOOLS_RESEARCH.md) produced 100 upgrades spanning symbols/stacks, trigger-based capture, ETW timelines, ProcMon-style correlation, WER ingestion, automatic crash detection, crash deduplication/cataloguing, retention, remote/offline analysis and support integrations.

Do not treat v2/P0 completion work as equivalent to finishing that 100-item product roadmap. Use [`../docs/README.md`](../docs/README.md) as the documentation index.