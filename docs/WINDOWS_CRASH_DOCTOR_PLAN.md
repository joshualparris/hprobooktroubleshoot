# Windows Crash Doctor — design, diagnostics and solution workflow

Windows Crash Doctor turns the HP ProBook investigation from a one-off troubleshooting exercise into a reusable Windows incident-diagnosis tool.

The design borrows the **evidence-first workflow** we wanted from Fedora Crash Doctor: persistent observation, post-incident reconstruction, explicit hypotheses, controlled interventions and verification. It does not attempt to port Linux commands to Windows.

## The 10 improvements

### 1. Persistent pre-freeze canary

A small scheduled background process samples system health continuously. The default interval is 10 seconds and automatically tightens to 2 seconds for two minutes after CPU, memory or disk-queue warning thresholds are crossed.

Every sample is appended immediately to JSONL. A total freeze therefore still leaves the previously flushed samples on disk.

Current fields include:

- boot ID and uptime;
- CPU load;
- physical-memory use;
- commit use;
- pagefile allocation/use;
- disk queue, disk utilisation and throughput;
- system-drive free space;
- battery state where present;
- top working-set process;
- optional GPU utilisation;
- optional ACPI thermal-zone reading;
- sample duration, which itself helps expose collection stalls.

### 2. Automatic hard-freeze reconstruction

Crash Doctor stores the current boot time and last successful heartbeat.

On the next boot it compares that state with the new boot ID. If Windows also records `Kernel-Power 41` or `EventLog 6008` around the new boot, Crash Doctor creates an incident automatically using the final prior heartbeat as the incident edge.

The default pre-incident window is 30 minutes.

### 3. Event correlation instead of Event Viewer hunting

The incident timeline pulls selected events from System and Application logs, including:

- Kernel-Power and EventLog abnormal-shutdown records;
- sleep, resume and orderly shutdown events;
- WHEA hardware errors;
- disk, StorPort/storage and NTFS events;
- `volmgr 161`;
- PnP problem events;
- display/GPU reset events;
- application crash/hang/WER events.

The engine keeps event timestamps and record IDs so they can be compared against the final canary samples rather than treated as isolated warnings.

### 4. Driver, firmware and reused-image diagnostics

Crash Doctor records:

- current model, board and BIOS;
- BIOS age;
- current problem PnP devices;
- disconnected-device count using `pnputil`;
- SetupAPI evidence of Sysprep/respecialisation;
- watched low-level driver/service matches including XTU, Conexant, WinRing and similar hardware-access tools.

This is intentionally evidence, not automatic blame. A matched service can raise a hypothesis, but it does not become proof that the service caused the freeze.

### 5. Controlled A/B experiment engine

Crash Doctor can persist one active experiment at a time.

Each experiment records:

- name;
- one variable under test;
- before state;
- after state;
- start boot;
- timestamps;
- final outcome;
- notes.

This directly enforces the troubleshooting rule that one major variable should change at a time.

### 6. Crash-capture readiness doctor

Before interpreting “no dump” or `volmgr 161`, the engine checks:

- whether crash dumps are enabled;
- pagefile allocation;
- whether Windows automatically manages the pagefile;
- physical RAM size;
- configured dump paths.

The output is `LikelyReady`, `Review` or `NotReady`.

This prevents a small or missing pagefile from being misread as evidence that storage itself failed.

### 7. Hardware isolation layer

The engine gathers physical-disk health and Windows storage reliability data when available, including:

- health/operational status;
- temperature;
- read/write error counts;
- uncorrected errors;
- power-on hours.

It also considers WHEA and thermal evidence. RAM/motherboard/CPU remain separate hypotheses because a hard lock can occur without a WHEA event.

### 8. Explainable hypothesis engine

Current hypothesis families are:

- power-state / resume interaction;
- firmware / BIOS interaction;
- low-level OEM / tuning driver interaction;
- reused / migrated Windows image;
- storage / controller failure;
- graphics driver / GPU hang;
- RAM / motherboard / CPU hardware;
- thermal instability;
- crash-capture gap as a diagnostic blocker.

Each hypothesis contains:

- score from 0–100;
- confidence band;
- supporting evidence;
- contradicting evidence;
- unknowns;
- next discriminating test.

**The score is a triage weight, not a probability.**

### 9. Safe solution engine with verification

Crash Doctor produces a staged recommendation sequence rather than firing off broad repairs automatically.

Typical sequence:

1. make dump capture trustworthy if needed;
2. run the power-state A/B test;
3. inspect low-level driver/tuning components;
4. compare/update BIOS through the official OEM path;
5. run extended memory diagnostics if instability persists;
6. isolate the delivered Windows image with a clean OS/live environment;
7. change one major variable at a time and log the result.

Potentially disruptive changes are recommendations, not silent automatic actions.

### 10. Known-pattern and machine-profile system

The app ships with an `hp-probook-11-g2` profile.

The profile contains case-specific priority checks from this investigation but explicitly labels them as **reference-case context**, not current-machine truth. Live collection must still confirm each condition.

Additional machine profiles can be added as JSON without rewriting the collector.

## Architecture

```text
WindowsCrashDoctor
|
+-- canary.ps1
|   +-- startup scheduled task
|   +-- rolling JSONL telemetry
|   +-- heartbeat/state persistence
|   +-- abnormal previous-boot detection
|
+-- WindowsCrashDoctor.psm1
|   +-- machine + BIOS evidence
|   +-- event correlation
|   +-- crash-capture readiness
|   +-- driver/image residue
|   +-- storage evidence
|   +-- hypothesis engine
|   +-- recommendation engine
|   +-- incident bundling
|   +-- experiment ledger
|
+-- windows-crash-doctor.ps1
|   +-- unified CLI for live + snapshot modes
|
+-- CrashDoctor.psm1 / Invoke-CrashDoctor.ps1
|   +-- deterministic offline analysis of collector text snapshots
|   +-- synthetic-fixture regression tests
|
+-- profiles/
|   +-- hp-probook-11-g2.json
|
+-- install.ps1 / uninstall.ps1
|   +-- Program Files installation
|   +-- SYSTEM startup task
|
+-- canonical deep collector
    +-- ../scripts/collect-diagnostics.ps1
```

Runtime state is intentionally outside the Git repository:

```text
%ProgramData%\WindowsCrashDoctor\
  config.json
  state.json
  ledger.jsonl
  canary\
  incidents\
  reports\
  experiments\
  logs\
```

## Two complementary analysis paths

The concurrent development work produced a useful second diagnostic path, so v0.1 deliberately keeps both:

- **Live engine:** current-machine collection, rolling canary, incident reconstruction, ranked hypotheses and experiment tracking.
- **Snapshot engine:** deterministic rule analysis of the text files produced by `scripts/collect-diagnostics.ps1`.

These are not competing collectors. Both depend on the same canonical deep snapshot collector, and the installed `wcd.cmd snapshot` command exposes the offline analyser through the same application. The snapshot engine is especially useful for repeatable regression fixtures and for analysing evidence from a machine that is no longer running.

## Why a scheduled task instead of a custom Windows service

For v0.1, a SYSTEM startup scheduled task gives us:

- no compiled dependency;
- compatibility with Windows PowerShell 5.1;
- straightforward install/uninstall;
- automatic startup before user logon;
- restart-on-failure support;
- easy inspection in Task Scheduler.

If later telemetry shows the PowerShell process itself is too heavy or unreliable, the canary can move to a small signed .NET service without changing the evidence schema or hypothesis engine.

## ProBook reference case

The first profile is tailored to the current HP ProBook 11 G2 investigation.

The reference case currently makes these checks especially important:

- S4/Fast Startup/resume timing;
- current N92 BIOS and firmware device state;
- Intel XTU/other low-level hardware-control components;
- SetupAPI respecialisation and disconnected-device history;
- dump/pagefile readiness;
- clean-OS isolation if the controlled firmware/driver work does not stabilise the machine.

The application must not simply replay those conclusions. It re-collects live evidence every time.

## Safety and privacy

The canary is read-only apart from writing its own evidence files.

The app does **not** automatically:

- flash BIOS;
- uninstall drivers;
- delete devices;
- disable security;
- rewrite the pagefile;
- change registry crash settings;
- disable hibernation/Fast Startup.

Those can be recommended as explicit experiments, with the user choosing when to apply them.

The installed evidence directory can contain private machine metadata and event text. Do not publish it without review.

## QA contract

The Windows CI self-test verifies:

- offline snapshot-rule regression fixtures and public-evidence guard;
- module import and version;
- config creation/parsing;
- one-shot canary collection;
- heartbeat persistence;
- crash-capture inspection;
- driver-residue shape;
- machine facts;
- ProBook profile JSON;
- evidence collection;
- hypothesis count/score bounds;
- recommendation generation;
- JSON + Markdown report generation;
- A/B experiment lifecycle;
- status output;
- packaging prerequisites.

The same workflow builds `WindowsCrashDoctor-v0.1.0.zip` and a SHA-256 sidecar after tests pass.
