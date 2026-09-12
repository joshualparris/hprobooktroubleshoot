# Documentation index

This repository has two kinds of documentation and they should not be confused:

1. **Product documentation** — how Windows Crash Doctor works, how to use it, and what is planned.
2. **Case documentation** — evidence and reasoning for the HP ProBook 11 G2 hard-freeze investigation.

## Start here

| Need | Document |
|---|---|
| Understand the whole repository | [`../README.md`](../README.md) |
| Run Windows Crash Doctor | [`../windows-crash-doctor/README.md`](../windows-crash-doctor/README.md) |
| See optional open-source diagnostic providers, licences and supply-chain rules | [`OPEN_SOURCE_INTEGRATIONS.md`](OPEN_SOURCE_INTEGRATIONS.md) |
| Understand the architecture and design rules | [`WINDOWS_CRASH_DOCTOR_PLAN.md`](WINDOWS_CRASH_DOCTOR_PLAN.md) |
| See reusable engineering patterns borrowed from Josh's other GitHub repos | [`GITHUB_BORROW_ROADMAP.md`](GITHUB_BORROW_ROADMAP.md) |
| See the ten comparator tools and research sources | [`COMPARABLE_TOOLS_RESEARCH.md`](COMPARABLE_TOOLS_RESEARCH.md) |
| See the full 100-item product backlog | [`ROADMAP_100.md`](ROADMAP_100.md) |
| Handle diagnostic evidence safely | [`../evidence/README.md`](../evidence/README.md) |
| Understand privacy/security constraints | [`../SECURITY_NOTICE.md`](../SECURITY_NOTICE.md) |
| See the current ProBook investigation state | [`../analysis/STATUS.md`](../analysis/STATUS.md) |
| Follow the controlled ProBook test sequence | [`../analysis/TEST_PLAN.md`](../analysis/TEST_PLAN.md) |

## Documentation authority

When documents disagree, use this order:

1. **Raw/current evidence** and generated collector output.
2. `analysis/STATUS.md` for the current ProBook operational state.
3. `analysis/MASTER_ANALYSIS.md` for detailed case interpretation.
4. `windows-crash-doctor/README.md` for currently shipped Crash Doctor behaviour.
5. `WINDOWS_CRASH_DOCTOR_PLAN.md` for architecture and intended design.
6. `GITHUB_BORROW_ROADMAP.md` for planned cross-repository adaptations and implementation sequencing.
7. `ROADMAP_100.md` for the broader unimplemented product backlog.

A roadmap item is not a statement that a feature already exists.

## Case records

The files in `analysis/` are investigation records. They are intentionally not rewritten just to make the product documentation look cleaner; doing so could blur when a conclusion was reached and what evidence supported it. Navigation and current-state corrections belong in `STATUS.md`, while historical reasoning remains traceable in the original analysis documents.

## Writing rules for future documentation

- State whether a claim is **observed**, **derived**, **historical/inherited**, or **planned**.
- Never describe a planned feature as implemented.
- Prefer exact commands and file paths over prose-only instructions.
- Keep risky actions explicit and separate from read-only diagnosis.
- Link every public evidence claim to its provenance where practical.
- Treat dump files, ETL traces, EVTX, WER reports and screenshots as potentially sensitive.
