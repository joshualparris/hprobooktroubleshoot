# Windows Crash Doctor — GitHub Borrow Roadmap

**Status:** Active implementation/status roadmap  
**Audit date:** 12 September 2026  
**Current source target:** Windows Crash Doctor `0.3.0-preview.1` / engine `0.3.0`

This roadmap records reusable engineering patterns borrowed from Josh's other repositories and their current Windows Crash Doctor implementation state.

The goal is **not** to blindly copy whole files. The goal is to reuse proven ideas, data models and small implementation patterns where they materially improve Crash Doctor while keeping Crash Doctor evidence-first, conservative and Windows-specific.

## Status legend

- **Implemented** — the core capability exists and is wired into the current product path.
- **Verified** — focused tests currently exercise the stated behaviour. Release verification still requires the Product Gate for the exact packaged commit.
- **Partial** — useful implementation exists, but one or more original acceptance criteria remain incomplete.
- **Future** — not materially implemented yet.

These labels describe source/test state. See [`RELEASE_VERIFICATION.md`](RELEASE_VERIFICATION.md) before claiming a packaged canary is verified.

## Core borrowing rules

1. **Understand before changing.** Read the Crash Doctor path and source implementation before porting anything.
2. **Adapt intent, not accidental structure.** Translate Python/TypeScript patterns into PowerShell/C# where that keeps the architecture coherent.
3. **One concept → one source of truth.** Do not create parallel history, redaction, retry or finding models.
4. **Read-only diagnosis remains the default.** Borrowed automation must not silently modify firmware, drivers, security, BitLocker or OS policy.
5. **Partial failure must stay visible.** A failed collector becomes explicit coverage/degraded-state evidence; it must not silently disappear.
6. **Evidence beats inference.** Borrowed components may improve collection, provenance, resilience and comparison, but diagnosis must still separate observation, interpretation, confidence and causality.
7. **Every borrowed behaviour gets tests.** A feature is not complete merely because implementation code exists.

---

## Source repositories and adaptations

| Source repo | Existing pattern worth reusing | Crash Doctor adaptation | Current state |
|---|---|---|---|
| `joshualparris/Action1` | Diagnostic registry, JSON diagnostic output, SQLite history, stdout/stderr/status/timing, cancellation/timeout | Canonical diagnostic metadata/coverage registry, SQLite run ledger, structured process result model | **Implemented / partial** |
| `joshualparris/DadlanControlCentre` | Failure isolation and derived health from independent observations | Preflight health states and degraded/unknown coverage rather than all-or-nothing diagnosis | **Implemented** |
| `joshualparris/Transfer` | Retry classification/backoff, resumable statuses, fingerprints, central redaction | Process retry classification, evidence/finding fingerprints, comparison and shared redaction | **Implemented / partial** |
| `joshualparris/AgentCheck` | Secret scanning that reports metadata without exposing matched secrets | Privacy-reviewed export scanner and secret-pattern metadata | **Implemented / tested** |
| `joshualparris/chronos` | Environment/health preflight with degraded-mode warnings | Crash Doctor preflight for environment, engine, evidence, history and optional tooling | **Implemented** |
| `joshualparris/JoshMemory` | Provenance, source identity, confidence and timestamped records | Finding/evidence provenance, registry/rule versions and run-to-run comparison metadata | **Implemented / partial** |

---

# Roadmap status

## Phase 1 — Diagnostic registry

**Status: PARTIAL — implemented foundation, original acceptance criteria not fully complete.**

Implemented now:

- canonical `windows-crash-doctor/diagnostics/registry.json` with stable IDs, names, descriptions, categories, expected evidence files, administrator metadata, default timeouts, retry policy, sensitivity, failure mode and rule version;
- registry version/schema identity;
- PowerShell and C# validation of unique IDs and required metadata;
- report coverage derived from registry expectations;
- registry provenance attached to reports;
- desktop preflight and status display consume the same registry identity;
- packaged desktop self-test checks registry completeness/uniqueness and that report coverage count comes from the registry.

Still incomplete against the original target:

- command/implementation dispatch is **not** wholly generated from registry entries;
- adding one registry definition does not yet automatically create the collector implementation in CLI/desktop;
- collector execution is still partly monolithic rather than one independently orchestrated operation per registry diagnostic.

### Acceptance status

- Unknown/invalid registry state fails explicitly: **implemented**.
- Registry IDs unique and tested: **implemented/tested**.
- UI/CLI share registry metadata/coverage source: **implemented**.
- Collector coverage from registry expectations: **implemented**.
- Collector command dispatch from the registry alone: **not complete**.

---

## Phase 2 — Resilient collector/execution engine

**Status: PARTIAL — structured runner implemented and tested; per-probe orchestration remains incomplete.**

Implemented in `PowerShellRunner`:

- start/finish timestamps and duration;
- exit code;
- stdout/stderr;
- statuses for completed, completed-with-warnings, cancelled, timed-out, failed-retryable, failed-permanent, unavailable and skipped-not-applicable;
- linked cancellation;
- bounded timeout;
- entire process-tree termination;
- bounded retry count;
- transient failure classification;
- exponential backoff with jitter;
- redacted failure logging.

The packaged desktop self-test explicitly exercises timeout classification and prompt process termination.

Still incomplete against the original phase:

- the current collector is largely one PowerShell process;
- per-diagnostic collector records are partly inferred from expected evidence-file outcomes;
- individual probes therefore do not yet all have their own actual subprocess duration/exit/timeout/retry lifecycle;
- local deterministic collector probes are not yet all dispatched through a uniform registry-driven runner.

### Acceptance status

- Timed-out desktop PowerShell operations kill process trees: **implemented/tested**.
- Cancelled versus timed-out status: **implemented in runner**.
- Bounded retry policy: **implemented in runner**.
- Partial/degraded evidence preserved: **implemented at report/coverage level**.
- Every collector probe independently timed/classified: **not complete**.

---

## Phase 3 — Replace flat JSON history with a durable run ledger

**Status: IMPLEMENTED.**

The desktop now uses SQLite `history.db` under `%LOCALAPPDATA%\WindowsCrashDoctor` with WAL/foreign-key support and normalized tables for:

- `runs`;
- `findings`;
- `collector_executions`;
- `run_comparisons`.

Run records include run identity/time/status, device/evidence fingerprints, product/rule versions, duration, finding counts, coverage, collector outcome counts and comparison summary.

Implemented migration behaviour:

- legacy `history.json` is imported when appropriate;
- the original is moved to `.migrated` after successful migration;
- migration failure leaves the legacy file untouched and surfaces a startup warning;
- SQLite health is included in preflight;
- latest comparable run can be queried by device fingerprint.

### Verification note

This is integrated source functionality. The current packaged desktop self-test does **not** independently exercise every SQLite migration/query path, so do not overstate it as exhaustive release verification.

---

## Phase 4 — Evidence fingerprints + before/after comparison engine

**Status: IMPLEMENTED, PARTIALLY VERIFIED.**

Implemented:

- SHA-256 device fingerprint;
- SHA-256 evidence-bundle hash;
- stable finding fingerprint using finding/rule/evidence semantics rather than Markdown formatting;
- provenance stamping with source collector and rule version;
- comparison to the latest comparable run for the same device;
- states `NEW`, `RESOLVED`, `UNCHANGED`, `IMPROVED`, `WORSENED`, `UNKNOWN`;
- coverage guard so absence under poor coverage becomes `UNKNOWN` rather than false `RESOLVED`;
- comparison trust classification;
- report JSON/Markdown enrichment and desktop recommendation summary;
- persistence to the SQLite run ledger.

Focused desktop self-test covers baseline comparison, NEW, RESOLVED, IMPROVED and UNCHANGED semantics.

Still desirable:

- dedicated regression fixtures for WORSENED and UNKNOWN;
- stronger schema/rule-version compatibility handling for long-lived histories;
- metric-aware IMPROVED/WORSENED beyond severity changes for richer numerical finding families.

---

## Phase 5 — Shared redaction + Safe Evidence Export

**Status: IMPLEMENTED and behaviourally tested in the desktop self-test.**

Implemented:

- shared redaction service used by desktop process/error paths;
- export planning before ZIP creation;
- UI preview with included/excluded/redacted/sensitive-match counts;
- default exclusion of high-risk opaque evidence such as dumps, EVTX, ETL, packet captures and screenshots;
- fail-closed treatment of unknown/unscannable binaries;
- private-key text exclusion;
- redaction of supported BitLocker/token/credential/API-key/JWT/email/user-path/MAC patterns from text derivatives;
- secret scanner metadata that records pattern type/line without exposing the secret value;
- reclassification immediately before copy;
- `export-manifest.json` with inclusion/exclusion/redaction metadata;
- originals left unchanged.

The desktop self-test asserts that known fake secrets do not survive in the exported derivative or manifest and that high-risk fixtures remain excluded.

Still future/post-P0:

- exhaustive secret/PII detection is impossible to claim;
- broader format-aware redaction/classification and retention policy;
- organization-specific export policies.

---

## Phase 6 — Crash Doctor self-check / preflight

**Status: IMPLEMENTED.**

Current preflight checks:

- Windows platform;
- administrator state;
- embedded engine extraction and required files;
- diagnostic registry;
- evidence output writability and free space;
- SQLite run-ledger health;
- Windows PowerShell availability/version;
- WMI/CIM;
- Windows Event Log access;
- crash-dump configuration;
- WinDbg/cdb availability;
- symbol-path configuration;
- LibreHardwareMonitor/HWiNFO provider presence.

Health states include `healthy`, `degraded`, `unavailable` and `not-configured`. Blocking unavailable prerequisites prevent a full diagnosis; optional gaps can remain degraded/not configured. Preflight is refreshed at diagnosis start and included in report/run provenance.

Still desirable:

- more direct symbol-service reachability testing;
- richer provider-version/platform-support checks;
- focused automated coverage for every preflight state and UI presentation.

---

## Phase 7 — Desktop/report integration

**Status: PARTIAL — major backend/report integration exists; full intended UI treatment remains incomplete.**

Integrated now:

- preflight status at startup/run time;
- run status/duration/provenance;
- SQLite-backed history;
- finding fingerprints;
- previous-run comparison and trust summary;
- report fields for run/preflight/collector/comparison/registry provenance;
- privacy-reviewed export screen;
- explicit degraded/missing evidence in report enrichment.

Still incomplete from the original desktop vision:

- a dedicated rich preflight/self-check panel rather than primarily status/log output;
- comprehensive visual comparison badges/details for all findings;
- broad WPF UI automation/accessibility coverage;
- deeper provenance drill-down UI;
- richer per-probe execution timing once collector orchestration is split.

---

## Phase 8 — QA, migration and rollout

**Status: PARTIAL — strong release gate exists, but rollout is not complete until the packaged gate is green for the intended commit.**

Current QA includes:

- PowerShell parser and PSScriptAnalyzer gates;
- snapshot/telemetry/integration regression tests;
- synthetic dump tests plus real DbgHelp minidump smoke test;
- Pester integration suite;
- public-evidence guard;
- packaged `WindowsCrashDoctor.exe --self-test` for embedded engine/provenance/registry coverage;
- desktop self-tests for process timeout cleanup, comparison basics and privacy export;
- release bundle manifest + per-asset SHA-256 generation;
- artifact handoff verification before canary publication.

The Product Gate is intentionally the rollout authority. A source feature is not “release verified” merely because its focused test passes.

At the A3 branch point, the latest completed Product Gate had passed every checkout-level engine/build stage but failed the **packaged EXE telemetry self-test**, so release packaging/publication was correctly blocked. See [`RELEASE_VERIFICATION.md`](RELEASE_VERIFICATION.md) for the exact run/commit and the acceptance checklist.

---

# What we deliberately did not copy

## Action1 basic system snapshot

Crash Doctor already collects richer Windows evidence. The useful borrowing is registry/execution/history architecture, not a weaker duplicate collector.

## DadLAN-specific machine/integration assumptions

SMB mount counts, MeshCentral addresses, ForgeGrid definitions and DadLAN topology are not Crash Doctor product concepts. Only failure-isolation/health-state patterns belong here.

## Transfer domain logic

Gmail/calendar/contact migration logic is irrelevant. Retry classification, fingerprints, durable state and redaction patterns are the reusable parts.

## AgentCheck product identity

AgentCheck's code/LLM-claim verification remains a separate product. Crash Doctor borrows privacy-preserving secret-scanner behaviour only.

## Unrelated game/UI code

A reuse candidate must materially improve diagnostics, evidence quality, safety, resilience, provenance or user comprehension.

---

# Current implementation order from here

The original foundational order has largely been executed. Remaining work should now close acceptance gaps rather than re-implementing parallel versions:

1. make the packaged Product Gate green for the intended `0.3.0-preview.1` commit;
2. independently verify release artifact, manifest/checksums and canary target;
3. move collector probe dispatch/execution metadata closer to the canonical registry;
4. add missing comparison/preflight/SQLite failure-path tests;
5. improve desktop presentation/UI automation without replacing the underlying models;
6. build the typed evidence/incident architecture and full crash catalogue as post-P0 work;
7. add stable-channel productisation (immutable versions, signing, stronger provenance/SBOM).

---

# Definition of Windows Crash Doctor v2 for this roadmap

The v2 flow is:

> **preflight → collect → isolate partial failures → analyse → fingerprint → persist → compare → explain what changed → recommend the next discriminating test → export safely**

Most of that flow now exists in source. “v2 release complete” still requires the current packaged executable to pass the Product Gate and the canary to be independently verified for that exact commit. Some deeper original acceptance criteria — especially true registry-driven per-probe orchestration and richer UI/QA — remain partial rather than being hidden behind a blanket “implemented” label.

A v2 diagnosis should answer:

- What evidence was successfully collected?
- What failed to collect and why?
- What changed since the previous comparable run?
- Which findings are new, resolved, improving or worsening?
- How trustworthy is that comparison?
- What is the next test that most efficiently separates the remaining hypotheses?
- Can this evidence bundle be shared without exposing obvious secrets?

That remains the useful engineering target, while the much larger 100-item crash/ETW/WER/symbol roadmap continues separately.