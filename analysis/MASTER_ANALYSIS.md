# Master analysis — 12 September 2026

## Bottom line

There is still useful information to extract from the evidence, and the deeper pass changed the weighting of several hypotheses.

The best-supported overall problem family is **low-level firmware / power-state / OEM-driver interaction on a contaminated refurb Windows image**, rather than an obvious SSD or simple battery failure. The failed N92 01.60 Windows firmware capsule is a serious abnormality, but the evidence does not yet prove Claude's specific SMI-hang mechanism. The current Windows image is demonstrably generalised/reused, Intel XTU is actively present, and both September hangs occurred shortly after S4 / hybrid-shutdown resume.

## Current physical hardware — high confidence

- HP ProBook 11 G2
- board 818F
- Core i3-6100U, Skylake-U, 2C/4T, 2.30 GHz
- Intel HD Graphics 520, PCI DEV_1916 / subsystem 818F
- one 4 GB SK Hynix HMA451S6AFR8N-TF DDR4-2133 SO-DIMM
- Samsung MZNTY128HDHP-000H1 128 GB SATA SSD
- BIOS N92 Ver. 01.04 dated 2016-11-02

The hardware identity is independently consistent across CIM, HWiNFO, msinfo/System Information and SetupAPI.

## The current freezes are genuine hard hangs

The 12 Sep Kernel-Power 41 event has:

- BugcheckCode 0
- all bugcheck parameters 0
- SleepInProgress 0
- ConnectedStandbyInProgress 0
- WHEABootErrorCount 0
- lid open
- non-zero PowerButtonTimestamp consistent with the user holding power to recover

The display remained lit with the last frame visible. That is consistent with a system hang rather than a simple battery/power loss. There is no causal WHEA, storage-reset, display-TDR or BugCheck trail immediately before the current September hang.

## Power-state correlation — high confidence

The parsed `sleepstudy-report.html` gives a strong common sequence.

### 11 Sep incident

- Hybrid Shutdown from 10 Sep 15:01:57 to 11 Sep 17:29:29
- resume from S4 / display burst
- active for ~166 s
- standby requested at 17:32:16 via button/lid
- standby session never obtains a valid completion timestamp
- next normal activity only after forced restart at ~17:57:56

### 12 Sep incident

- Hybrid Shutdown from 11 Sep 18:41:42 to 12 Sep 14:13:06
- resume S4 display burst
- active ~77 s
- brief screen-off interval
- power button wakes display
- active ~90 s
- abnormal shutdown recorded at 14:15:59 after forced recovery

The common factor is not merely "sleep"; both current incidents followed an **S4 / Fast Startup-style hybrid shutdown resume** within a few minutes. `powercfg /h off` is therefore a valuable clean A/B change because it removes both hibernation and Fast Startup.

## Firmware state — high confidence abnormality, causal mechanism not yet proven

Windows had one problem device:

`HP N92 System Firmware 01.60` → Firmware class → `oem28.inf` → Code 10 / `CM_PROB_FAILED_START` → status `0xC0000001`.

SetupAPI independently records the same UEFI resource configured by `oem28.inf` and left unstarted with Code 10. The physical BIOS remains N92 01.04.

Claude's transcript additionally reconstructs Windows Update history around `HP Inc. - Firmware - 1.60.0.0` and reports that `oem28.inf` was later removed, after which the generic firmware resource returned to OK status. This is plausible and important, but the current ChatGPT session has not independently re-captured the post-removal command output.

The hypothesis that a failed capsule triggers an SMI/SMM hang is technically plausible, but **not directly established by the evidence**. Treat it as a strong mechanism hypothesis, not a proven root cause.

## NEW: the cloned/generalised refurb image is proven more strongly than before

The deeper SetupAPI pass is significant.

On 10 Sep 2026 at 12:40, SetupAPI records **Sysprep Respecialize** on the current HP ProBook 11 G2, BIOS N92 01.04. During that operation it records:

- 263 configured devices
- 10 installed devices
- **154 non-present devices** (121 internal, 33 external)

The retained non-present inventory includes actual prior-device identities, not merely telemetry strings, for example:

- `SWD\\COMPUTER...PROD_HP_PROBOOK_11_G1...` — previous HP ProBook 11 G1 computer object
- Intel graphics DEV_1616 with subsystem 808F
- old 808F-platform PCI/audio devices
- LiteOn LCT-128 SSD
- Samsung MZNLN128HCGR-000 SSD
- SanDisk SD7SN6S-128G SSD
- Toshiba MQ01ACF050 disk
- multiple historical Bluetooth and volume GUIDs

At the same time, current 818F / i3-6100U / DEV_1916 devices are present and started.

This is strong evidence that the seller/refurb workflow reused/generalised a Windows image across hardware before delivery. It does **not prove** the image itself causes the freezes, but it substantially increases the probability of stale OEM driver/services, power-management assumptions and inherited servicing state.

## NEW: Intel XTU is live, not merely historical residue

SetupAPI shows a current `XTUCOMPONENT` bound to `oem24.inf` and **started** on the current ProBook. System Information also shows live XTU components/services including XTU ACPI/IOC BIOS pieces and XTU service processes.

This matters because XTU-class drivers operate below normal user applications and interact with CPU/ACPI/power controls. We do **not** yet have proof that an undervolt or non-default offset is actually configured. Therefore:

- XTU is a legitimate secondary suspect.
- Opening XTU to record any voltage offset / profile before removing it has diagnostic value.
- Do not change it during the current HWiNFO baseline test.

## NEW: `volmgr 161` is weaker evidence for storage failure than it first looked

System Information reports roughly:

- 4 GB physical RAM
- only ~330 MB available at capture time
- page-file space only ~1.38 GB on `C:\\pagefile.sys`

Three `volmgr 161` dump-creation failures were previously used to support a storage-wedge theory. A small/inadequate pagefile can itself make kernel/automatic dump creation fail. Therefore `volmgr 161` should be treated as evidence that crash capture is not reliable, **not evidence that the SSD/storage stack is the cause**.

Before relying on CrashOnCtrlScroll or future kernel dumps, make the page file system-managed / sufficiently large and verify dump configuration.

## NEW: Claude's BootAppStatus argument is overstated for the September freezes

The power-report JSON contains nine sessions with BootAppStatus:

- seven `0xC000007B`
- two `0x0`

However, the seven failures are predominantly historical / wrong-clock / July sessions. The **12 Sep current abnormal-shutdown session has BootAppStatus `0x0` and BootAppCheckpoint `0x0`**.

Therefore the old `0xC000007B` records are worth retaining, but they do **not** prove that the firmware capsule boot app failed on the boot associated with the current September hard hang.

## SSD / storage — currently lower probability

Evidence against an obvious SSD failure:

- HP SMART quick check passed
- HP Short DST passed
- Windows storage reliability counters: PowerOnHours 2242, 0 corrected read errors, 0 total read errors, 0 uncorrected read errors, 40 C, Wear 0
- no current SATA/AHCI timeout-reset storm around the 12 Sep freeze

Historical image records do contain old external/storage problems, including old disks and USB I/O issues. Because the image has crossed hardware, those historical faults cannot automatically be attributed to the current Samsung SSD.

## RAM / board

The HP memory quick check passed, but that is not enough to eliminate marginal RAM or board faults. A full MemTest86 run remains worthwhile if the machine continues hanging after the current software/firmware variables are isolated.

## Conexant / HP OEM driver stack

The current installation includes live Conexant services (`CxMonSvc`, `CxUtilSvc`) and related utilities. Historical Application logs contain repeated CxMonSvc .NET/KERNELBASE crashes and MicTray64 crashes. The Conexant service also receives power-resume notifications around the second current incident.

This is meaningful contamination/noise and a possible contributing driver stack, but there is not enough evidence to claim a Conexant process crash can explain the full kernel-level freeze by itself.

## Battery

The battery report does not support a sudden battery cutout. The frozen lit display also contradicts a simple loss of power. Battery readings that briefly appeared as 0/0 during boot were enumeration timing, not convincing battery-failure evidence.

## BitLocker

BitLocker was 99% encrypted, conversion in progress, XTS-AES 128, protection off/suspended. Repeated 99% status over a short interval is not sufficient to prove conversion is wedged. BitLocker errors around forced restarts can be consequences rather than causes.

The recovery password was exposed in chat and must be rotated. It is deliberately excluded from this repository.

## Current ranked hypotheses

| Rank | Hypothesis | Current weight | Why |
|---|---|---:|---|
| 1 | Firmware/power-state/OEM-driver interaction | High | Both current hangs follow S4 resume; BIOS is ancient; failed firmware capsule state existed |
| 2 | Generalised/cloned refurb Windows image | High as system-quality risk | Sysprep + 154 non-present devices + previous HP G1/device nodes are concrete |
| 3 | Failed N92 01.60 capsule specifically causing hang | Medium-high | Real Code 10 abnormality; removal is a good experiment, but SMI mechanism unproven |
| 4 | Intel XTU low-level driver / tuning state | Medium-high | Current XTU component is started; low-level ACPI/CPU interaction; offset not yet established |
| 5 | Conexant/HP OEM driver stack | Medium | Repeated crashes + resume processing; full-hang causality not proven |
| 6 | Marginal RAM / motherboard | Medium | Hard hangs can evade logs; quick memory test insufficient |
| 7 | Current Samsung SSD failure | Low | Multiple health checks/counters are reassuring |
| 8 | Battery / TPM / DCOM | Low | Evidence does not fit as direct cause |

## Best next evidence

Finish the current 30-minute HWiNFO sensor test without changing anything else. If stable, preserve the CSV and compare against the prior 1–3 minute failures. Then inspect XTU profile/offset without applying changes; run MemTest86; ensure pagefile/dump capture is suitable; and only then proceed to direct HP BIOS 01.60 update after BitLocker safety is handled.

A clean Windows installation remains advisable if the machine is kept, because SetupAPI proves the delivered image is a generalised/refurb image with substantial prior-device history.
