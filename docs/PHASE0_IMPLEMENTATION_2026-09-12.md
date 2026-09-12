# Phase 0 repository-audit remediation — 12 September 2026

This document records the concrete remediation implemented from the P0 section of [`REPOSITORY_AUDIT.md`](REPOSITORY_AUDIT.md). It is an **implementation record**, not by itself a claim that a packaged release passed CI. The **Windows Crash Doctor Product Gate** and [`RELEASE_VERIFICATION.md`](RELEASE_VERIFICATION.md) are the authorities for release verification.

Current source identity is product **0.3.0-preview.1**, engine **0.3.0**, collector **0.2.0**. The collector version is intentionally separate from the product/engine version.

## AUD-001 — release gating

Implemented:

- replaced independent desktop build/publish behaviour with a two-stage **Product Gate**;
- verification job has read-only repository permissions;
- release publication depends on successful PowerShell parsing, PSScriptAnalyzer, snapshot/telemetry/dump/integration tests, public-evidence guard, desktop compilation and packaged-EXE smoke testing;
- only the final release job receives `contents: write`;
- release job downloads the exact previously verified artifact and rechecks SHA-256 before publishing;
- rolling release is explicitly a **Canary / advanced preview**, not stable.

**Verification rule:** if `WindowsCrashDoctor.exe --self-test` fails, release bundle creation/upload and canary publication must remain blocked even when all checkout-level engine tests are green.

## AUD-002 — telemetry regression

Implemented:

- removed the original nested HWiNFO collection shape that broke row enumeration;
- normalized PowerShell 5.1 collection/cardinality handling;
- expanded regression coverage for zero/one/many rows, duplicate HWiNFO headings, malformed/partial input, bounded negative evidence and workload bursts;
- telemetry self-tests cover both HWiNFO CSV and LibreHardwareMonitor JSONL paths.

The Product Gate still remains the authority for whether this telemetry implementation also works correctly from the **embedded packaged engine**.

## AUD-003 — complete embedded engine

Implemented:

- `TelemetryAnalysis.psm1` is an embedded desktop resource;
- canonical diagnostic-registry files and `version.json` are embedded;
- current extracted engine path is versioned as **`0.3.0`**;
- missing required embedded resources fail explicitly rather than silently degrading;
- packaged desktop executable exposes headless `--self-test` to prove telemetry/registry/provenance through the extracted engine.

The earlier `0.2.0` extraction wording is obsolete.

## AUD-004 — telemetry pipeline unification

Implemented:

- telemetry analysis accepts supported HWiNFO-style CSV and Windows Crash Doctor / LibreHardwareMonitor JSONL;
- both providers flow through the same bounded telemetry summary/finding model;
- provider-specific absence is not converted into invented negative evidence — LibreHardwareMonitor does not claim clean WHEA or drive-health signals when those were not captured;
- recent desktop deep-sensor files stored beside a snapshot are only associated inside a bounded incident-time window to reduce stale-evidence contamination.

## AUD-005 — installer and release trust

Implemented in current source:

- GUI installer resolves the canary release and verifies `WindowsCrashDoctor.exe` SHA-256 before installation/launch;
- installed-build metadata records release/tag, target commit and verified digest;
- CLI installer stays in standard-user mode, downloads a release-built engine ZIP, verifies SHA-256 and runs package self-tests before activation;
- diagnostic runner requests UAC when collection requires elevation;
- double-click bootstrap verifies the GUI installer script before executing it;
- Product Gate release manifest records source commit, versions, verification stages and per-asset SHA-256 values;
- release job re-verifies asset hashes after artifact handoff before publication.

The EXE remains unsigned. Authenticode signing is future stable-release hardening and must not be implied by SHA-256 verification.

## AUD-006 — desktop behavioural verification

Implemented packaged/self-test coverage for:

- extraction of required embedded engine components;
- embedded telemetry analysis via the actual extracted PowerShell CLI;
- JSON report production and matching product/engine provenance;
- diagnostic-registry completeness/uniqueness and registry-backed expected coverage count;
- process timeout classification and process-tree cleanup;
- basic previous-run comparison semantics;
- privacy-export planning, high-risk exclusion, redaction and ZIP manifest generation.

This does not replace a future full WPF UI automation/accessibility suite.

## AUD-007 — privacy-aware export

Implemented:

- export creates a plan before writing a ZIP;
- UI shows include/exclude/redaction/sensitive-match counts before confirmation;
- high-risk opaque artefacts such as dumps, EVTX, ETL, packet captures and screenshots are excluded by default;
- unknown binaries fail closed instead of being copied blindly;
- private-key text is excluded;
- supported BitLocker/token/credential/API-key/JWT/email/user-path/MAC patterns are redacted from text derivatives;
- secret-pattern metadata does not expose the matched secret value;
- files are reclassified immediately before copy;
- `export-manifest.json` records inclusion/exclusion/redaction metadata;
- original evidence is never modified.

The scanner is intentionally conservative and is not claimed to discover every possible secret or identifier.

## AUD-008 — version and provenance identity

Implemented canonical `windows-crash-doctor/version.json` with separate:

- product version;
- engine version;
- collector version;
- rule-set version;
- report schema version;
- diagnostic-registry version.

Desktop builds carry source-revision identity. Extracted engines write build identity, and snapshot/dump reports include product provenance.

## Additional v2 architecture implemented after the original P0 pass

Several capabilities that older roadmaps still described as future now exist in source:

- SQLite `history.db` run ledger with normalized run/finding/collector/comparison tables and legacy JSON migration;
- device, finding and evidence-bundle SHA-256 fingerprints;
- previous comparable-run comparison with coverage-aware change states;
- preflight/self-check before diagnosis;
- canonical diagnostic-registry metadata/coverage/provenance;
- bounded timeout/cancellation/retry runner for desktop PowerShell operations;
- report enrichment with run/preflight/comparison/registry provenance.

These do **not** mean every original v2 acceptance criterion is finished. Registry-driven collector command dispatch and true per-probe execution timing/retry remain partial, and focused packaged coverage is not exhaustive for SQLite/preflight/UI paths. See [`GITHUB_BORROW_ROADMAP.md`](GITHUB_BORROW_ROADMAP.md).

## Current release-verification state

The Phase 0 implementation is substantially present in source, but **P0 release completion requires a green Product Gate for the intended commit and successful publication of that exact verified artifact**.

A3's independent verification snapshot is maintained in [`RELEASE_VERIFICATION.md`](RELEASE_VERIFICATION.md). At the A3 branch point, the latest completed gate had passed parser, analyzer, core snapshot, telemetry, dump, integration, privacy guard and desktop build stages, but failed the packaged EXE telemetry smoke test, so release packaging/publication was correctly blocked.

## Release definition after this change

A canary executable is publishable only when the Product Gate proves the same commit through the full engine suite and packaged desktop smoke path, builds the release manifest/checksums, uploads the exact verified artifact and then rechecks that artifact before publishing the rolling canary.

A green compile or green checkout-level engine test is not a release signal by itself.

## Remaining post-P0 / stable-release work

Intentionally separate from immediate P0 release completion:

- Authenticode/code signing and publisher trust;
- immutable semantic stable-release channel distinct from the rolling canary;
- stronger supply-chain pinning, SBOM and build provenance/attestation;
- broader secret/PII classification and retention/purge policy;
- full WPF UI automation/accessibility/localisation coverage;
- true registry-driven per-probe orchestration and structured probe execution metadata;
- typed `EvidenceBundle` / incident architecture and a full crash/incident catalogue beyond the current diagnostic run ledger;
- deeper WER, ETW, symbol/stack, proactive capture, deduplication and timeline work from the 100-item roadmap.