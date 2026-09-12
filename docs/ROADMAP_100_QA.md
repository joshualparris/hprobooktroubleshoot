# ROADMAP_100 QA record

This is the **historical validation record for the September 2026 benchmark/roadmap creation pass**. It records the structure of the roadmap when it was introduced; it is not a claim that every capability remains unimplemented today.

For current source/release state use:

- [`RELEASE_VERIFICATION.md`](RELEASE_VERIFICATION.md) for implemented/tested/Product-Gate/published distinctions;
- [`GITHUB_BORROW_ROADMAP.md`](GITHUB_BORROW_ROADMAP.md) for the v2 engineering-foundation status;
- [`ROADMAP_100.md`](ROADMAP_100.md) for the broader benchmark-derived capability backlog.

## Structural checks at roadmap creation

- Expected roadmap range: `WCD-001` through `WCD-100`.
- Expected total roadmap items: **100**.
- Expected benchmark groups: **10**.
- Expected items per benchmark tool: **10**.
- All roadmap items were intentionally initially unchecked when the benchmark pass was created.
- All items include a priority (`P0`, `P1`, or `P2`).

## Benchmark groups

1. WinDbg — WCD-001…010
2. WhoCrashed — WCD-011…020
3. BlueScreenView — WCD-021…030
4. ProcDump — WCD-031…040
5. WPR/WPA — WCD-041…050
6. Process Monitor — WCD-051…060
7. Windows Error Reporting — WCD-061…070
8. Fedora ABRT — WCD-071…080
9. Ubuntu Apport — WCD-081…090
10. systemd-coredump/coredumpctl — WCD-091…100

## Scope of the original documentation pass

The original benchmark documentation pass did **not** mark roadmap items as implemented and did not modify Crash Doctor execution code. That statement describes the historical pass only. Since then, implementation has advanced substantially: native dump parsing has a partial foundation, privacy-reviewed export exists, and the desktop now has SQLite diagnostic-run history, fingerprints/comparison, preflight and other v2 infrastructure.

Do not automatically mark a broader roadmap item complete just because a related foundation exists. Examples:

- the SQLite diagnostic **run ledger** is not yet the full always-on crash/incident catalogue described by WCD-073/WCD-091;
- current fingerprints/comparison are not yet stack-similarity crash deduplication from WCD-075;
- preflight is not ETW/WER/ProcDump-style proactive capture;
- the current native dump parser remains explicitly partial for WCD-001.

Historical detailed case-analysis files remain auditable; `analysis/STATUS.md` is the current operational case view.

## Completion rule

A `ROADMAP_100.md` checkbox should only be marked complete when the exact item — not merely an adjacent foundation — has implementation, tests, privacy/privilege behaviour and documentation as required by that roadmap's definition of done.

Release verification is a separate layer: an implemented roadmap capability is not a verified canary until the Product Gate and release handoff prove the exact packaged commit.