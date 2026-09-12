# Windows Crash Doctor

Windows Crash Doctor is an evidence-first Windows crash/hang triage engine.

The current release on `main` is deliberately small and read-only: it consumes a reproducible collector snapshot, evaluates bounded diagnostic rules and emits human- and machine-readable reports. It is being expanded toward proactive capture, dump analysis, ETW correlation and incident history through the [100-item roadmap](../docs/ROADMAP_100.md).

## What problem it solves

Windows failure investigations commonly mix together:
- the failure itself;
- events written only after the reboot;
- old events inherited from a cloned/refurb image;
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
- Administrator rights are recommended for the collector; analysis can run with ordinary file access to the evidence folder.
- No third-party PowerShell modules are required by the current snapshot analyser.

## Quick start

From the repository root in an elevated PowerShell session:

```powershell
.\scripts\collect-diagnostics.ps1
```

Then:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath "$env:USERPROFILE\Desktop\HPProBook-YYYYMMDD-HHMMSS"
```

To place reports elsewhere:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath C:\Evidence\HPProBook-20260912-160000 `
  -OutputDirectory C:\Evidence\Reports
```

## Outputs

### `crash-doctor-report.md`

Designed for a person investigating the machine. It contains:
- inventory/coverage;
- detected findings;
- severity/confidence;
- bounded interpretation;
- next diagnostic action.

### `crash-doctor-report.json`

The stable automation boundary. External tooling should consume the JSON rather than scrape Markdown.

The schema is additive where practical. Breaking schema changes should increment `SchemaVersion`.

## Current rule families

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
| Reporting | Markdown + JSON |
| Tests | Synthetic abnormal/quiet fixtures and public-evidence guard |

## Current limitations

Crash Doctor currently does **not**:
- parse `.dmp`/`.mdmp` memory dumps;
- resolve Microsoft symbols;
- inspect call stacks, registers or dump-time locks;
- record ETW/WPR traces;
- monitor process exceptions/hangs continuously;
- maintain a persistent incident database;
- deduplicate repeated crashes;
- show an interactive timeline;
- ingest the WER report store;
- send reports to a bug tracker or vendor.

These are not hidden limitations: they are explicitly tracked in [`../docs/ROADMAP_100.md`](../docs/ROADMAP_100.md).

## Safety boundary

The analysis path is read-only. Diagnostic recommendations are not the same as authorised remediation.

Crash Doctor must not silently:
- flash BIOS/UEFI;
- install/uninstall drivers;
- disable BitLocker or security controls;
- change dump/pagefile policy;
- disable hibernation;
- run Driver Verifier;
- upload dump files, ETL traces or private evidence.

Future mutation helpers must be explicit, reversible where possible and separated from collection/analysis.

## Input contract

The canonical collector is:

```powershell
.\scripts\collect-diagnostics.ps1
```

Crash Doctor treats missing evidence as **unknown**, not healthy. A partial collection should reduce `Coverage` rather than generate confident negative findings.

Binary EVTX files may be preserved for deeper work, but the current rule engine primarily consumes the collector's text exports.

## Testing

Run:

```powershell
.\windows-crash-doctor\tests\self-test.ps1 -RepositoryMode
```

The test suite builds synthetic abnormal and quiet fixtures and checks:
- expected rules fire;
- quiet fixtures do not produce high/critical false positives;
- memory inventory parsing works;
- Markdown and JSON files are emitted;
- evidence-discipline wording remains present;
- the repository public-evidence guard passes.

CI runs PowerShell parsing and tests on a Windows runner.

## Design principles

1. Understand before changing.
2. One concept, one source of truth.
3. Collection and remediation are separate.
4. Missing data is unknown, not proof of health.
5. Event 41 is aftermath evidence, not a root cause.
6. Historical Windows-image state is not automatically current-machine state.
7. A suspicious component is a hypothesis until discriminating evidence supports it.
8. Prefer controlled A/B tests over batches of changes.
9. Every finding should be reproducible from named evidence.
10. Privacy, retention and provenance are diagnostic features, not documentation afterthoughts.

## Where the project is going

The ten-tool benchmark in [`../docs/COMPARABLE_TOOLS_RESEARCH.md`](../docs/COMPARABLE_TOOLS_RESEARCH.md) produced 100 concrete upgrades spanning:
- native dump analysis and symbols;
- trigger-based capture;
- ETW timelines;
- ProcMon-style activity correlation;
- WER ingestion;
- automatic crash detection;
- history/deduplication;
- privacy review and retention;
- remote retracing;
- debugger and issue-tracker integrations.

Use [`../docs/README.md`](../docs/README.md) as the documentation index.
