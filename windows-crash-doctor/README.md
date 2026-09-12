# Windows Crash Doctor

Windows Crash Doctor is a lightweight Windows hard-freeze diagnostic engine built from the evidence-first ideas used in the Fedora Crash Doctor workflow: keep evidence continuously, reconstruct incidents after reboot, rank explanations transparently, change one variable at a time, and verify whether a proposed solution actually changed stability.

Version: **0.1.0**

## What it does

- runs a low-overhead rolling canary at Windows startup;
- writes every sample incrementally so a hard lock does not erase the pre-freeze timeline;
- detects an abnormal reboot after a missing heartbeat and creates an incident bundle automatically;
- correlates Windows System/Application events with canary telemetry;
- checks pagefile/crash-dump readiness before interpreting missing dumps;
- inventories firmware, BIOS age, problem devices, disconnected-device residue and watched low-level drivers;
- includes storage-health evidence where Windows exposes it;
- ranks hypotheses with supporting evidence, contradicting evidence, unknowns and the next discriminating test;
- tracks one-variable-at-a-time A/B experiments;
- produces machine-readable JSON plus human-readable Markdown reports;
- reuses the repository's existing `scripts/collect-diagnostics.ps1` as the canonical deep snapshot collector;
- includes the complementary offline snapshot analyser already developed for those collector outputs, exposed through the same installed app.

## Install on the ProBook

### Easiest safe path

1. Download this repository as a ZIP from GitHub and extract it.
2. Open **PowerShell as Administrator**.
3. Change into `windows-crash-doctor`.
4. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

### Bootstrap from GitHub

Download the bootstrap first, inspect it if desired, then run it:

```powershell
$u = 'https://raw.githubusercontent.com/joshualparris/hprobooktroubleshoot/main/windows-crash-doctor/bootstrap.ps1'
$p = Join-Path $env:TEMP 'wcd-bootstrap.ps1'
Invoke-WebRequest -UseBasicParsing $u -OutFile $p
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p
```

The bootstrap downloads the current app files over HTTPS and then invokes the local installer. It deliberately avoids the `irm ... | iex` pattern.

## After installation

Windows Crash Doctor installs to:

```text
C:\Program Files\WindowsCrashDoctor
```

Runtime evidence is kept under:

```text
C:\ProgramData\WindowsCrashDoctor
```

Useful commands:

```powershell
& "$env:ProgramFiles\WindowsCrashDoctor\wcd.cmd" status
& "$env:ProgramFiles\WindowsCrashDoctor\wcd.cmd" doctor
& "$env:ProgramFiles\WindowsCrashDoctor\wcd.cmd" collect
& "$env:ProgramFiles\WindowsCrashDoctor\wcd.cmd" sample
```

The scheduled task is named `WindowsCrashDoctor-Canary`.

## Offline snapshot analysis

The app has two complementary modes:

1. **live mode** (`doctor`, canary and incidents) reads the current machine and the rolling timeline;
2. **snapshot mode** analyses a folder previously produced by `collect-diagnostics.ps1`.

Run snapshot analysis through the installed CLI:

```powershell
& "$env:ProgramFiles\WindowsCrashDoctor\wcd.cmd" snapshot `
  -EvidencePath "$env:USERPROFILE\Desktop\HPProBook-YYYYMMDD-HHMMSS"
```

This writes `crash-doctor-report.md` and `crash-doctor-report.json` into the snapshot folder by default. The original `Invoke-CrashDoctor.ps1` entry point remains available for compatibility.

## A/B experiment tracking

Start an experiment before changing one major variable:

```powershell
& "$env:ProgramFiles\WindowsCrashDoctor\wcd.cmd" experiment-start `
  -Name "Fast Startup disabled" `
  -Variable "Fast Startup / hibernation" `
  -Before "Enabled" `
  -After "Disabled"
```

When the test window is over:

```powershell
& "$env:ProgramFiles\WindowsCrashDoctor\wcd.cmd" experiment-end `
  -Outcome stable `
  -Notes "24 hours representative use, 6 cold boots, no hard freeze"
```

Outcomes are `stable`, `failed` or `inconclusive`.

## Incident reconstruction

The canary stores the current boot ID and heartbeat. When a later boot has a different boot ID and Windows records Kernel-Power 41 or EventLog 6008 near startup, Crash Doctor treats the missing prior heartbeat as a candidate hard-stop incident and builds a bundle containing:

- the last pre-incident canary samples;
- relevant Windows events;
- current machine/firmware/driver/storage evidence;
- ranked hypotheses;
- recommended next tests.

You can also create a bundle manually:

```powershell
& "$env:ProgramFiles\WindowsCrashDoctor\wcd.cmd" incident
```

## Important interpretation rule

Scores are **triage weights, not probabilities**. A score is there to order investigation work; it is not a statement such as “70% chance the BIOS caused the crash”.

A hard freeze can prevent Windows from logging the final causal event. Therefore:

1. continuous pre-freeze evidence matters;
2. absence of an event does not automatically clear a subsystem;
3. correlation is not causation;
4. one-variable-at-a-time experiments are the strongest practical discriminator.

## Deep snapshot collector

Crash Doctor does not duplicate the repository's existing deep collector. `install.ps1` copies the canonical `scripts/collect-diagnostics.ps1` into the installed app and the `collect` command invokes that copy.

This keeps **one concept → one source of truth**.

## Packaging and QA

Windows CI runs both the synthetic offline-snapshot rule-engine tests and the live-engine self-test on `windows-latest`, then builds an installable ZIP and SHA-256 file:

```powershell
.\scripts\package-windows-crash-doctor.ps1
```

The ZIP contains both analysis modes, the installer, ProBook profile and canonical deep collector.

## Uninstall

Run elevated:

```powershell
& "$env:ProgramFiles\WindowsCrashDoctor\uninstall.ps1"
```

Diagnostic evidence is kept by default. To remove it too:

```powershell
& "$env:ProgramFiles\WindowsCrashDoctor\uninstall.ps1" -PurgeData
```

## Privacy

Incident bundles can contain machine names, usernames in paths, driver names, device IDs and event text. Treat `%ProgramData%\WindowsCrashDoctor` as private evidence and review reports before publishing them.
