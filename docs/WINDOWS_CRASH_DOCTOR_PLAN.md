# Windows Crash Doctor architecture and product plan

## Mission

Windows Crash Doctor should answer four questions in order:

1. **What actually happened?**
2. **What evidence supports each explanation?**
3. **What is the smallest test that separates the leading explanations?**
4. **What changed after that test?**

It should do this without turning suspicious events into automatic root-cause claims and without destroying evidence by changing multiple variables at once.

The HP ProBook 11 G2 is the first golden case, not the architecture.

## Current implementation on `main`

Today the pipeline is snapshot-based:

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
    v
CrashDoctor.psm1
    |
    +-- parse
    +-- evaluate rules
    +-- account for missing inputs
    +-- keep evidence separate from interpretation
    |
    +--> crash-doctor-report.md
    +--> crash-doctor-report.json
```

The current analyser is intentionally read-only and dependency-light.

## Target architecture

The roadmap expands the product into five cooperating layers:

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

High-risk remediation remains outside the automatic analysis path.

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

One incident may reference many evidence artefacts.

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

### Problem/signature

A deduplicated cluster of incidents that appear to share a cause/signature. Repeated crashes should increase frequency statistics, not create 50 unrelated “root causes”.

### Experiment

A controlled one-variable change with:
- baseline;
- single intended variable;
- start/end time;
- success criteria;
- incident count before/after;
- evidence bundle;
- rollback/reversal notes.

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

The current collector remains the canonical broad snapshot source. Future capture mechanisms should complement it:

- Windows Error Reporting store and LocalDumps;
- ProcDump-style triggers;
- ETW/WPR circular traces;
- early-boot tracing;
- optional high-volume ProcMon-style traces;
- native Windows dump discovery;
- runtime-specific exception hooks;
- a low-overhead always-on incident service.

A capture mechanism must document overhead and storage limits before it can run continuously.

## Analysis roadmap

Analysis grows from text rules to:
- minidump/kernel/full-dump parsers;
- Microsoft symbol resolution;
- bugcheck/exception knowledge;
- call-stack and module analysis;
- dump-time locks/waits;
- WER signatures/buckets;
- ETW timelines;
- crash history, clustering and deduplication;
- known-problem/issue-tracker matching.

The full list is in [`ROADMAP_100.md`](ROADMAP_100.md).

## Presentation roadmap

The product should eventually expose the same evidence through several surfaces:

- CLI for deterministic automation;
- Markdown for support/human review;
- JSON for integrations;
- local history browser;
- timeline UI;
- privacy-review/export wizard;
- debugger hand-off;
- issue/support bundle export.

The CLI and JSON schema remain the automation contract even if a GUI is added.

## Profile model

Model-specific profiles can provide:
- expected hardware identifiers;
- vendor support links;
- known firmware families;
- expected driver/device names;
- safe diagnostic commands;
- case-specific warnings.

Profiles must not mark a hypothesis as true merely because the machine matches a model.

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
10. **Upgrade tests** for persisted incident databases.

## Security model

Diagnostic data may contain:
- process memory;
- usernames;
- command lines;
- file paths;
- network addresses;
- serial numbers;
- browser/application content;
- credentials or recovery material.

Defaults:
- raw/private by default;
- local processing by default;
- no automatic upload;
- least privilege where practical;
- explicit retention;
- access checks before reading another user's dump;
- reviewed/redacted export.

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

Research and source links are in [`COMPARABLE_TOOLS_RESEARCH.md`](COMPARABLE_TOOLS_RESEARCH.md). The resulting 100 gaps are tracked in [`ROADMAP_100.md`](ROADMAP_100.md).

## Delivery strategy

### Phase A — richer evidence

Prioritise dump parsing/symbols, WER ingestion, ETW circular capture, incident catalogue and retention.

### Phase B — stronger diagnosis

Add stack analysis, bugcheck knowledge, historical correlation, signatures, deduplication and driver/module identity.

### Phase C — proactive capture

Add trigger-based dumps, crash/hang detection, boot/resume tracing and runtime hooks.

### Phase D — investigation UX

Add history, timeline, privacy review, support export and remote/offline workflows.

### Phase E — extensibility

Add plugins, custom trace profiles, retracing, debugger integration and reporting backends.

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
