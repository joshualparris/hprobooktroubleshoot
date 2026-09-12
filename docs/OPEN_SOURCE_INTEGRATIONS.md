# Open-source integrations

Windows Crash Doctor deliberately **does not vendor whole third-party repositories or binaries**. Instead, it has a small provider layer that can download selected official GitHub release assets on explicit request, verify SHA-256 when GitHub publishes a release digest, and run them as separate tools. This keeps provenance clear, avoids silently expanding the trusted codebase, and preserves upstream licence boundaries.

The catalogue is machine-readable at [`windows-crash-doctor/integrations/catalog.json`](../windows-crash-doctor/integrations/catalog.json).

## Relevant projects reviewed

| Project | Licence | Value to Crash Doctor | Integration status |
|---|---|---|---|
| `LibreHardwareMonitor/LibreHardwareMonitor` | MPL-2.0 | Temperatures, voltages, clocks, loads, fans and storage sensors | **Integrated** — verified release download + live JSONL sensor watcher |
| `smartmontools/smartmontools` | GPL-2.0 | Deep SMART/ATA/NVMe health and error data | **Integrated when installed** — read-only `smartctl` adapter; installer is download-only because current upstream release has no GitHub SHA-256 digest |
| `omerbenamram/evtx` | Apache-2.0 OR MIT | Fast, safe EVTX parsing to JSON/JSONL/XML | **Integrated** — verified standalone `evtx_dump` release + deterministic single-thread conversion |
| `Yamato-Security/hayabusa` | AGPL-3.0 | EVTX forensics timeline and Sigma enrichment | **Integrated, opt-in** — verified Windows live-response package, separate-process timeline adapter |
| `osquery/osquery` | Apache-2.0 OR GPL-2.0-only | Structured system/driver/service/software inventory | **Integrated, opt-in** — verified portable Windows release + read-only inventory adapter |
| `microsoft/perfview` | MIT | ETW/TraceEvent performance and hang tracing | **Download integrated, capture manual** — verified `PerfView.exe`; Crash Doctor will not silently start high-overhead tracing |
| `pester/Pester` | Apache-2.0 | PowerShell tests/mocks | **Integrated in CI** |
| `PowerShell/PSScriptAnalyzer` | MIT | PowerShell static analysis | **Integrated in CI** |
| `memtest86plus/memtest86plus` | GPL-2.0 | RAM test independent of Windows | **Catalogued/manual** — requires reboot/boot media |
| `chipsec/chipsec` | GPL-2.0 | Deep firmware/platform inspection | **Catalogued/manual** — privileged low-level tool; never auto-run on a warranty machine |
| `Jinjinov/Hardware.Info` | MIT | Portable .NET hardware inventory | **Catalogued/future** — overlaps current CIM + LibreHardwareMonitor collection |
| `Velocidex/velociraptor` | Upstream custom licence; GitHub metadata reports `NOASSERTION` | Full endpoint DFIR/orchestration platform | **Catalogued/not imported** — excessive footprint for this single-machine diagnostic scope |
| `WithSecureLabs/chainsaw` | Upstream repository currently redirects; verify current canonical licence before use | EVTX hunting/timeline alternative | **Catalogued/not imported** — `evtx` + Hayabusa already cover the immediate role |

This is the high-value set for the present application scope; it is not a claim that every open-source Windows diagnostic repository on GitHub has been enumerated.

## Why these are providers instead of copied source

Copying an entire upstream repository would add thousands of files we do not own, make upgrades harder, create unnecessary licence/distribution obligations, and make it difficult to prove which executable was actually used during a diagnostic run. Crash Doctor instead records the upstream repository, release tag, asset URL, expected digest (when available), actual local SHA-256 and installation time in `installation.json` beside each downloaded tool.

Third-party tools are stored outside the repository by default under:

```text
%LOCALAPPDATA%\WindowsCrashDoctor\Tools\
```

They are never committed by the project workflow.

## Commands

From the repository root:

```powershell
# See every reviewed integration and its local status
.\windows-crash-doctor\Manage-Integrations.ps1 -Action status

# Install a release whose GitHub asset includes SHA-256 provenance
.\windows-crash-doctor\Manage-Integrations.ps1 -Action install -Id librehardwaremonitor
.\windows-crash-doctor\Manage-Integrations.ps1 -Action install -Id evtx
.\windows-crash-doctor\Manage-Integrations.ps1 -Action install -Id hayabusa
.\windows-crash-doctor\Manage-Integrations.ps1 -Action install -Id osquery
.\windows-crash-doctor\Manage-Integrations.ps1 -Action install -Id perfview

# 30-minute sensor record at two-second intervals
.\windows-crash-doctor\Manage-Integrations.ps1 -Action sensors -DurationMinutes 30 -IntervalSeconds 2 -OutputPath .\sensor-run.jsonl

# Convert an exported EVTX to ordered JSONL
.\windows-crash-doctor\Manage-Integrations.ps1 -Action evtx -Path .\System.evtx -OutputPath .\System.evtx.jsonl

# Generate an optional Hayabusa timeline from an evidence directory
.\windows-crash-doctor\Manage-Integrations.ps1 -Action timeline -Path .\HPProBook-20260912-160000 -OutputPath .\timeline.csv

# Structured read-only osquery inventory
.\windows-crash-doctor\Manage-Integrations.ps1 -Action osquery -OutputPath .\osquery.json

# Deep SMART capture when smartctl is already installed
.\windows-crash-doctor\Manage-Integrations.ps1 -Action smart -OutputPath .\smart.json
```

## Supply-chain rules

1. Automatic downloads come only from the configured upstream GitHub `releases/latest` endpoint.
2. Exactly one asset must match the pinned asset pattern; ambiguous matches fail closed.
3. If GitHub publishes a `sha256:` digest, Crash Doctor verifies it before extraction or activation.
4. If the upstream release has no SHA-256 digest, automatic installation fails unless the operator deliberately supplies `-AllowUnverified`. For installers such as smartmontools, the preferred path is to verify/install it independently and let Crash Doctor discover `smartctl.exe`.
5. Downloading a tool does **not** execute an installer.
6. Privileged/rebooting tools such as CHIPSEC and Memtest86+ cannot be auto-installed by this module.
7. PerfView is downloadable but Crash Doctor does not start ETW capture automatically. A trace is an experimental variable that can change system load.
8. Hayabusa is opt-in because its Sigma content can trigger antivirus detections; the live-response asset is selected because upstream specifically provides it to reduce that problem.

## Evidence and privacy

Integration output can contain usernames, process paths, device identifiers and other sensitive information. Generated sensor, SMART, osquery, EVTX and timeline outputs are ignored by Git by default. Keep unredacted originals private and follow [`SECURITY_NOTICE.md`](../SECURITY_NOTICE.md) before publishing anything.

## Architecture rule

Third-party output is **evidence**, not a diagnosis. Crash Doctor should preserve the same discipline used by the existing engine:

> observed value → provenance → interpretation → confidence → next discriminating test

A SMART warning, Hayabusa rule hit, sensor spike, Code 10, or ETW anomaly must not automatically be promoted to “root cause” without corroborating evidence.
