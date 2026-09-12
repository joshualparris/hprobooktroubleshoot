# Windows Crash Doctor Desktop

Native WPF front end for the Windows Crash Doctor evidence engine.

## User experience

The desktop app is intentionally a real app rather than a PowerShell console wrapper. It provides:

- a modern dashboard with system-health cards;
- one-click **Run Full Diagnosis** with UAC only when collection needs it;
- live CPU and RAM gauges plus periodic CPU/SSD temperature readings where the machine exposes them;
- optional 30-minute LibreHardwareMonitor deep sensor capture for pre-freeze telemetry;
- ranked evidence findings with severity, confidence and recommended next action;
- current machine model / BIOS / RAM summary;
- local diagnostic history;
- native `.dmp` / `.mdmp` analysis through Crash Doctor's dump parser;
- open-source provider installation/status UI;
- privacy-aware ZIP export;
- light and dark themes.

## Engine boundary

The existing PowerShell engine remains the source of truth for collection and rule analysis. Required engine files are embedded into the executable and extracted to `%LOCALAPPDATA%\WindowsCrashDoctor\engine\0.1.0` when the app starts.

This keeps the GUI replaceable while preserving the evidence-first rules, tests and command-line workflow.

## Build

```powershell
dotnet publish .\desktop\WindowsCrashDoctor.App\WindowsCrashDoctor.App.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true
```

CI publishes a rolling preview release with `WindowsCrashDoctor.exe` and its SHA-256 checksum.

## Security

The executable is currently unsigned. Windows SmartScreen can therefore show an **Unknown Publisher** warning even when the file is the genuine GitHub Actions build. Verify the release SHA-256 when provenance matters.

Crash Doctor does not automatically upload evidence, flash firmware, remove drivers or alter BitLocker settings.
