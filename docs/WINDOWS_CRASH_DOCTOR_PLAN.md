# Windows Crash Doctor plan

## Purpose

Windows Crash Doctor turns a `collect-diagnostics.ps1` snapshot into a compact, reproducible diagnostic report without making any machine changes.

The first target is this HP ProBook 11 G2 hard-freeze investigation, but the architecture is deliberately generic enough to grow into a reusable Windows crash/hang triage tool.

## Non-goals

Crash Doctor does not:

- declare a root cause solely because one abnormal event exists;
- treat `Kernel-Power 41` as the cause of a crash;
- flash BIOS/UEFI;
- uninstall drivers;
- change BitLocker, pagefile, dump or power settings;
- upload private logs automatically;
- require third-party PowerShell modules.

Those actions either mutate evidence or have enough risk that they should remain explicit.

## Data flow

```text
Windows machine
    |
    v
scripts/collect-diagnostics.ps1
    |
    +-- text snapshots
    +-- recent EVTX exports
    +-- SetupAPI
    +-- battery/system power reports
    +-- msinfo32 NFO
    |
    v
windows-crash-doctor/Invoke-CrashDoctor.ps1
    |
    v
CrashDoctor.psm1
    |
    +-- inventory parsing
    +-- rule evaluation
    +-- evidence/confidence separation
    +-- coverage accounting
    |
    +--> crash-doctor-report.md
    +--> crash-doctor-report.json
```

## Rule contract

Every rule returns the same fields:

| Field | Meaning |
|---|---|
| `Id` | stable machine-readable identifier |
| `Severity` | operational priority, not certainty |
| `Confidence` | confidence that the evidence/interpretation is valid |
| `Title` | concise human label |
| `Evidence` | what was actually observed |
| `Interpretation` | what that evidence supports — no stronger |
| `NextStep` | smallest useful diagnostic action |

A rule must not smuggle causality into the `Evidence` field.

## Current rule families

### Firmware / device state

Detects a firmware-class Code 10 / `CM_PROB_FAILED_START` state and can also record a current Firmware-class `Status: OK` post-change snapshot. A failed-start state is high-priority evidence, but it does not itself prove that firmware caused the hang.

### Deployment-image history

Detects `Sysprep Respecialize` and records the largest non-present-device count found in SetupAPI. This identifies reused/generalised deployment history and helps prevent historical devices from being mistaken for current hardware.

### Power/tuning stack

Detects Intel XTU and Conexant-related evidence. Presence is reported separately from proof of a non-default tuning profile or driver-triggered crash.

### Crash-capture quality

Reads pagefile/dump state and warns when future dump absence would be weak evidence.

### Storage

Reads Windows storage-reliability counters. Clean counters reduce the priority of a simple failing-SSD theory but never fully clear intermittent storage/controller faults.

### Event evidence

Summarises WHEA, Kernel-Power 41 and volmgr 161 from the collector's recent text event export. The rules deliberately distinguish “found” from “caused”.

## Output schema

`crash-doctor-report.json` is the automation boundary. Top-level fields are:

- `SchemaVersion`
- `GeneratedAt`
- `EvidencePath`
- `Coverage`
- `Inventory`
- `EventSummary`
- `Findings`

New rule fields should be additive where possible so older consumers do not break.

## Testing strategy

`tests/self-test.ps1` generates synthetic abnormal and quiet evidence folders rather than relying on private real-world logs. It verifies:

- expected rules fire;
- high-severity false positives do not appear on the quiet fixture;
- inventory parsing works, including multiple memory modules;
- evidence-discipline language remains in the Markdown report;
- CLI output files are created;
- the repository public-evidence guard passes.

CI runs on `windows-latest` because the production environment is Windows PowerShell.

## Security model

Raw troubleshooting evidence is private by default. The public repository stores analysis, manifests, reviewed extracts and tooling.

`scripts/check-public-evidence.ps1` blocks the strongest known accidental leak in this case: an eight-group BitLocker recovery password. It is intentionally documented as a narrow guard rather than a complete secret-scanning product.

## Near-term roadmap

1. Add an HWiNFO CSV analyser for thermal/power/time-series evidence.
2. Add an explicit freeze-timestamp file so pre-hang event windows can be scored reproducibly.
3. Parse EVTX directly when a dependency-free or safely vendored path is available.
4. Add a `profiles/` layer for model-specific facts without hard-coding them into generic rules.
5. Add an optional public-summary exporter that strips common identifiers.
6. Add more fixture-based regressions for partial/malformed evidence and additional Windows versions.
7. Version the JSON schema once external consumers appear.

## ProBook case integration

For the current case, Crash Doctor should help answer the next narrow questions rather than invent a final answer:

- Is the firmware device still abnormal after the reported package removal?
- Does the machine remain stable with Fast Startup/hibernation disabled?
- Is XTU merely installed, or is non-default tuning active?
- Is dump capture configured well enough for a future hang/forced dump?
- Does HWiNFO show thermal, voltage or power-limit behaviour near a freeze?
- Does instability survive updated firmware, known-good RAM and a clean OS?
