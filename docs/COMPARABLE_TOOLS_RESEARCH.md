# Comparable crash and diagnostics tools — research notes

Research date: **12 September 2026**

Windows Crash Doctor is deliberately evidence-first and conservative. The tools below show what a mature diagnostic product can add without giving up that discipline. This comparison is about **capabilities to borrow**, not copying implementation or UI.

## Current Crash Doctor baseline

At the time of this comparison, `main` can:
- collect a reproducible Windows snapshot with `scripts/collect-diagnostics.ps1`;
- analyse the collector's text outputs;
- detect selected firmware, reused-image, XTU/Conexant, BitLocker, dump-readiness, storage, WHEA, Event 41 and volmgr patterns;
- separate evidence, interpretation, severity, confidence and next step;
- emit Markdown and JSON;
- run synthetic regression tests and a public-evidence guard.

It does **not yet** natively parse Windows crash dumps, resolve symbols, record ETW, capture trigger-based dumps, maintain a persistent incident database, deduplicate crashes, provide a graphical timeline or integrate with support/bug trackers.

## Ten comparable tools

### 1. WinDbg

Microsoft's full Windows debugger: native/user/kernel dump analysis, symbols, stacks, registers, live debugging and scripting.

**What to borrow:** the ten gaps translated into actionable backlog items are **WCD-001 through WCD-010** in [`ROADMAP_100.md`](ROADMAP_100.md).

**Primary sources:**
- [WinDbg overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/)
- [!analyze reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-analyze)

### 2. WhoCrashed

A user-friendly crash-dump analyser that turns dump internals into likely problem families and next-step guidance.

**What to borrow:** **WCD-011 through WCD-020**.

**Primary sources:**
- [WhoCrashed help](https://www.resplendence.com/whocrashed_help)
- [WhoCrashed Professional features](https://www.resplendence.com/whocrashed_pro)

### 3. BlueScreenView

A lightweight historical BSOD/minidump browser focused on bugchecks, loaded drivers and stack-involved modules.

**What to borrow:** **WCD-021 through WCD-030**.

**Primary source:**
- [BlueScreenView](https://www.nirsoft.net/utils/blue_screen_view.html)

### 4. ProcDump

A trigger-driven dump-capture tool for hangs, exceptions, CPU/memory thresholds and difficult intermittent process failures.

**What to borrow:** **WCD-031 through WCD-040**.

**Primary source:**
- [ProcDump](https://learn.microsoft.com/en-us/sysinternals/downloads/procdump)

### 5. WPR/WPA

Microsoft's ETW recording and timeline-analysis toolkit for CPU, I/O, memory, power, GPU and boot/resume scenarios.

**What to borrow:** **WCD-041 through WCD-050**.

**Primary sources:**
- [Windows Performance Toolkit](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/)
- [WPR command-line options](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpr-command-line-options)
- [Built-in recording profiles](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/built-in-recording-profiles)

### 6. Process Monitor

High-volume, real-time file/Registry/process/thread/DLL tracing with stacks, filters and boot logging.

**What to borrow:** **WCD-051 through WCD-060**.

**Primary source:**
- [Process Monitor](https://learn.microsoft.com/en-us/sysinternals/downloads/procmon)

### 7. Windows Error Reporting

Windows' native crash/hang reporting, local dump, report-store and application recovery infrastructure.

**What to borrow:** **WCD-061 through WCD-070**.

**Primary sources:**
- [About WER](https://learn.microsoft.com/en-us/windows/win32/wer/about-wer)
- [Collecting user-mode dumps](https://learn.microsoft.com/en-us/windows/win32/wer/collecting-user-mode-dumps)

### 8. Fedora ABRT

Fedora's automatic crash detection/reporting stack with local problem storage, deduplication, retracing and analytics.

**What to borrow:** **WCD-071 through WCD-080**.

**Primary sources:**
- [Fedora ABRT overview](https://developer.fedoraproject.org/tools/abrt/about.html)
- [ABRT server / analytics](https://abrt.fedoraproject.org/)
- [ABRT design](https://abrt.readthedocs.io/en/latest/design.html)

### 9. Ubuntu Apport

Ubuntu's automatic crash reporter with environment collection, package hooks, retracing and guided bug submission.

**What to borrow:** **WCD-081 through WCD-090**.

**Primary source:**
- [Ubuntu Apport](https://ubuntu.com/project/docs/contributors/debugging/apport/)

### 10. systemd-coredump/coredumpctl

Persistent crash catalogue and core-dump retrieval/debug workflow with metadata, retention and access controls.

**What to borrow:** **WCD-091 through WCD-100**.

**Primary sources:**
- [coredumpctl](https://www.freedesktop.org/software/systemd/man/latest/coredumpctl.html)
- [systemd-coredump](https://www.freedesktop.org/software/systemd/man/latest/systemd-coredump.html)

## Cross-tool themes

Across the ten tools, the same product lessons recur:

1. **Capture before analysis.** Mature tools preserve the failure itself — dump, core, ETW trace, WER record or operation log — instead of relying only on aftermath events.
2. **Symbols matter.** Stacks become dramatically more useful when addresses resolve to modules, functions and source locations.
3. **Time matters.** A timeline around boot, resume, hang and crash is often more diagnostic than a static inventory.
4. **History matters.** A catalogue of repeated incidents reveals recurrence, signatures, regressions and “fixed vs merely quiet”.
5. **Deduplication matters.** Repeated instances of the same crash should become one problem with frequency statistics, not 50 unrelated files.
6. **Capture must be triggerable.** CPU, memory, exception, hang and performance-counter triggers catch intermittent failures that ordinary snapshots miss.
7. **Context matters.** Process, package, driver, version, loaded modules, command line, user/session and uptime should travel with the incident.
8. **Privacy must be a product feature.** Crash dumps and traces can contain private memory and identifiers; review, access control and retention belong in the architecture.
9. **The next action should be reproducible.** Good tools make it easy to hand a dump to a debugger, retrace it remotely, export a support bundle or repeat a capture profile.
10. **A diagnostic product needs extensibility.** Plugins, custom trace profiles, runtime hooks and reporting backends prevent the core from turning into one giant hard-coded rules file.

## Important design constraint

Some comparator features are intentionally **not** candidates for silent automation. BIOS flashing, driver removal, security changes, dump-policy changes, report upload and remote access must stay explicit and reversible. The roadmap therefore separates **diagnosis/capture** from **remediation/action**.

## Research limitations

This is a feature benchmark, not a claim that each comparator is safe or suitable for every machine. Some tools are developer-oriented, some are consumer-oriented, and some are Linux-only. Features were translated into Windows Crash Doctor concepts only where they improve evidence quality, incident capture, explanation, privacy or workflow.
