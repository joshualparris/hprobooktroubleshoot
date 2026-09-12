# Windows Crash Doctor code principles

This document is the repository-level interpretation of Josh's 26 code principles. It is a review contract, not a feature roadmap.

The overriding rule is: **code should make its intent obvious to the next person who reads it, including six months later. Never optimise for making a diff before understanding the system.**

## Architecture and data flow

The intended dependency direction is:

```text
Run-WindowsCrashDoctor.ps1 / Invoke-CrashDoctor.ps1
                    |
                    +--> CrashDoctor.psm1 ---------+
                    +--> DumpParser.psm1           |
                    +--> TelemetryAnalysis.psm1 ---+--> FindingModel.psm1
                    +--> Integrations.psm1
                    +--> Reporting.psm1 (structured report objects in, text out)

scripts/collect-diagnostics.ps1 --> evidence directory --> analysis modules
```

Analysis modules own diagnostic truth. Reporting only formats already-computed structured results. The runner composes operations; it does not contain diagnostic rules. The collector gathers evidence; it does not diagnose or remediate.

## Principles

1. **Understand before changing.** Read callers, outputs, tests and adjacent modules before editing. Avoid mechanical broad edits unless every match has been proven equivalent.
2. **One concept, one source of truth.** Findings and severity ordering live in `FindingModel.psm1`; report formatting lives in `Reporting.psm1`; integration versions live in `integrations/catalog.json`.
3. **Keep related things together.** Core rules, dump parsing, telemetry, integrations, reporting and collection remain separate responsibilities.
4. **Prefer boring, obvious names.** Public functions describe exactly what they do. Internal helpers use `Wcd`/`CrashDoctor` names rather than generic `process2`-style names.
5. **Keep functions small and single-purpose.** Boundary parsing, statistics, rule evaluation, formatting and orchestration are separate functions.
6. **Make data flow explicit.** Evidence enters through collector files or explicit user paths, becomes structured analysis objects, then becomes Markdown/JSON. Hidden global state must not carry diagnostic conclusions.
7. **Separate UI/presentation from business logic.** `Reporting.psm1` formats; analysis modules compute. If a future GUI is added, it must consume the same structured report objects.
8. **Never pretend static data is live data.** Every report value must come from the supplied evidence/dump/telemetry or be clearly labelled as a limitation/example.
9. **Delete dead code.** Placeholder and abandoned architecture must not remain in the repository.
10. **Do not mutate data unless intentional.** Report enrichment returns a new report object rather than changing the caller's object in place.
11. **Protect important operations with invariants.** A new app/provider install must be downloaded, validated and tested before the known-good install is replaced; rollback must preserve the previous copy on swap failure.
12. **Comments explain why, not what.** Comments are reserved for non-obvious safety/compatibility decisions such as smartctl exit-bit semantics or privilege boundaries.
13. **Consistent structure beats cleverness.** PowerShell uses `Set-StrictMode`, explicit errors, stable naming, structured objects and versioned JSON where data persists.
14. **Keep dependencies directional.** Lower-level analysis/model modules do not import the runner or presentation layer.
15. **Tests protect behaviour.** Fixtures assert findings, boundary rejection, immutable merge behaviour, dump parsing, integrations, privacy guards and real Windows minidump compatibility.
16. **Fail loudly at boundaries; degrade gracefully at presentation/orchestration.** Invalid catalogues, dumps and parsable telemetry throw at their parser boundary. The telemetry orchestrator can retain a valid source while surfacing another source's structured error.
17. **YAGNI.** Do not create speculative app layers, services or desktop shells. Build them only when a current requirement needs them.
18. **Zero trust for external data.** Catalog JSON, installation metadata, GitHub release responses, telemetry files, dumps and user paths are validated/bounded before business rules consume them.
19. **The engine owns truth; AI proposes fiction.** There is no runtime AI authority in Crash Doctor. Findings are deterministic code derived from captured evidence; AI discussion outside the program must not silently become machine evidence.
20. **State changes are atomic and idempotent.** Install/update operations stage first and preserve the previous known-good state until the replacement succeeds. Collection IDs prevent same-second output collisions.
21. **Persistent data evolves safely.** Persisted installation metadata, collection status, reports and catalogues carry schema/version identity. Breaking persisted-schema changes require migration/compatibility tests before release.
22. **Secure and private by default.** Least privilege is mandatory; only collection requests elevation. No secrets or recovery keys belong in the repo. Default collection metadata omits username/computer name. Downloads are pinned and verified when upstream hashes exist.
23. **Accessibility and responsive UX are correctness requirements.** The current product has no graphical/browser UI, so this is not presently executable code. Any future GUI must add keyboard, screen-reader, contrast, touch/mobile and reduced-motion acceptance tests before it can be considered complete.
24. **Make failures observable without leaking data.** Status objects identify failing stages and exit codes without dumping entire private inputs or command stderr into public logs.
25. **Bound expensive/unpredictable work.** File sizes, telemetry rows, hardware nodes, artifact searches, sensor duration/output, external-process runtimes and download sizes have explicit ceilings.
26. **Builds are reproducible and dependencies intentional.** Installer source is pinned to one commit. Downloadable tools use pinned tags and SHA-256 where available. CI pins runner/action/tool versions.

## Review checklist

Before merging a meaningful change, verify that the change preserves the dependency direction above, has a behavioural regression test where failure could misdiagnose or lose state, introduces no new mutable/latest dependency, does not widen privilege unnecessarily, and has explicit limits for new external or potentially unbounded work.

If a principle is not applicable to the current product surface (for example GUI accessibility while no GUI exists), document why rather than creating speculative scaffolding solely to satisfy the principle.
