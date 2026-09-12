# Windows Crash Doctor architecture and product plan

## Mission

Windows Crash Doctor should answer four questions in order:

1. **What actually happened?**
2. **What evidence supports each explanation?**
3. **What is the smallest test that separates the leading explanations?**
4. **What changed after that test?**

It should do this without turning suspicious events into automatic root-cause claims and without destroying evidence by changing multiple variables at once.

The HP ProBook 11 G2 is the first golden case, not the architecture.

## Current implementation

The original snapshot pipeline still provides the core evidence/rule path:

```text
Windows machine
    |
    v
scripts/collect-diagnostics.ps1
    |
    +-- hardware / OS / boot state
    +-- firmware / PnP / driver state
    +-- storage / dump / BitLocker state
    +-- recent event text + EVTX
    +-- SetupAPI + power reports
    |
    v
windows-crash-doctor/Invoke-CrashDoctor.ps1
    |
    +-- CrashDoctor.psm1
    +-- TelemetryAnalysis.psm1
    +-- DumpParser.psm1 (dump mode)
    +-- DiagnosticRegistry.psm1 + diagnostics/registry.json
    |
    +--> crash-doctor-report.md
    +--> crash-doctor-report.json
```

The current `0.3.0-preview.1` desktop product now adds a substantial v2 application layer around that engine:

```text
WPF desktop
    |
    +--> preflight/self-check
    +--> embedded engine + registry extraction
    +--> full diagnosis / dump analysis / deep sensor capture
    +--> structured PowerShell timeout/cancellation/retry runner
    +--> registry-backed coverage + provenance
    +--> finding/evidence fingerprints
    +--> previous comparable-run comparison
    +--> SQLite diagnostic run ledger
    +--> report enrichment
    +--> privacy-reviewed shareable export
```

These are implemented source capabilities, not merely planned architecture. Release verification is a separate question; see [`RELEASE_VERIFICATION.md`](RELEASE_VERIFICATION.md).

Two important v2 gaps remain:

- the diagnostic registry is canonical for metadata/coverage/provenance but does not yet dispatch every collector command itself;
- the broad collector is still largely one process, so per-diagnostic execution status/timing is partly inferred from evidence-file outcomes rather than every probe having an independent runner lifecycle.

## Target architecture

The larger roadmap still expands the product into five cooperating layers:

```text
+-------------------------+
| 1. Capture              |
| snapshots, WER, dumps,  |
| ETW, triggers, canary   |
+------------+------------+
             |
             v
+-------------------------+
| 2. Evidence store       |
| incidents, hashes,      |
| provenance, retention   |
+------------+------------+
             |
             v
+-------------------------+
| 3. Analysis             |
| parsers, symbols,       |
| rules, stacks, history  |
+------------+------------+
             |
             v
+-------------------------+
| 4. Reasoning            |
| hypotheses, confidence, |
| dedupe, next test       |
+------------+------------+
             |
             v
+-------------------------+
| 5. Presentation/action  |
| report, timeline,       |
| debugger/support export |
+-------------------------+
```

The current SQLite **diagnostic run ledger** is an implemented step toward layer 2, but it is not yet the full always-on crash/incident catalogue implied by this target. High-risk remediation remains outside the automatic analysis path.

## Core data concepts

### Evidence artefact

A file or record captured from the system, with:

- stable ID;
- source;
- capture timestamp;
- machine/session/boot identity where known;
- SHA-256 where applicable;
- sensitivity classification;
- parser status;
- provenance links.

Current source already implements evidence-bundle fingerprints and registry/rule provenance, but the fully typed cross-provider `EvidenceBundle` architecture remains future work.

### Diagnostic run

The desktop now persists a concrete diagnostic-run model in SQLite, including run identity/time/status, device/evidence fingerprints, product/rule versions, finding/coverage summaries, collector outcome records and comparison state.

A run is not automatically an incident: a healthy/manual diagnostic snapshot can exist without a known crash.

### Incident

A time-bounded failure or suspected failure:

- hard freeze;
- bugcheck/BSOD;
- application crash;
- application hang;
- unexpected reboot;
- WHEA/hardware error;
- installer/update failure;
- manually marked symptom.

One incident may reference many evidence artefacts and diagnostic runs. This richer incident model is not complete yet.

### Finding

A bounded diagnostic statement:

| Field | Meaning |
|---|---|
| `Id` | stable machine-readable rule ID |
| `Severity` | operational priority |
| `Confidence` | confidence in the interpretation |
| `Evidence` | direct observations |
| `Interpretation` | what those observations support |
| `Contradictions` | evidence against the hypothesis |
| `Unknowns` | missing discriminating evidence |
| `NextStep` | smallest useful diagnostic action |

Current desktop enrichment also adds fingerprint, rule version, source collector and comparison state.

### Problem/signature

A deduplicated cluster of incidents that appear to share a cause/signature. The current finding fingerprints/comparison engine are a useful foundation, but stack-similarity crash clustering/deduplication remains future work.

### Experiment

A controlled one-variable change with baseline, one intended variable, start/end time, success criteria, incident count before/after, evidence bundle and rollback notes. This remains a target model rather than a complete product subsystem.

## Architecture rules

1. **Understand before changing.**
2. **One source of truth per concept.**
3. **Collection is not remediation.**
4. **Historical state is not current state.**
5. **Missing evidence is unknown.**
6. **Aftermath events are not automatically causes.**
7. **Profiles may add context; they may not fabricate evidence.**
8. **Every automated conclusion must be explainable.**
9. **Every risky action requires explicit approval.**
10. **Privacy, retention and provenance are core data-model concerns.**

## Capture roadmap

Implemented capture today includes the broad snapshot collector, existing dump-file analysis and desktop LibreHardwareMonitor deep sensor capture. Future capture mechanisms should complement rather than fork those paths:

- Windows Error Reporting store and LocalDumps;
- ProcDump-style triggers;
- ETW/WPR circular traces;
- early-boot tracing;
- optional high-volume ProcMon-style traces;
- automatic native Windows dump discovery/indexing;
- runtime-specific exception hooks;
- a low-overhead always-on incident service.

A capture mechanism must document overhead and storage limits before it can run continuously.

## Analysis roadmap

Already present as foundations:

- evidence-first text/rule analysis;
- supported HWiNFO/LibreHardwareMonitor telemetry analysis;
- bounded System Power Report parsing;
- native minidump/kernel-header parser foundation;
- previous-run evidence comparison.

Still future/deeper:

- Microsoft symbol resolution;
- richer bugcheck/exception knowledge;
- call-stack and module analysis;
- dump-time locks/waits;
- WER signatures/buckets;
- ETW timelines;
- incident clustering/deduplication;
- known-problem/issue-tracker matching.

The full list is in [`ROADMAP_100.md`](ROADMAP_100.md).

## Presentation roadmap

Already implemented surfaces:

- CLI for deterministic automation;
- Markdown/JSON reports;
- native WPF desktop dashboard;
- SQLite-backed diagnostic history view;
- previous-run comparison summary;
- privacy-reviewed shareable export.

Still future/deeper:

- interactive incident/timeline UI;
- richer per-finding comparison/provenance drill-down;
- debugger hand-off;
- remote/offline workflows;
- support/issue-tracker submission integrations;
- broad WPF UI automation/accessibility/localisation.

The JSON schema remains the automation boundary even as UI surfaces grow.

## Profile model

Model-specific profiles can provide expected hardware identifiers, vendor support links, known firmware families, expected driver/device names, safe diagnostic commands and case-specific warnings.

Profiles must not mark a hypothesis as true merely because the machine matches a model. The current product still has case/OEM assumptions to separate further into profiles; that remains post-P0 architecture work.

## Testing strategy

The test pyramid should include:

1. **Parser tests** for every input format.
2. **Rule fixtures** with positive, negative and ambiguous examples.
3. **Quiet-machine fixtures** to control false positives.
4. **Golden incident fixtures** built from redacted real cases.
5. **Schema compatibility tests**.
6. **Windows integration tests** on supported PowerShell versions.
7. **Performance/overhead tests** for continuous capture.
8. **Privacy tests** for export/redaction.
9. **Corruption/truncation tests** for partial evidence.
10. **Upgrade tests** for persisted databases.
11. **Packaged-artifact tests** proving embedded engine/resources, not only repository checkout behaviour.

Current Product Gate already covers PowerShell parser/analyzer, snapshot/telemetry/integration regression tests, synthetic + real DbgHelp dump smoke, public-evidence guard, desktop build and packaged EXE self-test. Broader SQLite/preflight/UI failure-path coverage remains desirable.

## Security model

Diagnostic data may contain process memory, usernames, command lines, file paths, network addresses, serial numbers, browser/application content and credentials/recovery material.

Defaults:

- raw/private by default;
- local processing by default;
- no automatic upload;
- least privilege where practical;
- explicit retention as the target;
- access checks before reading another user's dump;
- reviewed/redacted export.

The current desktop privacy-reviewed export is implemented and tested against known secret fixtures, but must not be described as exhaustive PII/secret detection.

See [`../SECURITY_NOTICE.md`](../SECURITY_NOTICE.md).

## Comparable-tool benchmark

The September 2026 research pass compares Crash Doctor with:

- WinDbg;
- WhoCrashed;
- BlueScreenView;
- ProcDump;
- WPR/WPA;
- Process Monitor;
- Windows Error Reporting;
- Fedora ABRT;
- Ubuntu Apport;
- systemd-coredump/coredumpctl.

Research and source links are in [`COMPARABLE_TOOLS_RESEARCH.md`](COMPARABLE_TOOLS_RESEARCH.md). The resulting 100 capability gaps are tracked in [`ROADMAP_100.md`](ROADMAP_100.md).

## Delivery strategy

The original delivery phases are no longer all untouched future work:

### Phase A — richer evidence

**Partial.** Native dump parsing and privacy/export/provenance foundations exist. Symbols, WER ingestion, ETW circular capture, full incident catalogue and retention remain future.

### Phase B — stronger diagnosis

**Partial foundation.** Previous-run evidence fingerprints/comparison exist. Stack analysis, richer bugcheck knowledge, crash signatures/deduplication and broader driver/module identity remain future.

### Phase C — proactive capture

**Mostly future.** Trigger-based dumps, automatic crash/hang detection, boot/resume tracing and runtime hooks are not implemented as a complete subsystem.

### Phase D — investigation UX

**Partial.** Native WPF UI, diagnostic history, comparison summary and privacy-reviewed export exist. Timeline, richer incident UX and remote/offline workflows remain future.

### Phase E — extensibility

**Future.** Plugins, custom trace profiles, retracing, debugger integration and reporting backends remain broader product work.

## P0/v2 versus stable release

P0/v2 completion is about proving the current composed path — preflight, collection, analysis, persistence/comparison, privacy export, packaged engine and release handoff — for one exact commit.

It does **not** require the whole five-layer roadmap to be finished. Conversely, a green canary is not yet a hardened stable release: Authenticode signing, immutable semantic stable releases, broader UI automation, stronger supply-chain provenance and other productisation work remain post-P0.

See [`RELEASE_VERIFICATION.md`](RELEASE_VERIFICATION.md) for the exact release-proof contract.

## ProBook integration

The ProBook case remains useful because it forces Crash Doctor to handle:

- a true hard hang with no trustworthy dump;
- reused Windows-image history;
- power-state correlation;
- firmware abnormalities that are suspicious but not proven causal;
- weak dump configuration;
- multiple plausible low-level culprits.

For this case the next diagnostic questions remain:

- Is the firmware resource currently healthy?
- Does the machine stay stable with Fast Startup disabled?
- Is XTU actually applying non-default tuning?
- Can the next failure produce a trustworthy dump or trace?
- Do thermal/power/ETW signals change immediately before a freeze?
- Does the problem survive updated firmware, known-good RAM and a clean OS?

The case test plan remains in [`../analysis/TEST_PLAN.md`](../analysis/TEST_PLAN.md).