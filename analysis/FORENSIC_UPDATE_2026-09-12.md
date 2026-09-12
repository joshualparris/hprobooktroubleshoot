# HP ProBook 11 G2 forensic update — 12 September 2026

## Purpose

This update correlates the new 12 September evidence set rather than treating each file in isolation. The emphasis is the HWiNFO sensor log, but the conclusions also use the supplied Windows System Power Report, battery report, MSINFO32 export and binary EVTX logs.

The goal is **not** to name a root cause prematurely. Each conclusion below distinguishes what the evidence proves from what remains a hypothesis.

## Evidence reviewed

- HWiNFO sensor CSV (`sensors(1).CSV`), ~46 minutes of ~2-second samples;
- Windows battery report;
- Windows System Power Report / SleepStudy HTML;
- MSINFO32 text export;
- nine supplied EVTX exports (`a` through `i`);
- existing repository evidence and prior hypothesis register;
- current official HP BIOS information and Microsoft Windows 11 processor support information.

Raw security/audit EVTX data is **not** being committed to this public repository. One supplied log contains account/audit information and should remain private unless intentionally reviewed and redacted.

## Executive findings

### 1. The sensor capture materially weakens overheating as an explanation

The sensor CSV contains 1,374 timestamped samples from approximately **15:07:27 to 15:53:24 local** (~45.9 minutes). Sampling remained continuous: the largest interval between samples was only about **2.4 seconds**.

During that capture:

- CPU package temperature stayed approximately **38–52 C**;
- CPU package median was about **40 C** and P95 about **45 C**;
- core/package thermal-throttle and critical-temperature flags remained **No**;
- HWiNFO's hardware-error counter remained at **0**;
- GPU temperature stayed roughly **38–47 C**;
- drive temperature stayed roughly **30–44 C**.

This is strong bounded negative evidence against a thermal failure **during this capture**. It cannot prove what temperature was doing at an earlier uncaptured freeze.

### 2. Severe memory pressure is real and persistent

The same capture shows a much more useful chronic stress signal:

- physical-memory load minimum: **~78.9%**;
- median: **~84.2%**;
- P95: **~86.2%**;
- maximum: **~92.1%**;
- minimum available physical memory: **~311 MB**;
- virtual-memory load maximum: **~84.7%**;
- page file observed by HWiNFO: about **2,636 MB total**, up to roughly **724 MB used**.

MSINFO32 independently recorded only about **330 MB available physical memory** on a machine with **4 GB installed**, which corroborates the sensor result.

At about **15:16:16**, the log captured a short combined stress point: CPU reached 100%, RAM was ~92%, and disk activity was ~58%. The sensor logger continued sampling normally through it, so that burst was not itself a captured hard freeze.

**Interpretation:** 4 GB is demonstrably creating paging/headroom pressure and can plausibly explain severe pauses or apparent freezes. It does **not**, by itself, explain a forced power-off / abnormal-shutdown mechanism.

### 3. A fresh firmware failed-start state is confirmed

The new MSINFO32 export reports:

- physical BIOS: **HP N92 01.04**, dated 2016;
- problem device: **HP N92 System Firmware 01.60**;
- state: **This device cannot start**.

HP's April 2023 BIOS refresh lists **HP ProBook 11 G2 Education Edition System BIOS (N92) [01.60]**. This means the machine is physically on a much older BIOS while Windows has a 01.60 firmware resource that is failing to start.

Official HP reference:
https://support.hp.com/pt-pt/document/ish_8896930-8896970-16

**Interpretation:** this is a concrete low-level abnormality and now a higher-priority investigation path. It still does not prove that firmware caused the hard freeze.

### 4. The System Power Report gives a precise current incident boundary

After filtering sessions to the report's own declared seven-day window, the relevant current failure is:

- **12 Sep 2026 14:15:59 local** — `Abnormal Shutdown`, **on battery**;
- **14:16:33** — new active session after reboot;
- **14:33:14** — active session changes to AC power;
- **14:56:16** — report generated.

The report also contains old/future-dated failure records, including a 2042 bugcheck entry. Those records fall **outside** the report's declared time window and must not be counted as current incidents.

This matters because the reused/generalised Windows image already contains inherited/stale history. A naive parser would produce false crash counts.

### 5. The binary System log supports the same reboot boundary

A structural read of the supplied System EVTX shows activity around **04:14 UTC**, followed by the next boot sequence beginning around **04:15:56 UTC** (14:15:56 local). BitLocker/NTFS and normal boot providers then appear, followed by Kernel-Power startup records.

No clear pre-incident thermal, disk-timeout or display-driver storm was identified in the recoverable strings immediately before that boundary.

Important limitation: this environment did not have a full Windows EVTX parser available, so the binary logs were inspected conservatively using record structure/timestamps/provider strings rather than pretending to have complete XML event decoding. The Windows collector's text exports remain the preferred rule-engine input.

### 6. Storage looks comparatively reassuring in the captured period

HWiNFO reports:

- drive remaining life around **86%**;
- `Drive Failure`: **No** throughout;
- `Drive Warning`: **No** throughout;
- normal low median disk activity with transient workload spikes;
- no thermal issue at the drive.

There was no convincing incident-time storage fault signature in the supplied logs. This weakens a simple “the SSD is dying” theory, though intermittent controller/device faults are not impossible.

### 7. Battery data does not show a simple collapse, but the power path remains relevant

The abnormal shutdown happened while on battery, so the DC power path cannot be dismissed.

However:

- the post-reboot session continued on battery at high charge;
- there is no clear sudden capacity-collapse signature;
- the battery report currently shows design capacity and full-charge capacity both as **54,989 mWh**;
- historical “design capacity” values change substantially across weeks, sometimes above 63 Wh, and track full-charge capacity suspiciously closely;
- HWiNFO's battery fields remained essentially static during the later capture.

Therefore battery wear percentage is not reliable enough here to diagnose the incident. Treat battery/power delivery as a testable hypothesis, not the current lead.

### 8. Brief GPU/ring limit flags occurred, but without matching heat or errors

Around **15:13–15:16**, HWiNFO recorded short `GT` / ring limit-reason flags, including fuse/electrical-limit style indicators. They occurred at low temperatures, with no WHEA increment and no captured hard freeze.

These are retained as a **low-priority power-management clue**, not evidence of GPU failure.

### 9. Windows 11 is running outside the normal supported CPU generation list

The machine is an **Intel Core i3-6100U (6th generation)** running Windows 11 24H2. Microsoft's current Windows 11 24H2 Intel processor list starts the Core family at **8th-generation Core** processors rather than 6th generation.

Microsoft reference:
https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-24h2-supported-intel-processors

This does not mean Windows 11 must be the root cause. It does mean platform/driver/firmware behaviour is occurring outside Microsoft's normal supported CPU baseline and therefore deserves weight when interpreting an old OEM image and firmware stack.

## Incident timeline

| Local time | Evidence | Interpretation |
|---|---|---|
| ~14:13–14:14 | Power report shows screen-off/active transitions after earlier hibernate/shutdown history | Consistent with the established post-S4 correlation; not proof of mechanism |
| 14:15:59 | System Power Report: abnormal shutdown, battery | Precise current incident marker |
| 14:16:33 | Active session begins | Successful reboot/new session |
| ~14:29 | MSINFO32 snapshot | Only ~330 MB physical RAM available; firmware 01.60 device cannot start; physical BIOS still 01.04 |
| 14:33:14 | Power source changes to AC | Post-incident, not causal evidence |
| 14:56:16 | System Power Report generated | Ends its current report window |
| 15:07:27 | HWiNFO capture starts | Later stability/telemetry window |
| ~15:13–15:16 | Short GT/ring limit flags | Low-priority electrical/power-management clue |
| ~15:16:16 | CPU 100%, RAM ~92%, disk ~58% | Real workload stress burst; logger remains continuous |
| 15:53:24 | HWiNFO capture ends | No thermal/WHEA/hard-freeze evidence in ~46-min capture |

## EVTX triage notes

The supplied binary logs appear to cover several channels and time ranges. They also contain inherited/future-dated material, reinforcing the need for time-window filtering.

| File | Main useful observation |
|---|---|
| `a(4).evtx` | Mixed system/device history, including Kernel-PnP/TPM/Windows Update/WLAN; contains stale future timestamps |
| `b(3).evtx` | Application-oriented records such as RestartManager/WMI/Synaptics/MSIX; little direct incident-time evidence |
| `c(3).evtx` | Security/audit activity; **contains sensitive account information and must not be published raw** |
| `d(3).evtx` | Setup/servicing history; mainly older staging activity |
| `e(3).evtx` | Best incident correlation: System activity before 14:15 local followed by the next boot sequence around 14:15:56 local |
| `f(3).evtx` | Mixed System/Application/OEM history including Conexant references |
| `g(3).evtx` | Repeated Conexant `CxMonSvcLog` polling; noisy but no direct crash signature |
| `h(3).evtx` | Intel Graphics Command Center history; no useful incident-time correlation |
| `i(3).evtx` | Windows PowerShell history; no useful incident-time correlation |

## Ranked current hypotheses

### Higher priority

**Firmware / power-state interaction** — strengthened by the fresh Firmware-class failed-start state, old physical BIOS and incident clustering around S4/hybrid-resume history.

**Unsupported-platform / old-driver-image interaction** — Windows 11 24H2 on a 6th-gen CPU plus a reused/generalised image increases the chance of brittle firmware/OEM-driver behaviour. This is a compatibility risk, not direct proof.

### Important contributing factor

**Memory pressure** — strongly proven as a performance/stall problem. It should be isolated because reducing it may improve stability, but it should not be mistaken for proof of the abnormal-shutdown mechanism.

### Medium/low priority

**Battery/DC power delivery** — incident occurred on battery, but there is no collapse signature.

**Conexant / Intel graphics / other OEM stack** — old components are present, but no direct incident-time fault signature has been demonstrated.

### Currently weakened

**Overheating** — strongly weakened for the HWiNFO capture.

**Straightforward SSD failure** — weakened by clean drive flags and lack of a matching incident-time storage signature.

## Recommended next discriminating sequence

1. **Do not stack changes.** Continue the current Fast-Startup/hibernation A/B window long enough to make the result meaningful.
2. **Make crash capture reliable.** Use a system-managed or adequately sized pagefile and an appropriate automatic/kernel dump policy before interpreting future missing dumps.
3. **Record XTU state** before changing/removing it. Presence is known; active tuning is not.
4. **Prepare for an official BIOS update**: confirm BitLocker recovery-key access, reliable AC power and HP's N92 recovery/update method. The physical 01.04 BIOS is substantially behind HP's published 01.60 release.
5. **After BIOS update, re-capture** BIOS version, Firmware-class PnP state, System events and System Power Report. The key discriminator is whether the failed 01.60 firmware device disappears and stability changes.
6. **Repeat sensor logging** through normal workload and, ideally, through the next incident. Crash Doctor can now ingest the HWiNFO CSV directly.
7. **Isolate memory pressure separately.** If practical, compare representative workload with more RAM; otherwise keep the 4 GB limitation in mind during every “freeze” report.
8. **Use clean-OS isolation if instability survives firmware and RAM testing.** This distinguishes inherited Windows/OEM state from hardware.
9. **Stop indefinite software tweaking** if updated firmware + reliable crash capture + known-good memory + clean OS still produce low-level freezes; that is the point to use return/warranty/hardware replacement paths.

## Windows Crash Doctor changes prompted by this evidence

The 12 September evidence exposed two blind spots in the existing tool: it collected a System Power Report without analysing it, and it had no sensor-log ingestion.

This update therefore adds:

- HWiNFO-style CSV parsing that safely handles duplicate sensor headers;
- sustained physical-memory-pressure detection;
- CPU thermal/throttle assessment;
- HWiNFO WHEA-counter assessment;
- drive-health flag interpretation;
- sample-gap detection, allowing a captured logging pause to become timeline evidence;
- combined CPU/RAM/disk workload-burst detection;
- bounded interpretation of transient GT/ring limit flags;
- System Power Report `LocalSprData` parsing;
- **hard filtering of power-report failures to the report's declared time window**;
- abnormal-shutdown and in-window bugcheck findings;
- explicit reporting of ignored stale/future failure records;
- optional `-SensorCsvPath` support in the collector;
- a telemetry self-test fixture, including a future 2042 bugcheck that must be ignored.

The analyser remains read-only. It will not silently change BIOS, drivers, BitLocker, power settings, pagefile policy or HWiNFO configuration.
