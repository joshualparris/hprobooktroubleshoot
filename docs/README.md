# Documentation index

This repository has two kinds of documentation and they should not be confused:

1. **Product documentation** — how Windows Crash Doctor works, what is implemented, what is verified and what is still planned.
2. **Case documentation** — evidence and reasoning for the HP ProBook 11 G2 hard-freeze investigation.

## Start here

| Need | Document |
|---|---|
| Understand the whole repository | [`../README.md`](../README.md) |
| Check whether a particular Windows Crash Doctor canary is actually verified/releasable | [`RELEASE_VERIFICATION.md`](RELEASE_VERIFICATION.md) |
| See the dated engineering quality/risk audit | [`REPOSITORY_AUDIT.md`](REPOSITORY_AUDIT.md) |
| See what was implemented for the audit's Phase 0 blockers | [`PHASE0_IMPLEMENTATION_2026-09-12.md`](PHASE0_IMPLEMENTATION_2026-09-12.md) |
| Run Windows Crash Doctor | [`../windows-crash-doctor/README.md`](../windows-crash-doctor/README.md) |
| See optional open-source diagnostic providers, licences and supply-chain rules | [`OPEN_SOURCE_INTEGRATIONS.md`](OPEN_SOURCE_INTEGRATIONS.md) |
| Understand the architecture and design rules | [`WINDOWS_CRASH_DOCTOR_PLAN.md`](WINDOWS_CRASH_DOCTOR_PLAN.md) |
| See cross-repository engineering adaptations and their implementation status | [`GITHUB_BORROW_ROADMAP.md`](GITHUB_BORROW_ROADMAP.md) |
| See the ten comparator tools and research sources | [`COMPARABLE_TOOLS_RESEARCH.md`](COMPARABLE_TOOLS_RESEARCH.md) |
| See the full 100-item product backlog | [`ROADMAP_100.md`](ROADMAP_100.md) |
| Handle diagnostic evidence safely | [`../evidence/README.md`](../evidence/README.md) |
| Understand privacy/security constraints | [`../SECURITY_NOTICE.md`](../SECURITY_NOTICE.md) |
| See the current ProBook investigation state | [`../analysis/STATUS.md`](../analysis/STATUS.md) |
| Follow the controlled ProBook test sequence | [`../analysis/TEST_PLAN.md`](../analysis/TEST_PLAN.md) |

## Documentation authority

Different documents answer different questions. When they appear to disagree, use this order for the relevant type of claim:

1. **Raw/current evidence** and generated collector output for machine/case facts.
2. `analysis/STATUS.md` for the current ProBook operational state.
3. `analysis/MASTER_ANALYSIS.md` for detailed case interpretation and historical reasoning.
4. `windows-crash-doctor/README.md` for currently implemented Crash Doctor behaviour and limitations.
5. `RELEASE_VERIFICATION.md` for whether a specific commit/artifact/canary has actually passed the release contract.
6. `PHASE0_IMPLEMENTATION_2026-09-12.md` for concrete P0 implementation work; implementation alone is not release proof.
7. `REPOSITORY_AUDIT.md` as the dated engineering-audit baseline and stable audit-ID record.
8. `WINDOWS_CRASH_DOCTOR_PLAN.md` for architecture and intended design.
9. `GITHUB_BORROW_ROADMAP.md` for cross-repository adaptations, including **implemented**, **partial** and **future** status.
10. `ROADMAP_100.md` for the broader product capability backlog.

A roadmap item is not a statement that a feature already exists. Conversely, an old roadmap/audit statement that says a feature is planned does not override current source code. Use the current implementation and its tests to establish **implemented** state, and the Product Gate/release record to establish **release-verified** state.

## Release truth model

Documentation must distinguish:

- **implemented in source**;
- **covered by a focused test**;
- **verified through the packaged EXE Product Gate**;
- **published as the canary for the same commit**;
- **future stable-release hardening**.

For example, SQLite history, fingerprints/comparison, preflight, diagnostic-registry coverage/provenance, privacy-reviewed export and resilient process execution are now source capabilities. That does not mean every original v2 acceptance criterion or future stable-release requirement is complete. See [`RELEASE_VERIFICATION.md`](RELEASE_VERIFICATION.md) for the exact distinctions.

## Case records

The files in `analysis/` are investigation records. They are intentionally not rewritten merely to make historical reasoning match the newest product architecture. Navigation and current-state corrections belong in `STATUS.md`, while historical reasoning remains traceable in the original analysis documents.

## Audit maintenance

`REPOSITORY_AUDIT.md` is a dated engineering baseline. Keep its audit IDs stable rather than silently rewriting the original finding text. Current remediation/verification state belongs in the Phase 0 implementation record and release-verification record until a later formal re-audit supersedes the baseline.

## Roadmap maintenance

`GITHUB_BORROW_ROADMAP.md` is now a live implementation/status roadmap, not a purely planned document. A phase may be marked **Implemented**, **Partial**, **Verified** or **Future** only to the extent that code and tests support that wording.

`ROADMAP_100.md` remains a broader benchmark-derived product backlog. Its items have stricter definitions than the v2 foundation: for example, the current SQLite diagnostic run ledger is not the same thing as an always-on crash/incident catalogue with lifecycle, deduplication and retention.

## Writing rules for future documentation

- State whether a claim is **observed**, **derived**, **historical/inherited**, **implemented**, **verified** or **planned**.
- Never describe a planned feature as implemented.
- Never describe source implementation as a verified release unless the Product Gate/release handoff proves it for that commit.
- Prefer exact commands and file paths over prose-only instructions.
- Keep risky actions explicit and separate from read-only diagnosis.
- Link public evidence claims to provenance where practical.
- Treat dump files, ETL traces, EVTX, WER reports and screenshots as potentially sensitive.
- Keep product/engine/collector versions distinct rather than flattening them into one number.