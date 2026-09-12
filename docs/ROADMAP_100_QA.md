# ROADMAP_100 QA record

Validation performed before merge of the September 2026 benchmark/documentation pass.

## Structural checks

- Expected roadmap range: `WCD-001` through `WCD-100`.
- Expected total roadmap items: **100**.
- Expected benchmark groups: **10**.
- Expected items per benchmark tool: **10**.
- All roadmap items are intentionally initially unchecked.
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

## Scope check

This documentation pass does **not** mark any roadmap item as implemented and does not modify Crash Doctor execution code. It improves navigation, architecture, safety, evidence handling, current-case status and future product planning.

Historical detailed analysis files were deliberately not rewritten merely for consistency; `analysis/STATUS.md` remains the current operational view while older reasoning remains auditable.

## Completion rule

A roadmap checkbox should only be marked complete when implementation, tests, privacy/privilege behaviour and documentation are all present as defined in `ROADMAP_100.md`.
