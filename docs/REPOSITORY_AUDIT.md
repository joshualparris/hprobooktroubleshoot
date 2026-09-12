# Repository engineering audit

Audit date: **12 September 2026**  
Repository: `joshualparris/hprobooktroubleshoot`  
Audit baseline: `08add035799b7e21d4c91a1bd70d205ed74ece57` (`main` at audit completion)  
Scope: the whole repository — ProBook case material, Windows Crash Doctor engine, collector, telemetry, dump parser, integrations, desktop application, installers, CI/release workflows, evidence/privacy controls, documentation and engineering governance.

> This is the canonical **quality/risk audit**, not another feature wishlist. `ROADMAP_100.md` remains useful as a capability backlog. This document asks a different question: **does the repository form a coherent, safe, testable and releasable product today, and what must change to make it one?**

## Executive assessment

Windows Crash Doctor has an unusually good diagnostic principle at its centre: keep observation, evidence, interpretation and causality separate. The core PowerShell findings model already encodes severity, confidence, evidence, interpretation and next step, and the ProBook case has forced the project to deal with genuinely messy Windows evidence rather than toy examples.

The weakness is no longer lack of ambition. It is **composition**. The repository now contains a collector, rule engine, telemetry parser, dump parser, integration manager, installer, WPF desktop application and automated release pipeline, but those pieces are moving faster than the contracts and tests joining them together. Several user-visible claims are therefore stronger than the end-to-end behaviour that is currently proven.

The most important change is cultural and architectural:

**Stop measuring progress by how many components exist. Measure it by whether one versioned, tested evidence path works end-to-end from collection → normalisation → analysis → report/history → privacy-reviewed export → reproducible release.**

### Overall maturity scorecard

| Area | Score | Assessment |
|---|---:|---|
| Evidence-first diagnostic discipline | **8/10** | Strongest part of the project; careful wording and bounded claims are already visible in the engine. |
| HP ProBook case investigation | **8/10** | Rich evidence, hypothesis tracking and controlled test philosophy; still mixed into product code/documentation more than ideal. |
| Core snapshot analyser | **6/10** | Useful real rules and synthetic tests, but text/regex contracts are brittle and coverage is file-based rather than capability-based. |
| Telemetry analysis | **4/10** | Good direction and real incident-derived heuristics, but current CI regression and multiple disconnected telemetry formats show that it is not yet a stable subsystem. |
| Dump analysis | **6/10** | Sensible bounded native-parser foundation; documentation correctly avoids claiming full debugger capability. Needs fuzzing, symbols and real kernel-dump depth. |
| Desktop user experience | **6/10** | Substantial usable surface very quickly; architecture and testability have not caught up with the feature set. |
| Desktop/core integration | **3/10** | Critical missing embedded telemetry module and sensor-format disconnect mean the EXE is not yet equivalent to the documented engine. |
| Automated testing | **5/10** | Core PowerShell QA is better than many early projects, but current `main` has had a failing telemetry test while desktop releases still publish; desktop has essentially no behavioural test suite. |
| Release engineering | **3/10** | Automated builds exist, but release is not gated on full product health and mutable rolling artifacts weaken reproducibility. |
| Installer/supply-chain security | **2/10** | Installers trust mutable downloads without verifying the published hash/signature/attestation before execution; CLI installer elevates mutable `main`. |
| Privacy/evidence safety | **5/10** | Policy is thoughtful and local-first; implementation of export/redaction/secret detection remains much narrower than the policy and UI wording imply. |
| Generic Windows portability | **4/10** | Product is becoming generic but still carries HP/ProBook naming, OEM filters and case-specific assumptions in canonical paths. |
| Maintainability | **5/10** | Modules are separated at repo level, but several modules/classes are already monolithic and contracts are implicit. |
| Documentation | **7/10** | Strong amount of documentation and explicit limitations; needs a shipped/partial/planned status model and stricter truth checks against code. |
| Governance/reproducibility | **4/10** | Fast iteration is productive, but direct `main` construction and rolling release behaviour allow implementation to outrun verification. |
| Product readiness | **4/10** | Valuable advanced prototype; not yet a trustworthy general-purpose diagnostic product to install broadly. |

## What is already worth preserving

Do not “clean up” the following strengths away while refactoring:

1. **Evidence / interpretation / causality separation.** This should remain the central product philosophy and become part of the typed data model.
2. **Missing data means unknown, not healthy.** Preserve this in every future adapter and UI.
3. **Negative evidence is time-bounded.** The recent sensor/power work correctly treats a clean interval as bounded evidence rather than a universal hardware clearance.
4. **Read-only analysis by default.** Collection/analysis and remediation are sensibly separated.
5. **Local-first evidence handling.** Keep uploads and external integrations opt-in.
6. **Synthetic regression fixtures.** Continue using small, readable fixtures for rules and add real-world corpora around them.
7. **Explicit roadmap limitations.** The dump parser documentation is a good example: useful foundation without pretending to be WinDbg.
8. **Case provenance.** The ProBook investigation has historical value; preserve it, but separate it structurally from the generic product.

---

# P0 — issues that should block calling a build releasable

These are not “nice to have”. They are integration, correctness or trust problems.

## AUD-001 — Core QA is not an enforced release gate

**Severity:** Critical  
**Area:** CI / release governance

A Windows Crash Doctor core workflow can be red while the desktop build/release workflow independently succeeds and publishes a new executable. That creates a false-green product state: the UI artifact looks healthy even when the engine regression suite is not.

### Required change

Create one required product gate that must pass before release publication:

`PowerShell parser → PSScriptAnalyzer → snapshot tests → telemetry tests → dump tests → integration tests → desktop unit/integration tests → packaging smoke → security/privacy checks → release`.

### Acceptance criteria

- A failing engine test prevents any stable or rolling desktop release from being published.
- Release workflow consumes an already-tested commit/artifact rather than rebuilding an unverified state.
- GitHub UI exposes one obvious “product green/red” status for the commit.
- `main` documentation does not say “tested” when the required gate is red.

## AUD-002 — Telemetry regression is currently not healthy

**Severity:** Critical  
**Area:** Engine correctness

`TelemetryAnalysis.psm1` currently returns the CSV row collection using `,$rows`; the caller then wraps the result again with `@(Import-SensorCsv ...)`. This can make the first element an array rather than a sensor row, causing column discovery to operate on the array object instead of the row properties. The telemetry self-test has exposed the problem.

### Required change

Return rows in a single predictable enumeration contract, then add parser tests for:

- one row;
- many rows;
- duplicate headings;
- BOM/UTF-8/Windows-1252 inputs;
- malformed rows;
- missing columns;
- localized/renamed sensor headings;
- empty files.

### Acceptance criteria

- Telemetry self-test is green on Windows PowerShell 5.1 and PowerShell 7.
- HWiNFO fixture produces expected memory, temperature, WHEA and continuity findings.
- Parser API contract is documented and no caller depends on PowerShell array-shape accidents.

## AUD-003 — Desktop EXE does not embed the complete analysis engine

**Severity:** Critical  
**Area:** Desktop/core integration

The desktop project embeds `CrashDoctor.psm1`, `DumpParser.psm1`, the CLI, integrations and collector, but **does not embed `TelemetryAnalysis.psm1`**. `EngineExtractor` also has no mapping for it. The CLI only loads telemetry when that module exists, so the desktop “full diagnosis” can silently omit telemetry analysis while the repository/CLI path supports it.

### Required change

Make embedded engine contents declarative and test them. Prefer a manifest rather than manually duplicating the list in both `.csproj` and `EngineExtractor`.

### Acceptance criteria

- Built EXE contains every module required by the CLI at that commit.
- CI extracts the engine from the built EXE into a temp directory and runs a full telemetry fixture through it.
- Missing required resources fail application startup loudly rather than degrading silently.
- App report includes app version, engine version, rule-set version and Git commit.

## AUD-004 — Deep sensor capture and telemetry analysis are separate pipelines

**Severity:** High  
**Area:** Telemetry architecture

The GUI’s LibreHardwareMonitor deep capture writes `sensor-*.jsonl`. The snapshot telemetry analyser searches for HWiNFO-style `sensor*.csv` / `hwinfo*.csv`. A user can therefore run “deep sensor capture” and “full diagnosis” and reasonably assume the former informs the latter when the two formats are not joined into one incident/evidence model.

### Required change

Introduce a canonical telemetry schema and provider adapters:

`HWiNFO CSV → normalized samples`  
`LibreHardwareMonitor JSONL → normalized samples`  
`future ETW/perf counters → normalized samples`

Each sample stream needs provider/version, host, capture start/end, monotonic ordering, units, semantic sensor IDs and incident/run ID.

### Acceptance criteria

- A GUI deep-sensor session can be attached to the next/current diagnostic run.
- The same memory/thermal/WHEA/continuity rules work regardless of source provider.
- UI explicitly shows which telemetry streams contributed to each finding.

## AUD-005 — Installers do not verify downloaded first-party artifacts before execution

**Severity:** Critical  
**Area:** Supply chain

The GUI installer downloads the mutable `windows-crash-doctor-desktop-latest` executable, checks only that it is larger than 1 MB, copies it into the app directory, calls `Unblock-File` and launches it. A SHA-256 asset exists but the installer does not fetch and verify it.

The console installer is more concerning: it self-elevates, downloads `main.zip`, installs it and executes PowerShell from that mutable branch with `ExecutionPolicy Bypass`, without pinning or verifying an immutable digest/signature.

### Required change

- Stable installer downloads immutable versioned artifacts only.
- Verify expected SHA-256 from a signed/attested release manifest before installation.
- Sign Windows binaries with Authenticode when practical.
- Keep a separate explicitly labelled canary channel if rolling `main` builds are useful.
- Do not `Unblock-File` an unverified/unsigned executable as a substitute for trust.

### Acceptance criteria

- Tampered binary/hash fixture causes install failure.
- Installer prints exact version, commit and verified hash before first launch.
- Stable installer cannot silently move to a different commit at the same version.
- Elevated installer never executes unverified mutable branch content.

## AUD-006 — Desktop publishing is a build check, not a product test

**Severity:** High  
**Area:** Desktop QA

The desktop workflow restores, publishes, checks that the EXE exists, writes a hash and publishes it. There is no C# behavioural test project, no embedded-engine execution smoke, no first-run smoke, no UI automation smoke and no verification that a “full diagnosis” produced a valid report.

### Required change

Add `desktop/WindowsCrashDoctor.Tests` and end-to-end packaging tests.

### Acceptance criteria

At minimum CI proves:

- settings/history serialization;
- engine extraction;
- exact embedded resource inventory;
- PowerShell command argument escaping;
- report JSON deserialization;
- full-diagnosis synthetic fixture;
- dump-analysis fixture;
- app starts and creates the main window on a Windows runner;
- release EXE hash matches published manifest.

## AUD-007 — “Privacy-aware ZIP export” currently overstates the implementation

**Severity:** High  
**Area:** Privacy / UX truthfulness

The desktop path warns that the bundle can contain sensitive data and then zips the evidence directory. That is **privacy-warning-aware**, not yet privacy-aware export in the stronger sense implied by the README/security design: there is no per-file preview, classification, default exclusion, redaction derivative or broad secret scan.

### Required change

Until implemented, rename the feature to something like **“Export diagnostic ZIP (review before sharing)”**. Then build the proper workflow:

1. manifest and hashes;
2. sensitivity classification;
3. file/field preview;
4. default exclusion of high-risk raw artefacts;
5. optional redacted derivative;
6. secret/PII checks;
7. explicit final confirmation.

### Acceptance criteria

- User can see every file about to leave the private evidence store.
- Dumps/EVTX/ETL/raw sensor logs are never silently included in a “safe” support export.
- Redaction never mutates the original evidence.

## AUD-008 — Release state is mutable and weakly reproducible

**Severity:** High  
**Area:** Release engineering

The rolling desktop release tag is deleted/recreated and points at the latest build. This is fine as an explicit canary convenience, but not as the primary trusted installation identity. App and embedded engine are also hard-coded as `0.1.0`, so materially different builds can present the same version.

### Required change

Use semantic immutable releases, e.g. `v0.2.0`, with commit SHA, source archive, binary hash, SBOM and build provenance. Keep `desktop-latest` only as a moving alias/canary.

### Acceptance criteria

Every report/history record contains:

- app version;
- engine version;
- collector version;
- rule-set/schema version;
- source commit SHA;
- provider versions.

---

# Detailed architecture audit

## 1. Product boundaries and repository shape

### AUD-009 — Case investigation and generic product are still too tightly coupled

The repository’s origin as a ProBook investigation remains visible in canonical collector naming (`HPProBook-*`), comments, OEM service filters and product documentation. That made sense while extracting the first rules, but it now creates three risks:

- generic users inherit case-specific assumptions;
- case evidence/privacy concerns live close to distributable product code;
- changes intended for one machine can accidentally become universal diagnostic policy.

**Target:** keep one repo if desired, but formalise boundaries:

```text
src/ or windows-crash-doctor/        generic engine
profiles/hp-probook-11-g2/           OEM/case-specific rules and knowledge
cases/hp-probook-11-g2/              investigation reasoning/public reviewed evidence
desktop/                              generic UI
fixtures/                             sanitized test evidence
docs/                                 product docs/ADRs/audits
```

A later split into separate case and product repositories may be worthwhile, but a clean internal boundary should come first.

### AUD-010 — There is no single canonical evidence model

Today the system moves through formatted PowerShell text, EVTX binaries/text exports, HTML power reports, HWiNFO CSV, LibreHardwareMonitor JSONL, dump structures and report JSON. Regex and file names effectively act as interfaces.

**Target:** define a versioned `EvidenceBundle` manifest with normalized facts and raw-artefact references. Raw evidence remains preserved; rules operate primarily on normalized typed facts.

Example concepts:

```text
EvidenceBundle
  bundle_id
  schema_version
  captured_at_utc
  machine_id (local pseudonymous ID)
  collector_version / commit
  privilege_level
  locale / timezone
  probes[]
    id
    status = success|partial|failed|unauthorized|unsupported|timeout
    duration_ms
    raw_artifacts[] { path, sha256, sensitivity }
    normalized_facts[]
```

This solves localization, coverage, provenance and parsing reliability together.

## 2. Collection quality

### AUD-011 — “File exists” is not equivalent to “probe succeeded”

The collector writes an `ERROR:` line to an output file when a section fails. The core analyser’s coverage model can still count a non-empty file as present. This can overstate evidence completeness.

**Improve:** every probe returns structured status and error metadata. Coverage should report capability-level states, not merely `N / knownFiles`.

### AUD-012 — Collector lacks robust per-probe timeout/cancellation

Commands such as CIM queries, `msinfo32`, storage providers or power utilities can hang on exactly the machines Crash Doctor is designed to investigate.

**Improve:** run probes through a common executor with timeout, cancellation, duration, exit code and partial-result policy. One bad provider must not prevent the remaining collection.

### AUD-013 — Text formatting is an unstable machine interface

`Format-List`/`Format-Table` output and utilities such as `powercfg`, `manage-bde` and `pnputil` can differ by Windows build/localization.

**Improve:** emit normalized JSON directly for CIM/registry/API evidence while retaining raw text for human/forensic value. Add locale fixtures for any command that cannot be replaced with an API.

### AUD-014 — Collection provenance should be stronger

Add UTC and local timestamp/offset, Windows locale, PowerShell version, elevation level, collector SHA/version, probe duration, output hashes, boot ID and evidence-bundle ID. Run `hash-evidence.ps1` automatically as part of successful collection.

### AUD-015 — Generic collector should stop using `HPProBook-*` as canonical naming

Use `WindowsCrashDoctor-<machine>-<timestamp>-<bundleid>` or opaque bundle IDs. Preserve a compatibility alias temporarily if scripts depend on old names.

## 3. Rule engine

### AUD-016 — Rule input contracts are implicit

`CrashDoctor.psm1` is a useful but increasingly monolithic collection of regex-driven rules. Each rule should declare:

- rule ID + version;
- required/optional evidence facts;
- scope/time window;
- severity/confidence basis;
- profile applicability;
- references/description;
- deterministic unit fixtures.

Move to a registry/data-driven rule interface before adding dozens more detectors.

### AUD-017 — Findings need machine-readable provenance locators

A finding currently describes evidence in prose. Add structured references such as:

```json
{
  "source_artifact": "recent-system-events.json",
  "sha256": "...",
  "event_record_id": 1234,
  "timestamp_utc": "...",
  "json_pointer": "/events/17",
  "rule_version": "2"
}
```

That allows the UI to offer **Show evidence** and makes findings independently reproducible.

### AUD-018 — Bounded negative evidence should become a first-class field

The project already reasons this way. Encode it explicitly: `Scope`, `WindowStart`, `WindowEnd`, `EvidenceQuality`, `CanRuleOut=false`. This prevents future UI/AI layers from turning “not observed in 46 minutes” into “hardware healthy”.

### AUD-019 — OEM-specific rules should become profile packs

Firmware IDs, XTU/Conexant/HP-specific heuristics are valuable but should be loaded via profiles rather than living indistinguishably beside generic Windows invariants.

## 4. Telemetry

### AUD-020 — Sensor identity depends too heavily on display names

Hard-coded English headings such as `CPU Package [°C]` are brittle across HWiNFO versions/locales/providers.

**Improve:** provider adapter maps provider-native keys to semantic IDs (`cpu.package.temperature.c`, `memory.physical.load.percent`, etc.). Preserve original name/unit beside normalized identity.

### AUD-021 — CSV encoding handling is too narrow

Telemetry parser currently uses a fixed legacy encoding. Add BOM/UTF-8 detection with explicit fallback and tests for non-ASCII degree/unit characters.

### AUD-022 — Thresholds need provenance and context

Rules such as RAM >90% or thermal thresholds are reasonable heuristics, but should be configured/documented by rule version and, where useful, adjusted by hardware baseline rather than buried as literals.

### AUD-023 — Observer overhead needs measurement

Crash Doctor is diagnosing low-resource/failing machines. The desktop currently mixes lightweight native CPU/RAM calls with periodic PowerShell/CIM temperature/storage queries and optional deeper monitoring. Record Crash Doctor’s own CPU/memory/I/O overhead and back off when the host is stressed.

## 5. Dump analysis

### AUD-024 — Product wording must distinguish structure parsing from debugger-grade diagnosis

Current engine documentation does this reasonably well; keep the UI equally explicit. Use “Dump structure summary” until symbolized stack/root-cause features exist.

### AUD-025 — Treat dumps as hostile/untrusted binary input

Add fuzz/property tests, integer-overflow checks, maximum count/allocation limits, malformed RVA/size corpora and time/memory ceilings. A diagnostic parser should not itself become a denial-of-service path.

### AUD-026 — Build a real sanitized dump corpus

Synthetic fixtures are excellent for determinism. Add legally safe real minidumps and eventually kernel-dump fixtures across Windows versions/architectures with expected parsed facts.

## 6. Desktop application architecture

### AUD-027 — `MainWindow.xaml.cs` owns too many responsibilities

Navigation, diagnostics, provider management, dump analysis, sensors, history, export and theming are converging in one code-behind class. This makes behaviour difficult to unit test and encourages hidden coupling.

**Target:** MVVM/application-service boundaries:

```text
Views
ViewModels
Application services
  DiagnosticRunService
  SensorCaptureService
  DumpAnalysisService
  ExportService
  ProviderService
Infrastructure
  PowerShellEngineHost
  HistoryRepository
  EvidenceStore
```

Use dependency injection so tests can substitute deterministic fakes.

### AUD-028 — PowerShell execution surface should be narrowed

A generic “run a command string” interface is harder to audit and safely quote than strongly typed operations.

**Improve:** expose explicit functions (`CollectAsync`, `AnalyseSnapshotAsync`, `AnalyseDumpAsync`, `ManageProviderAsync`) and pass arguments as escaped argv rather than interpolated command text. Consider hosting PowerShell through SDK/runspaces if that meaningfully improves cancellation/typing.

### AUD-029 — Whole GUI should not need long-lived admin rights

Run UI unelevated. Spawn a short-lived, narrowly scoped elevated collector/helper when a probe needs admin rights, returning evidence into the user-owned store. This reduces attack surface and makes privilege state obvious.

### AUD-030 — Silent exception swallowing is unacceptable in a diagnostic product

History/settings/UI helper paths currently swallow some failures. Diagnostics software must distinguish “nothing found” from “we failed to read it”. Add structured local logs and user-visible degraded-state messages.

### AUD-031 — Accessibility requires explicit testing

Add keyboard-only navigation, focus order, automation names, high-contrast checks, 125–200% scaling, non-colour severity indicators and screen-reader announcements for long-running status changes.

### AUD-032 — Hard-coded English strings limit future locale support

Move UI strings/resources early, before the surface grows further. Localization matters particularly because Windows command output/locales are already a parser concern.

## 7. History and incident model

### AUD-033 — `history.json` is not yet an incident database

Current history is capped to 30 entries and rewrites a JSON file. Corruption is silently treated as empty history. It cannot model multiple evidence streams and follow-up analysis cleanly.

**Improve:** SQLite (or another transactional embedded store) with schema migrations and explicit relationships:

```text
Incident
  Run(s)
  Evidence bundle(s)
  Sensor stream(s)
  Dump(s)
  Finding instances
  User notes
  Change/test stage
```

Keep raw evidence as files with hashes; store metadata/indexes in DB.

### AUD-034 — History writes should be atomic even before SQLite migration

Until then use temp-file + fsync/replace, corruption backup and visible recovery message.

## 8. Privacy, security and evidence storage

### AUD-035 — Public evidence guard is intentionally but dangerously narrow

The guard currently focuses on BitLocker recovery-key patterns. Keep it, but add layered scanning:

- general secrets scanner (tokens/private keys/credentials);
- diagnostic PII patterns;
- forbidden binary/raw-artifact extension gate;
- review of generated exports;
- allowlist/suppression with audit trail.

No scanner replaces manual review of memory dumps or event logs.

### AUD-036 — Private working evidence should not default to Desktop

Desktop is convenient but visible, sync-prone and often less controlled. Put working evidence under `%LOCALAPPDATA%\WindowsCrashDoctor\Evidence` with appropriate ACLs; make “Export to Desktop…” explicit.

### AUD-037 — Retention/purge policy is not implemented

Add configurable retention by evidence class. History deletion must explain whether it deletes only index metadata or raw evidence too. Provide secure-ish best-effort purge language rather than claiming physical erasure on SSDs.

### AUD-038 — Add a real `SECURITY.md`

`SECURITY_NOTICE.md` is useful evidence-handling policy. Add standard vulnerability reporting/supported-version guidance separately.

## 9. Dependencies, integrations and supply chain

### AUD-039 — First-party installer trust is weaker than optional-provider trust

The integration manager already has concepts for release assets and digest verification. Apply at least the same standard to Windows Crash Doctor’s own executable/install path.

### AUD-040 — Pin CI actions and add dependency automation

Pin GitHub Actions to commit SHAs where practical, use Dependabot/Renovate for actions/.NET dependencies, and review updates intentionally.

### AUD-041 — Generate SBOM and build provenance

Publish SPDX/CycloneDX SBOM, SHA-256 manifest and GitHub artifact attestation/provenance with each immutable release. Later add code signing.

### AUD-042 — Principle of least privilege in workflows

The desktop workflow currently needs `contents: write` because build and release happen together. Split test/build from release so ordinary build/test jobs have read-only permissions; only the final gated release job receives write permission.

## 10. CI and test strategy

### AUD-043 — Test on both Windows PowerShell 5.1 and PowerShell 7

The product claims compatibility with classic Windows PowerShell while modern development also uses `pwsh`. Run shared fixtures under both where applicable.

### AUD-044 — Add contract tests between every layer

High-value contract tests:

1. collector output → engine parser;
2. HWiNFO adapter → normalized telemetry;
3. LHM adapter → same normalized telemetry;
4. engine JSON → desktop models;
5. embedded engine → same output as repo engine;
6. release EXE → first-run synthetic diagnosis;
7. privacy export → manifest and exclusion policy.

### AUD-045 — Add mutation/property/fuzz tests where parsing is security-sensitive

Highest priorities: dump parser, power-report JS/JSON extraction, CSV parsing and EVTX adapters.

### AUD-046 — Test failure paths, not only success fixtures

Simulate access denied, WMI timeout, corrupt JSON, full disk, missing PowerShell, disabled services, unsupported providers, no network, interrupted download and partial evidence. The product’s quality will be determined by degraded Windows machines, not clean CI hosts.

## 11. Documentation and governance

### AUD-047 — Roadmap needs status semantics, not just checkboxes

`ROADMAP_100.md` is valuable, but capabilities now exist in partial forms. Adopt statuses:

`Planned | In progress | Partial | Shipped | Blocked | Deprecated`

Each item should link to tests/acceptance criteria and, when shipped, the release that proves it.

### AUD-048 — Documentation claims need executable truth checks

Examples from the current surface that need correction or tests:

- “PowerShell engine embedded” should mean the **complete required engine**, including telemetry.
- “privacy-aware ZIP export” currently means warning + archive, not review/redaction.
- “deep sensor capture” should not imply analysis integration until the JSONL path is normalized and attached.
- “tested command-line workflow” should not be claimed on a red required workflow.

Add a release checklist and lightweight automated documentation assertions where possible.

### AUD-049 — No repository licence is present

A public GitHub repository is not automatically open source. Decide intended licensing before encouraging external reuse/contribution, then add a `LICENSE` compatible with bundled/provider boundaries. Do not choose a licence accidentally merely to satisfy tooling.

### AUD-050 — Add standard project governance files

Recommended:

- `CONTRIBUTING.md`
- `SECURITY.md`
- `SUPPORT.md`
- `CHANGELOG.md`
- `CODEOWNERS`
- issue/bug/evidence templates
- PR template with test/privacy/release checklist
- architecture decision records (`docs/adr/`)

### AUD-051 — Direct construction on `main` is outrunning verification

During this audit, multiple installer/desktop release commits landed directly on `main` while the audit was in progress. Branch-protection settings could not be read through the available GitHub connection, so this audit does **not** claim protection is absent. The observable engineering problem is simpler: changes are reaching `main` and releases faster than the full product gate validates composition.

**Improve:** short-lived feature branches/PRs, required checks, squash/merge, and an exception process for urgent fixes.

## 12. UX/product strategy

### AUD-052 — Turn evidence into an incident timeline, not just independent screens

The highest-value future UI is not more cards. It is one incident timeline showing:

- boot/resume/power transitions;
- event-log warnings/errors;
- memory/CPU/disk/thermal telemetry;
- driver/device state;
- user “system froze here” marker;
- dump/WER creation;
- configuration changes between incidents.

That connects the project’s strongest reasoning principle to a genuinely differentiated product.

### AUD-053 — Recommendations should explain discriminating tests

Instead of only “update driver” or “run memory test”, show:

- what hypothesis the test evaluates;
- what result would raise/lower that hypothesis;
- risk/cost;
- whether it changes system state;
- how to return to baseline.

The ProBook test-plan discipline should become a generic product feature.

### AUD-054 — Introduce machine/profile baselines

A snapshot is stronger when compared with this machine’s own prior healthy state. Store stable inventory/configuration hashes and show what changed before the incident.

### AUD-055 — Make confidence explainable

Confidence should eventually be a transparent function of source quality, correlation and rule specificity rather than a fixed label. Avoid fake numerical probability; show contributing reasons.

---

# Target architecture

A durable architecture for the next phase should look approximately like this:

```text
                    ┌─────────────────────────┐
                    │ WPF / future CLI / API  │
                    └────────────┬────────────┘
                                 │ typed application services
                    ┌────────────▼────────────┐
                    │ Incident orchestration   │
                    │ run / mark / compare     │
                    └───────┬─────────┬───────┘
                            │         │
             ┌──────────────▼───┐ ┌───▼─────────────────┐
             │ Evidence store    │ │ History / metadata   │
             │ immutable raw +   │ │ SQLite, schema ver.  │
             │ normalized facts  │ └──────────────────────┘
             └──────────┬───────┘
                        │
       ┌────────────────▼─────────────────┐
       │ Provider/adaptor normalization   │
       │ Windows | HWiNFO | LHM | WER ... │
       └────────────────┬─────────────────┘
                        │ stable semantic facts
             ┌──────────▼──────────┐
             │ Rule / correlation   │
             │ registry + profiles  │
             └──────────┬──────────┘
                        │ finding + provenance
           ┌────────────▼─────────────┐
           │ Report / privacy/export  │
           │ preview → redact → hash  │
           └──────────────────────────┘
```

The key is **one normalized evidence path**. Desktop, CLI and future automation should be clients of the same contracts, not parallel implementations.

---

# Recommended execution plan

## Phase 0 — Stabilise the product spine (P0)

Do these before adding major new features:

1. Fix telemetry array/parser regression and restore green core QA.
2. Make core QA a hard prerequisite for desktop release.
3. Embed `TelemetryAnalysis.psm1` and test the packaged engine end-to-end.
4. Normalize LibreHardwareMonitor JSONL and HWiNFO CSV into one telemetry model.
5. Add desktop unit/integration test project and first-run EXE smoke.
6. Secure both installers with immutable version/hash verification; stop elevated mutable-`main` install.
7. Correct README/desktop wording where implementation is partial.
8. Create version/commit identity that flows into every report/history record.

**Exit criterion:** one versioned EXE can collect a synthetic snapshot, analyse core + telemetry, produce deterministic JSON, reopen it in history, and create a clearly-labelled private export — all under one green required workflow.

## Phase 1 — Replace implicit file contracts with evidence contracts

1. Design `EvidenceBundle v1` schema and ADR.
2. Wrap collector probes with status/timeouts/duration/hash/provenance.
3. Emit normalized JSON for Windows facts while retaining raw artefacts.
4. Refactor rules behind a registry with explicit dependencies and provenance locators.
5. Move HP/XTU/Conexant specialisation into profile packs.
6. Create normalized telemetry provider adapters.
7. Migrate history toward SQLite incident/run relationships.

**Exit criterion:** a rule is independent of PowerShell pretty-print formatting and can point to the exact supporting fact/artifact.

## Phase 2 — Trust, privacy and release maturity

1. Privacy-review export workflow.
2. Broader secret/PII/raw-artifact CI scanners.
3. Stable immutable versioned releases.
4. SBOM + provenance/attestation; Authenticode signing when feasible.
5. Least-privilege desktop + elevated collector helper.
6. retention/purge controls and private evidence ACLs.
7. required PR checks and documented release checklist.

**Exit criterion:** installation and export have a defensible trust story, not merely a convenient one.

## Phase 3 — Diagnostic depth

Only after the spine is stable, accelerate the existing roadmap:

- WER ingestion;
- ETW/WPR ring-buffer capture;
- event timeline correlation;
- symbol resolution and stack analysis;
- automatic incident trigger/marker;
- hang capture;
- deduplication/signatures;
- baseline comparison;
- richer storage/GPU/network/power profile packs.

## Phase 4 — Ecosystem/productisation

- plugin/profile SDK;
- support/issue-tracker export with privacy controls;
- accessibility/localization completion;
- signed updater with stable/canary channels;
- optional remote/retrace services with explicit consent and tenant isolation.

---

# Definition of “releaseable” for Windows Crash Doctor

A commit should not produce a user-facing stable release unless all of the following are true:

- [ ] PowerShell parses under supported hosts.
- [ ] PSScriptAnalyzer error gate passes.
- [ ] Snapshot rule fixtures pass.
- [ ] Telemetry fixtures pass.
- [ ] Dump parser synthetic + real smoke pass.
- [ ] Integration-provider tests pass.
- [ ] Desktop unit tests pass.
- [ ] Embedded-engine equivalence test passes.
- [ ] Packaged EXE first-run/full-diagnosis smoke passes.
- [ ] Public evidence + general secret scan passes.
- [ ] Export/privacy policy tests pass.
- [ ] Version/commit/schema metadata is present.
- [ ] Release artifact hash/provenance is generated.
- [ ] Documentation accurately labels incomplete capabilities.

A **canary preview** may intentionally relax some product-readiness criteria, but it must be labelled canary and must never bypass integrity/security checks.

---

# Suggested engineering metrics

Avoid vanity metrics such as number of roadmap items or number of diagnostic rules. Track:

- required-workflow pass rate on `main`;
- time from regression introduced → detected;
- percentage of findings with structured provenance locators;
- percentage of collector probes with structured status + timeout;
- normalized evidence schema coverage vs regex text parsing;
- end-to-end fixture count across real Windows versions;
- false-positive/false-negative rule evaluations on curated corpora;
- desktop crash-free diagnostic runs;
- sensor capture overhead (CPU/RAM/I/O);
- export bundles blocked by privacy scanner;
- immutable releases reproducible from commit;
- mean incident-to-actionable-hypothesis time.

---

# Audit register summary

| ID | Priority | Summary |
|---|---|---|
| AUD-001 | P0 | Core QA must gate releases |
| AUD-002 | P0 | Fix telemetry parser/array regression |
| AUD-003 | P0 | Desktop must embed complete engine |
| AUD-004 | P0 | Join LHM JSONL and HWiNFO CSV telemetry paths |
| AUD-005 | P0 | Verify immutable installer artifacts |
| AUD-006 | P0 | Add desktop behavioural/integration tests |
| AUD-007 | P0/P1 | Make export genuinely privacy-aware or rename it |
| AUD-008 | P0/P1 | Immutable versioned releases + build identity |
| AUD-009–019 | P1 | Product boundaries, evidence schema and rule architecture |
| AUD-020–026 | P1/P2 | Telemetry and dump hardening |
| AUD-027–034 | P1 | Desktop architecture and incident history |
| AUD-035–042 | P1 | Privacy, supply-chain and release trust |
| AUD-043–046 | P0/P1 | Cross-layer testing and failure-path testing |
| AUD-047–051 | P1 | Roadmap/docs/licensing/governance |
| AUD-052–055 | P2 | Incident timeline, explainable recommendations and baselines |

---

# Final judgement

The repository has moved beyond “a troubleshooting script”. It now contains the beginnings of a distinctive diagnostic product. The central reasoning model is stronger than the current software engineering around it.

The next improvement is **not to add another 50 features**. The highest-leverage move is to make the existing collector, telemetry, rule engine, dump parser and desktop application behave as one versioned system with one evidence schema, one incident model and one release gate.

If the P0 and Phase 1 work above is completed before major roadmap expansion, the project becomes dramatically easier to trust and extend. If feature growth continues faster than those contracts, tests and release controls, each new capability will increase ambiguity and regression risk faster than it increases diagnostic power.

## Audit maintenance rule

Update this audit when a finding is materially resolved. Do not delete historical findings; mark them `Resolved` with the commit/release and the test that proves resolution. Re-run a full repository audit before each major/minor release or after a significant architecture change.
