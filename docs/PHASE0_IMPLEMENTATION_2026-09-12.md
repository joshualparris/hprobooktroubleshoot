# Phase 0 repository-audit remediation — 12 September 2026

This document records the concrete remediation implemented from the P0 section of [`REPOSITORY_AUDIT.md`](REPOSITORY_AUDIT.md). It is an implementation record, not a claim that a release passed CI: the **Windows Crash Doctor Product Gate** is the authority for release readiness.

## AUD-001 — release gating

Implemented:

- replaced the desktop build-and-publish job with a two-stage **Product Gate**;
- the verification job has read-only repository permissions;
- release publication depends on successful PowerShell parsing, PSScriptAnalyzer, snapshot tests, telemetry tests, dump tests, integration tests, public-evidence guard, desktop compilation and packaged-EXE smoke testing;
- only the final release job receives `contents: write`;
- the release job downloads the exact previously verified artifact and rechecks SHA-256 before publishing;
- the rolling release is explicitly named **Canary / advanced preview** rather than stable.

## AUD-002 — telemetry regression

Implemented:

- removed the nested collection return shape from the HWiNFO CSV importer;
- added explicit single-provider row enumeration semantics;
- expanded regression tests around duplicate HWiNFO headings, sample counts, bounded negative evidence and workload bursts.

## AUD-003 — complete embedded engine

Implemented:

- `TelemetryAnalysis.psm1` is now an embedded desktop resource;
- `version.json` is also embedded;
- engine extraction is versioned as `0.2.0`;
- missing embedded resources fail extraction rather than silently degrading;
- the packaged desktop executable has a headless `--self-test` which proves telemetry is actually available through the extracted engine.

## AUD-004 — telemetry pipeline unification

Implemented:

- telemetry analysis now accepts both HWiNFO-style CSV and Windows Crash Doctor / LibreHardwareMonitor JSONL;
- both providers flow into the same telemetry summary and finding model;
- provider-specific absence is not turned into invented negative evidence — for example, LibreHardwareMonitor JSONL does not claim a clean WHEA counter or reassuring drive-health flags when those signals were not captured;
- a recent desktop deep-sensor file stored beside a snapshot can be associated only inside a bounded incident-time window, reducing stale-evidence contamination.

## AUD-005 — installer and release trust

Implemented:

- GUI installer resolves the GitHub canary release and verifies `WindowsCrashDoctor.exe` SHA-256 before installation or launch;
- installed build metadata records release id/tag, target commit and verified digest;
- CLI installer no longer elevates merely to install into the current user's profile;
- CLI installer downloads a release-built engine ZIP, verifies SHA-256, runs package self-tests before activation, then lets the diagnostic runner request UAC only for collection;
- the double-click `.cmd` bootstrap verifies the GUI installer script checksum before executing it;
- release manifest records commit, product/engine/rule versions, verification stages and per-asset SHA-256.

The EXE remains unsigned, so SmartScreen can still report **Unknown Publisher**. Authenticode signing remains separate work rather than being falsely implied by hash verification.

## AUD-006 — desktop behavioural verification

Implemented packaged behavioural smoke coverage for:

- extraction of every required engine component;
- embedded telemetry analysis via the actual extracted PowerShell CLI;
- JSON report production;
- product/engine provenance in reports;
- privacy-export planning, high-risk exclusion, secret/identifier redaction and ZIP manifest generation.

This does not replace a future full WPF UI automation suite, but release publication no longer treats `dotnet publish` alone as desktop correctness.

## AUD-007 — privacy-aware export

Implemented:

- export now creates a plan before writing a ZIP;
- UI shows included, excluded and redaction counts before confirmation;
- high-risk opaque artefacts such as dumps, EVTX, ETL, packet captures and screenshots are excluded from the shareable derivative by default;
- unknown binary formats are fail-closed rather than copied blindly;
- private-key material causes the containing text file to be excluded;
- common BitLocker recovery-password, token, credential-like value, email, Windows user-path and MAC-address patterns are redacted from text derivatives;
- files are reclassified immediately before copy so a post-preview change cannot bypass policy;
- `export-manifest.json` records every included/excluded file and redaction count;
- original evidence is never modified.

This scanner is intentionally conservative and is not claimed to discover every possible secret or identifier.

## AUD-008 — version and provenance identity

Implemented canonical `windows-crash-doctor/version.json` with:

- product version;
- engine version;
- collector version;
- rule-set version;
- report schema version.

Desktop builds also carry source-revision identity, and extracted engines write `build-info.json`. Snapshot and dump JSON reports now include a `Product` provenance object; Markdown reports include build provenance as well.

## Release definition after this change

A canary executable is publishable only when the Product Gate proves the same commit through the full engine suite and packaged desktop smoke path. A green compile on its own is no longer a release signal.

Remaining post-P0 work is intentionally separate: Authenticode signing, broader secret classification, full UI automation, stable versioned release channels, SQLite incident history and the larger typed `EvidenceBundle`/incident architecture from the audit.
