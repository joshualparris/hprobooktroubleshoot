# Evidence timeline

## Historical records in inherited image

The Windows image contains old sessions, wrong-clock sessions (including 2041/2042), previous devices and prior hardware. Historical events are useful for pattern-finding but **cannot automatically be attributed to the current physical HP ProBook 11 G2**.

### 28 Feb 2026 — firmware / driver activity in inherited image
- Claude's log analysis reports Windows Update activity for `HP Inc. - Firmware - 1.60.0.0` including fail/start/success records.
- Current physical BIOS nevertheless remains N92 01.04.
- Intel graphics and multiple OEM components in the present image are dated around this period.

### 25 Mar / Apr / Jul 2026 — historical failures
- Older crash/freeze records exist in the image.
- Some sessions have `BootAppStatus = 0xC000007B`.
- Because the image has been reused across hardware, these are background evidence only unless tied to current hardware IDs.

## Refurb / delivery preparation

### 9 Sep 2026
- SetupAPI shows device/volume cleanup and extensive driver servicing.

### 10 Sep 2026 12:40
- `Sysprep Respecialize` runs on **HP ProBook 11 G2**, BIOS **N92 01.04**.
- SetupAPI sees **154 non-present devices**.
- Retained history includes an HP ProBook 11 G1 computer object, 808F devices and several prior SSDs.

## User-owned period

### 11 Sep 2026 — first day received
- Laptop received from seller.
- First hard freeze occurs shortly after arrival.
- HP UEFI quick memory test passes.
- SSD SMART and Short DST pass.
- Power report sequence later shows Hybrid Shutdown → S4 resume at ~17:29:29 → active ~166 s → standby request at 17:32:16 that never completes cleanly → forced reboot around 17:57:56.
- Later Windows Update / OEM driver activity occurs, including HP/Conexant-related components.
- `Win11Debloat` is recorded later in the evening, after the first freeze, so it cannot be the original cause.

### 12 Sep 2026 ~14:13–14:16 — second current hard freeze
- Resume from S4 / hybrid shutdown at 14:13:06.
- Active ~77 s, brief screen-off, power button display wake, active ~90 s.
- User observes a lit frozen lock screen.
- Forced power-off produces Kernel-Power 41 at ~14:15:59.
- BugcheckCode 0; WHEABootErrorCount 0; no recorded BSOD.
- BootAppStatus for this current abnormal-shutdown session is **0x0**, not `0xC000007B`.

### 12 Sep — investigation changes
- `powercfg /h off` disables hibernation and Fast Startup.
- BitLocker protectors disabled/suspended; conversion still reports 99%.
- `pnputil /enum-devices /problem` identifies exactly one problem device: HP N92 System Firmware 01.60, `oem28.inf`, Code 10.
- Claude-session transcript reports `oem28.inf` was then uninstalled and the firmware resource returned to generic/OK state. This post-removal state should be independently re-captured in this repository later.
- HWiNFO confirms current hardware and BIOS.
- 30-minute HWiNFO sensor logging begins; result pending at repository snapshot time.
