# Windows Crash Doctor Desktop

Native WPF front end for the Windows Crash Doctor evidence engine.

Current source identity is **0.3.0-preview.1** with embedded engine **0.3.0**. Release readiness is separate from source versioning; see [`../../docs/RELEASE_VERIFICATION.md`](../../docs/RELEASE_VERIFICATION.md).

## User experience

The desktop app provides:

- a dashboard with system-health cards;
- one-click **Run Full Diagnosis** with preflight and UAC only when collection needs it;
- live CPU and RAM gauges plus periodic CPU/SSD temperature readings where the machine exposes them;
- optional LibreHardwareMonitor deep sensor capture, consumed by the same telemetry analysis layer as supported HWiNFO CSV evidence;
- ranked evidence findings with severity, confidence and recommended next action;
- current machine model / BIOS / RAM summary;
- a local SQLite diagnostic run ledger with legacy JSON migration;
- evidence/finding fingerprints and previous comparable-run comparison;
- diagnostic-registry-backed coverage/provenance;
- bounded PowerShell timeout/cancellation/retry handling;
- native `.dmp` / `.mdmp` analysis through Crash Doctor's dump parser;
- open-source provider installation/status UI;
- privacy-reviewed shareable ZIP export with high-risk exclusions, text redaction and an export manifest;
- light and dark themes.

## Engine boundary

The PowerShell engine remains the source of truth for collection and core rule analysis. Required engine files — including `TelemetryAnalysis.psm1`, diagnostic registry files and version metadata — are embedded into the executable and extracted under:

`%LOCALAPPDATA%\WindowsCrashDoctor\engine\0.3.0`

The packaged executable exposes `--self-test`. The Product Gate uses that path to prove the **built EXE** can extract and execute its embedded engine instead of assuming `dotnet publish` is sufficient.

The v2 integration is substantial but not total: registry metadata/coverage/provenance is canonical, while every collector command is not yet dispatched independently from the registry; likewise individual collector evidence records are partly derived from output presence rather than every probe having its own subprocess timing/retry lifecycle.

## History, comparison and preflight

`HistoryService` stores diagnostic runs locally in SQLite (`history.db`) with normalized run, finding, collector-execution and comparison records. Existing `history.json` is migrated when possible and left untouched with a visible warning on migration failure.

Before a full run, preflight checks Windows/platform state, elevation, embedded-engine extraction, registry availability, output writability/free space, SQLite health, PowerShell, CIM, Event Log access, dump readiness, debugger/symbol configuration and optional sensor-provider presence. Blocking prerequisites stop the affected diagnosis; optional gaps can produce a degraded state instead.

Finding/evidence fingerprints allow comparison with the latest comparable run on the same device. Comparison states include `NEW`, `RESOLVED`, `IMPROVED`, `WORSENED`, `UNCHANGED` and `UNKNOWN`, with coverage used to avoid falsely calling an absent finding resolved when the new evidence is incomplete.

## Privacy-reviewed export

The shareable ZIP workflow plans the bundle before creation, shows inclusion/exclusion/redaction counts, excludes high-risk or unscannable artefacts by default, redacts known sensitive text patterns in derivatives and writes `export-manifest.json`. Original evidence is not modified.

This is a conservative safety layer, not a guarantee that every possible secret or identifier can be detected.

## Build

```powershell
dotnet publish .\desktop\WindowsCrashDoctor.App\WindowsCrashDoctor.App.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true
```

A local build is not a release proof. The canary Product Gate additionally runs the PowerShell engine suite, dump tests, public-evidence guard and `WindowsCrashDoctor.exe --self-test`, then creates checksummed release assets plus `release-manifest.json`. Only that already-verified artifact is handed to the canary publication job.

## Security and release status

The executable is currently unsigned, so Windows SmartScreen can show **Unknown Publisher** even for a genuine build. Current GUI/CLI installers verify downloaded release assets by SHA-256 before activation, but that does not provide Authenticode publisher trust.

The rolling canary may intentionally remain on an older known artifact when the latest Product Gate is red. Check [`../../docs/RELEASE_VERIFICATION.md`](../../docs/RELEASE_VERIFICATION.md) before describing or installing the canary as the current verified build.

Crash Doctor does not automatically upload evidence, flash firmware, remove drivers or alter BitLocker settings.