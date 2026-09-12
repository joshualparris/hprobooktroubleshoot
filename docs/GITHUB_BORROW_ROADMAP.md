# Windows Crash Doctor — GitHub Borrow Roadmap

**Status:** Planned / implementation roadmap  
**Audit date:** 12 September 2026  
**Target:** Windows Crash Doctor v2 evolution inside `hprobooktroubleshoot`

This roadmap records reusable engineering patterns already present in Josh's other GitHub repositories and maps them into Windows Crash Doctor.

The goal is **not** to blindly copy whole files. The goal is to reuse proven ideas, data models and small implementation patterns where they materially improve Crash Doctor, while keeping Crash Doctor evidence-first, conservative and Windows-specific.

## Core borrowing rules

1. **Understand before changing.** Read the Crash Doctor path and the source implementation before porting anything.
2. **Adapt intent, not accidental structure.** Translate Python/TypeScript patterns into PowerShell/C# where that keeps the architecture coherent.
3. **One concept → one source of truth.** Do not create parallel history, redaction, retry or finding models.
4. **Read-only diagnosis remains the default.** Borrowed automation must not silently modify firmware, drivers, security, BitLocker or OS policy.
5. **Partial failure must stay visible.** A failed collector becomes explicit coverage/degraded-state evidence; it must not silently disappear.
6. **Evidence beats inference.** Borrowed components may improve collection, provenance, resilience and comparison, but diagnosis must still separate observation, interpretation, confidence and causality.
7. **Every borrowed behaviour gets tests.** A feature is not complete until regression tests prove its success and failure paths.

---

## Source repositories and what to borrow

| Source repo | Existing pattern worth reusing | Crash Doctor adaptation |
|---|---|---|
| `joshualparris/Action1` | Diagnostic registry, JSON diagnostic output, SQLite history, stdout/stderr/status/timing, cancellation and timeout patterns | Diagnostic plug-in registry, durable run ledger, richer process execution metadata |
| `joshualparris/DadlanControlCentre` | `safe()` failure isolation, integration health states, derived health from multiple independent observations | Continue a diagnosis when one collector/integration fails; expose `healthy`, `degraded`, `unavailable`, `unknown` coverage states |
| `joshualparris/Transfer` | Retry classification, exponential backoff + jitter, resumable statuses, fingerprints, central redaction | Resilient optional collectors/providers, deterministic evidence fingerprints, retryable/permanent failure states, shared redaction service |
| `joshualparris/AgentCheck` | Deterministic secret scanning that reports pattern metadata without exposing the matched secret | Safe Evidence Export scanner for API keys, PATs, JWTs, private keys and other credentials before creating a shareable bundle |
| `joshualparris/chronos` | Environment/health preflight with degraded-mode warnings instead of mysterious downstream failure | Crash Doctor self-check for elevation, Event Log access, dump readiness, WinDbg/symbol availability and integration status |
| `joshualparris/JoshMemory` | Provenance, source identity, confidence and timestamped records | Stronger finding/evidence provenance and run-to-run comparison metadata |

### Primary source files to inspect during implementation

- **Action1**
  - `fedora/diagnostics.py`
  - `fedora/database.py`
  - `fedora/dadlan.py`
  - `docs/ROADMAP.md`
- **DadlanControlCentre**
  - `src/lib/fleet.ts`
  - `src/lib/types.ts`
- **Transfer**
  - `electron/gmail.ts`
  - `electron/security.ts`
  - `electron/database.ts`
  - `electron/types.ts`
  - `MIGRATION_DATA_MODEL.md`
- **AgentCheck**
  - `src/agentwitness/evidence/secrets.py`
- **chronos**
  - `backend/src/services/systemdService.js`
  - `backend/src/routes/health.js`
- **JoshMemory**
  - `joshmemory/schema.py`
  - `joshmemory/index.py`
  - `joshmemory/facts.py`

---

# Roadmap

## Phase 1 — Diagnostic registry

Borrow the structured diagnostic-registry idea from Action1.

Create one canonical registry describing each collector/diagnostic rather than scattering execution knowledge across the UI and scripts.

Each diagnostic entry should define at minimum:

- stable diagnostic ID;
- display name and description;
- category (`system`, `storage`, `memory`, `power`, `firmware`, `events`, `dump`, `telemetry`, `integration`);
- implementation/command;
- administrator requirement;
- expected output type/schema;
- default timeout;
- retry policy;
- sensitivity classification;
- whether failure is fatal or degradable;
- version/rule provenance.

### Intended result

A diagnostic can be added once and automatically becomes available to the CLI, desktop application, report coverage model and test harness.

### Acceptance criteria

- Unknown diagnostic IDs fail explicitly.
- Registry IDs are unique and tested.
- UI and CLI consume the same registry/source of truth.
- Collector coverage comes from registry expectations rather than a second hard-coded file list.

---

## Phase 2 — Resilient collector/execution engine

Combine the good parts of Action1, DadlanControlCentre and Transfer.

Crash Doctor already supports cancellation. Extend the runner so every execution records:

- start and finish timestamps;
- duration;
- exit code;
- stdout/stderr;
- completion status;
- timeout state;
- cancellation state;
- retry count;
- redacted failure reason.

Introduce explicit result states such as:

- `completed`;
- `completed-with-warnings`;
- `cancelled`;
- `timed-out`;
- `failed-retryable`;
- `failed-permanent`;
- `unavailable`;
- `skipped-not-applicable`.

Optional/transient work such as symbol retrieval, provider discovery or network-backed integrations may use bounded exponential backoff + jitter. Local deterministic diagnostics should **not** be retried blindly.

### Failure isolation

A single collector failure must not destroy the entire diagnosis unless that collector is explicitly marked fatal.

Example:

- Event Logs succeed;
- storage reliability succeeds;
- LibreHardwareMonitor unavailable;
- WinDbg symbol download times out.

Crash Doctor should still produce a report and state exactly which evidence is missing and why.

### Acceptance criteria

- Timeouts cannot leave child PowerShell/process trees running.
- Cancelled and timed-out runs are distinguishable from failures.
- Transient retry policies are bounded and testable.
- Reports preserve partial evidence and explicit degraded coverage.

---

## Phase 3 — Replace flat JSON history with a durable run ledger

Borrow the SQLite run-history model from Action1 and the resumable/state ideas from Transfer.

The current desktop history should evolve from a short flat JSON list into a durable local SQLite database.

### Minimum run record

- `run_id`;
- started/finished timestamps;
- duration;
- Crash Doctor application version;
- rule/schema version;
- device identity/fingerprint;
- evidence path;
- evidence bundle hash;
- overall status;
- coverage percentage;
- high/medium/low/info finding counts;
- collector success/failure counts;
- cancellation/timeout state;
- report path.

### Supporting tables

Prefer normalised tables for:

- runs;
- collector executions;
- findings;
- evidence fingerprints;
- run comparisons;
- integration health.

Do not store secrets or unnecessary raw diagnostic contents in the history database.

### Acceptance criteria

- Existing JSON history can be imported or safely ignored without data corruption.
- History survives application upgrades.
- Database errors fail visibly rather than silently pretending there is no history.
- Queries support at least the latest runs for the same machine and latest occurrence of a finding.

---

## Phase 4 — Evidence fingerprints + before/after comparison engine

Borrow deterministic fingerprinting and provenance ideas from Transfer/JoshMemory.

This is one of the highest-value upgrades.

For every meaningful finding/evidence item, compute a stable semantic fingerprint from the facts that define the condition — not from volatile report formatting.

Compare a new run with the previous comparable run for the same device.

### Comparison states

- `NEW` — present now, absent before;
- `RESOLVED` — present before, absent now;
- `UNCHANGED` — materially the same;
- `IMPROVED` — same problem family but objective metric improved;
- `WORSENED` — same problem family but objective metric worsened;
- `UNKNOWN` — comparison is unsafe because evidence coverage/schema changed materially.

### Example output

> **Resolved:** Firmware device Code 10  
> **Unchanged:** Conexant stack still present  
> **New:** WHEA-Logger hardware error  
> **Improved:** SSD temperature peak 67°C → 48°C  
> **Evidence coverage:** 19/20 collectors succeeded  
> **Next discriminating test:** preserve this configuration for a controlled stability window before changing another major variable.

### Provenance attached to each comparison

- source collector;
- source file/event/channel;
- observed timestamp/window;
- rule ID + rule version;
- Crash Doctor version;
- confidence;
- evidence fingerprint.

### Acceptance criteria

- Reformatting a report does not create false `NEW` findings.
- Missing coverage does not falsely mark findings `RESOLVED`.
- Rule-version changes are visible in comparison metadata.
- Tests cover new/resolved/unchanged/improved/worsened/unknown states.

---

## Phase 5 — Shared redaction + Safe Evidence Export

Borrow central redaction from Transfer and secret-pattern detection from AgentCheck.

Create a single redaction/sensitivity layer used by:

- logs;
- exception messages;
- history;
- Markdown/JSON reports where appropriate;
- diagnostic ZIP export;
- public evidence checks.

### Secret scanner

Before a shareable/export ZIP is created, scan textual evidence for common credential formats including at least:

- OpenAI-style API keys;
- Anthropic-style API keys;
- GitHub PATs;
- AWS access-key IDs;
- JWTs;
- private-key headers;
- bearer tokens;
- common JSON fields such as `password`, `access_token`, `refresh_token`, `client_secret`.

The scanner must report **file + line + pattern type**, not the secret itself.

This supplements, rather than replaces, the existing BitLocker/public-evidence guard.

### Export modes

- **Private/full export** — user-controlled local diagnostic bundle.
- **Shareable/redacted export** — blocks or warns on unresolved sensitive matches and strips known sensitive fields where deterministic redaction is safe.

### Acceptance criteria

- Tests prove matched secret values never appear in scanner output/logs.
- Public/shareable export refuses clearly unsafe bundles unless the user deliberately chooses a private-local path.
- Existing BitLocker recovery-key protection remains enforced.

---

## Phase 6 — Crash Doctor self-check / preflight

Borrow Chronos' environment-health pattern.

Add a self-check that runs before or independently of a full diagnosis.

### Checks

- running elevated/admin or not;
- PowerShell availability/version;
- WMI/CIM access;
- Windows Event Log access;
- expected output directory writable;
- free disk space sufficient for collection;
- crash-dump/pagefile readiness;
- WinDbg/cdb availability when dump analysis is requested;
- symbol path/service reachability where relevant;
- optional provider presence and version;
- LibreHardwareMonitor/HWiNFO availability where relevant;
- Crash Doctor embedded engine extraction succeeded;
- history database accessible;
- current platform is supported Windows.

### Health states

Use explicit states rather than a single pass/fail:

- `healthy`;
- `degraded`;
- `unavailable`;
- `not-configured`;
- `not-applicable`.

### Acceptance criteria

- A missing optional provider produces a degraded explanation, not an opaque exception.
- A truly blocking prerequisite prevents the affected action with a useful remediation message.
- Preflight results are included in run provenance.

---

## Phase 7 — Desktop/report integration

Expose the borrowed capabilities coherently rather than as hidden backend features.

### Desktop additions

- preflight/self-check panel;
- run duration/status/retry information;
- explicit missing/degraded evidence panel;
- comparison with previous run;
- `NEW / RESOLVED / IMPROVED / WORSENED / UNCHANGED` badges;
- history backed by SQLite;
- Safe Evidence Export result/secret-scan screen;
- provenance details expandable from each finding.

### Report additions

Extend JSON/Markdown schemas with:

- run ID;
- application/rule/schema version;
- collector execution results;
- integration health;
- evidence fingerprints;
- previous-run comparison;
- explicit incomplete-coverage warnings.

Do not break the existing separation of **severity**, **confidence**, **evidence**, **interpretation** and **next step**.

---

## Phase 8 — QA, migration and rollout

No borrowed feature ships only because it works on the development machine.

### Required regression coverage

- registry validation;
- runner timeout/cancellation/process-tree cleanup;
- retryable vs permanent failure classification;
- degraded partial collection;
- SQLite migration/recovery;
- evidence fingerprint stability;
- run comparison semantics;
- secret detection without secret disclosure;
- redaction;
- preflight health-state classification;
- CLI/Desktop parity;
- existing snapshot-analysis rules;
- dump-parser regression suite;
- public-evidence/BitLocker guard.

### CI expectations

Keep Windows GitHub Actions as the authority for PowerShell/WPF build behaviour that cannot be fully validated on non-Windows hosts.

---

# What we should deliberately NOT copy

## Do not copy Action1's basic system snapshot wholesale

Crash Doctor already collects richer Windows evidence. Borrow the **registry/execution/history architecture**, not a weaker duplicate collector.

## Do not import DadLAN-specific machine/integration assumptions

SMB mount counts, MeshCentral addresses, ForgeGrid machine definitions and DadLAN topology are not Crash Doctor product concepts. Borrow only the failure-isolation and health-state model.

## Do not import Google/Transfer domain logic

Gmail/calendar/contact migration logic is irrelevant. Borrow retry classification, fingerprints, durable state and redaction patterns only.

## Do not turn Crash Doctor into AgentCheck

AgentCheck's code/LLM-claim verification is a separate product. Borrow the privacy-preserving secret scanner pattern only.

## Do not import unrelated game/UI code merely because it exists

A reuse candidate must make diagnostics, evidence quality, safety, resilience, provenance or user comprehension materially better.

---

# Proposed implementation order

1. **Canonical diagnostic registry**
2. **Runner result model + timeout/status/failure isolation**
3. **SQLite run ledger**
4. **Evidence fingerprinting**
5. **Run-to-run comparison engine**
6. **Central redaction service**
7. **Secret-safe evidence export**
8. **Preflight/self-check**
9. **Desktop comparison/history/preflight UI**
10. **Full QA + schema migration documentation**

This order establishes the underlying data contracts before building UI around them.

---

# Definition of Windows Crash Doctor v2 for this roadmap

This roadmap is complete when Crash Doctor can reliably perform the following flow:

> **preflight → collect → isolate partial failures → analyse → fingerprint → persist → compare → explain what changed → recommend the next discriminating test → export safely**

A v2 diagnosis should be able to answer not only **"what looks wrong now?"**, but also:

- What evidence was successfully collected?
- What failed to collect and why?
- What changed since the previous comparable run?
- Which findings are new, resolved, improving or worsening?
- How trustworthy is that comparison?
- What is the next test that most efficiently separates the remaining hypotheses?
- Can this evidence bundle be shared without exposing obvious secrets?

That is the useful engineering to borrow from the wider GitHub portfolio.