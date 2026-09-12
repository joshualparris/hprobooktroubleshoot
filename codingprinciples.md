# Engineering Principles

**One standard across every repo. Version 5.1.**

> **Code should make its intent obvious to the next person who reads it — including you in six months, and including an AI agent with no memory of why any of this exists.**

Good engineering is not the production of code. It is the production of a system that can be **understood, changed, verified, recovered and trusted**.

---

# 0. How to use this standard

Keep this file at the repository root as `codingprinciples.md` and reference it from whichever agent instruction files exist, such as `CLAUDE.md`, `AGENTS.md`, or `.github/copilot-instructions.md`.

Agents **MUST read this document before making changes**.

Every maintained repository declares near the top of its README:

```text
Engineering principles: v5.1
Assurance tier: 1 | 2 | 3
Canonical repository: https://github.com/owner/repository
```

Repository-specific architectural or stack conventions belong in the repository, not in the universal principles. Use a file such as `REPO_CONVENTIONS.md` and `docs/decisions/` for durable project-specific decisions.

Do not silently modify this standard in one repository. Change the shared standard deliberately and increment its version.

## 0.1 Normative language

**MUST** — A hard requirement whenever the rule applies to the repository's assurance tier. An agent must not silently weaken, reinterpret or ignore a MUST.

**SHOULD** — The required default. Depart only for a concrete reason and state that reason in the durable change record. A SHOULD silently ignored has been treated as a MAY and violates this standard.

**MAY** — Optional. Use when it materially improves the system.

Words such as "probably", "ideally", "where appropriate" and "generally" do not create additional requirement levels.

## 0.2 When principles conflict

```text
safety & data integrity → correctness → recoverability → clarity → simplicity → consistency → performance → convenience
```

A smaller diff is not better if it is wrong. A simpler implementation is not better if it loses data. A consistent implementation is not better if the convention itself is unsafe. Passing tests are not enough if observed behaviour is wrong.

## 0.3 Assurance-tier applicability

A **MUST becomes mandatory when the section containing it is required for the repository's tier**, except for the universal safety floor and overlays below.

| Requirement set | Applies to |
|---|---|
| Universal safety floor | Every repository |
| Tier 1 requirements | Tier 1, Tier 2 and Tier 3 |
| Tier 2 requirements | Tier 2 and Tier 3 |
| Tier 3 requirements | Tier 3 |
| LLM/agent overlay | Any tier using an LLM or autonomous coding/runtime agent |

### Universal safety floor

Always apply: §1; §2.1, §2.3–2.4; §3.4, §3.6–3.7; §5.1–5.2; §6.1, §6.3; §7.1; §8.4; §9.4 whenever a coding agent is used; and §10 for maintained repos.

No tier permits committing secrets, knowingly fabricating system state, claiming verification that did not occur, or silently treating a failed operation as successful.

### Tier 1

Tier 1 is the universal safety floor and is valid only while the repo remains genuinely experimental. If it stores persistent data someone would care about losing, becomes regularly used, or becomes a dependency of another maintained system, it **MUST be promoted to Tier 2**.

### Tier 2

Tier 2 adds §2.2 and §2.5; §3.1–3.3 and §3.5; all of §4; §5.3–5.4; §6.4; §7.2; §8.1–8.3 and §8.5; and full §10 documentation. If it handles money, health data, workplace/client information, auth, other people's private data or similar high-consequence data, it **MUST be promoted to Tier 3**.

### Tier 3

Tier 3 requires the **entire standard**. Convenience never excuses a relevant MUST.

### LLM/agent overlay

If a repo contains an LLM-driven feature, §9.1–9.3 apply regardless of tier. If a coding agent modifies any repo, §9.4 applies regardless of tier.

## 0.4 One project has one canonical repository

Every actively maintained project **MUST have exactly one canonical repository**. It owns authoritative default-branch history, active PRs/branches, current issues, releases/tags and deployment configuration.

Copies elsewhere **MUST** have an explicit role: read-only mirror, archived predecessor, backup, deliberate fork or generated distribution copy. A mirror **MUST NOT** receive independent feature development. If two repos both claim to be the same active project, work **MUST stop until one is selected**.

Every maintained deployment **MUST** be traceable:

```text
canonical repository → branch/tag/commit → build → deployment
```

Multiple deployments are allowed. Multiple unexplained sources of truth are not.

## 0.5 When an agent cannot comply

An agent **MUST NOT guess its way around a MUST**. If context is unavailable, authoritative instructions conflict, the task requires violating a MUST, recovery cannot be established, an irreversible action cannot be verified, access/tooling is unavailable, the canonical repo is unclear, or materially different interpretations remain:

1. Stop the affected action.
2. Do not perform the destructive, irreversible or assumption-dependent step.
3. State the exact conflict or missing fact.
4. Name the principle preventing progress.
5. Preserve safely completed work.
6. Continue only independent, reversible work not dependent on the unresolved decision.
7. Request an explicit decision when a human is available.

Do not convert "I don't know" into "this is probably what they meant." If §1 understanding cannot be reached from available code, docs, history or tools, **stop changing that area rather than infer architecture from filenames or patterns alone**.

---

# The ten rules

1. **Understand the system before changing it.**
2. **Never optimise for producing a diff.**
3. **Make the smallest change that completely solves the problem.**
4. **Every important fact has one canonical owner of truth.**
5. **Validate everything crossing a trust boundary.**
6. **Important state changes remain correct under retries, failures and concurrency.**
7. **Fail loudly inside the system and honestly to the user.**
8. **The interface never claims something the system does not know.**
9. **Anything capable of destroying, exposing or materially misrepresenting important data is tested according to its risk.**
10. **"Done" means demonstrated with named evidence.**

# 1. Understand before changing

## 1.1 Understand existing behaviour

Before changing code, **MUST** understand enough of the surrounding path to explain what it does, why it exists, callers, dependencies, dependants, input origins, output destinations, persistent state touched and assumptions that must remain true. Investigation depth follows consequence of failure.

**Smell:** you cannot explain in one sentence what code you are about to remove was doing.

## 1.2 Never optimise for the diff

The goal is to improve the system, not maximise changed files. A five-line fix based on understanding beats a 300-file pattern rewrite. Volume of change, agent activity and a tidy diff are not evidence of correctness.

## 1.3 Prove equivalence before bulk automation

Repo-wide replacements, codemods, mass renames and automated migrations **MUST NOT** be used merely because lines look similar. Establish semantic equivalence first; verify behaviour afterwards. Compilation alone is not proof.

# 2. Change deliberately

## 2.1 Small, complete, reversible

A change **SHOULD** contain one coherent concern. Make the smallest change that **completely** solves the problem, not merely the visible symptom. Avoid unrelated cleanup; cleanup **MAY** be included when required for safety or to remove code made obsolete. Commit messages **SHOULD** explain why.

## 2.2 Recovery before destructive work

Before deleting important data, persistent-schema changes, mass renames, destructive migrations, storage-format replacement or irreversible bulk operations, **MUST** know how to recover. For important persistent data, create or confirm the recovery point **before** the destructive step. A backup is not proven merely because a file exists.

## 2.3 Prefer subtraction to speculative abstraction

Remove dead code, duplicated concepts, obsolete paths, unused architecture and unused dependencies. Do not add infrastructure solely because it may be useful later. Optimise conceptual load, not line count. Git remembers.

## 2.4 Separate refactoring from behaviour change

Explicitly decide whether behaviour stays the same, deliberately changes or becomes unsupported. Do not hide behaviour changes inside refactors. Observable changes **MUST** be discoverable in code, tests and relevant docs.

## 2.5 Record non-obvious decisions

If a choice cannot be understood from code alone, record why using the smallest durable form: comment, repo docs or ADR. A decision record **SHOULD** state the decision, reason, significant alternatives rejected and constraints future work must preserve. Comments explain why; code should explain what.

# 3. Make the structure obvious

## 3.1 One fact, one canonical authority

Every important fact **MUST** have one canonical authority. Caches, indexes, projections and derived state **MAY** exist only with explicit ownership, derivation and rebuild/reconciliation rules.

**Smell:** two independently writable places can answer the same factual question differently.

## 3.2 Group by responsibility

Code **SHOULD** be organised around responsibilities/features, not generic buckets. Structure should answer: *where do I look to understand this behaviour?*

## 3.3 Dependencies point deliberately

Prefer `UI → application/features → domain/services → persistence/infrastructure`. Domain/persistence **MUST NOT** depend on presentation for convenience. Dependency cycles **SHOULD** be removed; use interfaces/ports/callbacks/injection where framework constraints invert control.

## 3.4 Boring, precise names

Names **MUST** communicate intent: `exportUserData()`, not `doStuff()`; `calculatePlanSpend()`, not `process2()`. Generic names are acceptable only when the abstraction is genuinely generic and responsibility remains obvious.

## 3.5 One level of abstraction

Functions/modules **SHOULD** perform one coherent job at one conceptual level. Split when it materially improves reasoning, testing, failure handling, reuse or ownership; do not create microscopic wrappers merely to satisfy a rule.

## 3.6 Consistency beats local cleverness

Follow existing repo conventions unless replacing the convention is itself the deliberate task. Be consistent about naming, imports, errors, validation, time/date handling, persistence, async behaviour, state, tests and logging. Do not casually introduce a second competing convention.

## 3.7 Comments preserve intent

Comments explain why, not what. If the operation itself needs explanation, first improve its name or structure.

# 4. Make data flow traceable

## 4.1 Important values have a traceable path

Important data shown or acted upon **MUST** trace back to its authority, e.g. `storage/API → adapter/repository → domain/application → view model/hook → UI`. Architecture may differ; the requirement does not: origin must be discoverable without guessing.

## 4.2 Presentation presents; domain logic decides

Presentation **MUST NOT** be the sole home of important financial, permission, migration, backup, health, combat, scoring or resource rules. Formatting and interaction-specific logic **MAY** remain there.

## 4.3 Every trust boundary is untrusted

External data **MUST** be validated before trusted logic relies on it: user input, APIs, URLs, config/env, imports, browser/device storage, old persisted schemas, webhooks, IPC and model output. Validation **SHOULD** happen near the boundary using an idiomatic mechanism.

## 4.4 Do not mutate data you do not exclusively own

Data from callers, caches, query systems, framework state, persistence libraries and shared stores **MUST** be treated as shared unless ownership is explicit. Local exclusive mutation is allowed. When uncertain, copy before transforming.

## 4.5 State transitions withstand repetition and partial failure

Where duplication matters, ask *what if this executes twice?* and *what if it fails halfway through?* Retries, double-clicks, duplicate events and reconnects **MUST NOT** accidentally double-charge, double-consume, double-award, duplicate durable records or advance state twice. Use transactions, idempotency keys, uniqueness constraints, compare-and-swap, optimistic concurrency or suitable equivalents.

## 4.6 Time, randomness and concurrency are explicit dependencies

When correctness depends on clocks, timers, randomness, async ordering or concurrent writes, those dependencies **SHOULD** be isolated/injectable so behaviour can be reproduced and tested. Accidental timing must not become a hidden business rule.

## 4.7 Persistent data evolves deliberately

Persistent-structure changes **MUST** have an explicit upgrade strategy. Identify versions, test representative old data, protect originals from failed upgrades, and define recovery/forward repair. Never assume all installations start on today's schema.

# 5. Design for failure and recovery

## 5.1 Fail near the source

Invalid states and failed operations **MUST NOT** silently become apparent success. Do not swallow meaningful failures. Errors **SHOULD** retain enough safe context to identify what failed, where and which operation/request/build was involved.

## 5.2 Fail honestly and calmly to users

UI **MUST** distinguish loading, empty, failed, unavailable, stale and successful states when materially different. Failed fetch ≠ empty result. Do not show success before the operation defining success completes.

## 5.3 Bound unpredictable work

Work that can grow from external input, generated behaviour or repeated failure **MUST** have a sensible bound: retries, model/tool calls, uploads, response sizes, untrusted collections, external recursion, queues, network waits, context history. Fixed inherently bounded work needs no artificial limit.

## 5.4 Recovery must be demonstrated

For important persistent data, define what is recoverable, where recovery material lives, what failures it protects against and how restoration works. Recovery **MUST** be tested to the repo's assurance level.

> **A backup that has never successfully restored representative data is an unverified backup.**

# 6. Security, privacy and dependencies

## 6.1 Least privilege

Users, code, services and agents receive only required authority. Secrets **MUST NOT** be committed or shipped client-side. Authorisation **MUST** be enforced at a trusted boundary. Hiding a button is not authorisation.

## 6.2 Observability without leakage

Logs **MUST NOT** contain passwords, API keys, access/refresh tokens, auth secrets or complete sensitive payloads. Sensitive personal data **SHOULD NOT** be logged unless documented and appropriately protected. Diagnostic identifiers **SHOULD** be minimised/scoped/pseudonymised where practical. Prefer request IDs, error categories, build versions and bounded technical context.

## 6.3 Dependencies earn their place

Before adding one, consider security, maintenance, update cadence, runtime/bundle cost, licensing, ecosystem health and conceptual cost. Use established dependencies for hard solved problems; do not add one to avoid trivial obvious code. Unused dependencies **MUST** be removed.

## 6.4 Controlled build inputs

Commit lockfiles where supported. Pin/constrain runtimes and important tooling enough for repeatable builds. CI/deploy environments **SHOULD** be compatible with development/test environments. A build relying on undocumented one-machine state is not reproducible.

# 7. Tell the truth to the user

## 7.1 Never present invented certainty

UI **MUST NOT** imply information is live, measured, saved, verified or authoritative when it is not. This includes sample data as real, premature success, fake progress, undisclosed stale data, failed requests as empty, placeholders as calculated results, charts without authoritative inputs, and AI-generated assertions as verified facts. Demo data is fine; demo data pretending to be real is not.

## 7.2 Accessibility and supported environments are correctness

User-facing software **MUST** work in environments the repo claims to support. Where relevant verify keyboard operation, assistive semantics, contrast, focus, reduced motion, touch targets, responsive layout and real loading/error states. The repo defines supported devices/browsers/input methods.

# 8. Verify according to risk

## 8.1 Prefer behavioural invariants

Tests **SHOULD** establish behaviour/invariants rather than mirror implementation. Write the invariant plainly, then test it — e.g. *anything exported survives export → wipe → restore without losing meaning*. Do not couple to implementation detail unless that detail is a deliberate contract.

## 8.2 Test according to consequence

Test effort follows risk, not line count. Highest priority: code that can destroy data, expose private data, move money, change permissions, corrupt persistent state, materially misrepresent information or trigger irreversible external actions; then important domain rules and core flows.

## 8.3 Protect contracts

Interfaces between independently changing components **SHOULD** have executable contract verification: client↔API, app↔database, service↔provider, importer↔backup format, old schema↔migration, rules engine↔AI. Breaking public/persisted contracts requires deliberate compatibility handling.

## 8.4 Automated gates are evidence, not runtime proof

At the required assurance level, CI **MUST** run declared gates, commonly format/lint, static/type analysis, tests, build and dependency/security checks. Report each result accurately. Never say tests passed when only build ran; never say the app works merely because CI is green.

**Green CI is necessary evidence where required. It is not sufficient evidence of runtime behaviour.**

## 8.5 Measure performance before trading clarity for speed

Do not complicate code for speculative performance. Performance work **SHOULD** start with measurement and **SHOULD** record reproducible before/after results. Correctness is not traded for speed.

# 9. LLM and agent systems

## 9.1 Deterministic code owns authoritative state

> **Code owns facts. The model proposes interpretation, language and possibilities.**

Money, HP, resources, inventory, XP, dice outcomes, permissions, scores and save state **MUST** be owned by deterministic logic unless the product explicitly defines another authority model. A model must not silently invent mechanical truth.

## 9.2 Model output is untrusted input

Model output **MUST** be validated before affecting authoritative state. Structured output must satisfy schema. Bounded repair/retry is allowed; repaired output **MUST** be validated again. If valid output cannot be obtained within bounds, fail without inventing state.

## 9.3 Assume prompt injection

Users, files, websites, tools, retrieval and other models may contain adversarial instructions. Trusted instructions, app state and untrusted content **MUST** remain distinguishable. Untrusted content cannot grant itself authority. Agent tools **SHOULD** expose minimum capability; high-consequence actions require stronger verification than reads.

## 9.4 Agents provide evidence, not confidence

"Everything is working" is not evidence. Completion reports **SHOULD** name what actually ran and what was observed, e.g. `npm test → 84 passed`, `npm run build → exit 0`, `manual → save persisted after refresh`, `deployed → API returned expected status/schema`. Agent confidence has no bearing on correctness.

# 10. Documentation reduces archaeology

Maintained repos **MUST** make discoverable, when relevant: what the project does, how to run/test/build it, assurance tier, canonical repository, important architectural constraints, persistent-data location and deployment path. Documentation changes when described behaviour changes. Fix or delete stale docs; confident false docs are worse than none.

# Assurance tiers

Choose by **consequence of failure**, not size, age or original seriousness. Higher tiers include lower-tier requirements unless explicitly superseded. Declared tier is a minimum, not a waiver. If consequences increase, tier **MUST be raised before further work relies on the lower standard**.

## Tier 1 — Experimental

Throwaway prototypes, experiments, proofs of concept, games with no important persistence. Required: universal safety floor. CI/migrations/extensive tests are not required unless the experiment itself depends on them.

## Tier 2 — Durable personal/family software

Regularly used personal/family apps, persistent games, personal productivity tools and long-lived hobby systems. Tier 1 plus canonical data ownership, traceable data, boundary validation, deliberate schema evolution, recovery, destructive/persistence tests, supported-environment/accessibility verification, controlled builds and maintained docs.

## Tier 3 — High-consequence software

Health, finance, workplace/client information, authentication/authorisation, other people's private data and multi-user systems where failure can materially harm someone. Requires the **full standard**, especially privacy/security, least privilege, decision records, validated boundaries, idempotency/concurrency safeguards, tested migrations/recovery, contract tests, CI gates, safe observability, deliberate dependencies and LLM safeguards.

Tier 3 requires evidence, not ceremony for its own sake.

# Repository-specific conventions

The universal standard does not prescribe a framework/library. Each repo **SHOULD** declare its actual stack conventions, e.g. in `REPO_CONVENTIONS.md`: validation, tests, static checks, build, persistence, deployment. Next.js may use `next build`; Vite `vite build`; Python Ruff/Pyright-or-Mypy/Pytest/build; Kotlin ktlint/Detekt/tests/Gradle.

**The principle is universal. The tool is not.**

# Definition of done

## Understanding
- [ ] I can explain previous behaviour and why the change is required.
- [ ] I understand affected data/dependencies deeply enough for this repo's risk.

## Scope
- [ ] Smallest complete solution; unrelated changes excluded.
- [ ] Obsolete code removed; refactor and behaviour change not mixed silently.

## Correctness
- [ ] Relevant code actually ran and behaviour that matters was observed.
- [ ] Required static checks, tests and build passed and are reported separately.

## Data/recovery
- [ ] Trust boundaries validated.
- [ ] Important state changes tolerate retry, duplication and partial failure.
- [ ] Migration/recovery requirements satisfied.
- [ ] No silent data destruction, duplication, exposure or misrepresentation.

## User experience
- [ ] UI tells the truth; loading/failure/stale/empty are not confused.
- [ ] Affected experience works in declared supported environments.

## Security
- [ ] No secrets entered source/client/logs; permissions not accidentally broadened.
- [ ] Sensitive logging justified/minimised; new dependencies justified.

## Repository authority
- [ ] I confirmed this is canonical, or its explicit non-canonical role permits the change.
- [ ] I am not creating a second independent source of truth.
- [ ] Affected deployment traces back to this repo/commit.

## Standards compliance
- [ ] I know the assurance tier and applied its MUSTs/overlays.
- [ ] Any SHOULD departure is recorded durably.
- [ ] I did not silently work around a MUST.
- [ ] Unsatisfied requirements were reported as blockers rather than guessed around.

## Maintainability
- [ ] No dead code, orphaned files or abandoned commented-out implementation.
- [ ] Non-obvious decisions recorded; docs match resulting system.

## Evidence
- [ ] I can state exactly what proves this change works.

If the final question cannot be answered, the change is not done.

# Final rule

When uncertain, optimise for the next reader **without compromising the current user**. Leave the system easier to understand than you found it.

A good change leaves enough truth that the next human or AI agent can understand **what it does, why it exists, how it was verified, how it can fail, and how to change it without guessing**.

A good agent knows not only how to make a change, but when **not** to make one. When evidence is missing, authority is unclear or a high-consequence decision cannot be made safely, refusing to guess is part of correct engineering.