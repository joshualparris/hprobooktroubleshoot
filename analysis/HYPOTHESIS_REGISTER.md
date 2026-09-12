# Hypothesis register

This document separates **observed evidence** from **mechanism hypotheses** so that a plausible story does not become a false certainty.

## H1 — failed HP N92 firmware capsule directly causes CPU/firmware hang

**Supporting evidence**
- Real HP N92 System Firmware 01.60 problem device, Code 10 / failed start.
- Physical BIOS remains N92 01.04.
- Current hangs are low-level enough to leave no BSOD.
- Claude transcript reports capsule removal returns firmware resource to OK.

**Against / unresolved**
- No log directly records an SMI/SMM hang.
- Current 12 Sep freeze's BootAppStatus is 0x0.
- Historical `0xC000007B` boot-app records are not concentrated on the current September events.

**Status:** strong candidate, mechanism unproven. The post-removal stability test is highly informative.

## H2 — S4 / Fast Startup resume path triggers instability

**Supporting evidence**
- Both current September incidents occur within minutes of S4 / Hybrid Shutdown resume.
- Power report reconstructs this independently.

**Against / unresolved**
- Correlation can reflect another driver/firmware component activated on resume.

**Status:** high-confidence trigger/correlation, not necessarily root cause. `powercfg /h off` is the correct A/B test.

## H3 — contaminated generalised Windows image contributes

**Supporting evidence**
- Sysprep Respecialize on 10 Sep.
- 154 non-present devices.
- old HP ProBook 11 G1 computer object.
- old 808F graphics/chipset/audio devices.
- multiple previous SSD device nodes.
- large volume/device history.

**Against / unresolved**
- Sysprep is legitimate in refurbishment workflows.
- Windows can tolerate non-present device history.

**Status:** proven image reuse; causal contribution plausible but not yet isolated. Clean install is a strong later test.

## H4 — Intel XTU / tuning driver causes or contributes to hard hangs

**Supporting evidence**
- live XTU component started in SetupAPI.
- system information shows XTU ACPI/IOC BIOS components and service stack.
- low-level tuning drivers can affect CPU/power behaviour.

**Against / unresolved**
- no proof yet of an actual voltage offset or non-default profile.
- HWiNFO VID alone is not proof of undervolting.

**Status:** medium-high secondary suspect. Record XTU settings before removal.

## H5 — Conexant/HP audio/power service stack contributes

**Supporting evidence**
- CxMonSvc/CxUtilSvc live.
- many historical CxMonSvc application crashes.
- MicTray64 crash history.
- Conexant receives resume/power events near current freeze sequence.

**Against / unresolved**
- user-mode service crashes normally should not freeze the entire kernel.

**Status:** medium.

## H6 — marginal RAM or motherboard

**Supporting evidence**
- genuine whole-system hangs can occur without useful logs.
- quick memory tests do not catch every intermittent failure.

**Against**
- HP quick memory check passed.
- current pattern has strong power/firmware/software correlations.

**Status:** medium; MemTest86 required if software/firmware isolation does not resolve it.

## H7 — current Samsung SSD is failing

**Supporting evidence**
- hard hangs can theoretically come from storage stalls.
- BitLocker was active.

**Against**
- SMART and Short DST pass.
- 0 read errors / uncorrected errors in reliability counters.
- 40 C, Wear 0, 2,242 hours.
- no current AHCI timeout/reset storm around 12 Sep.
- `volmgr 161` can be explained by small pagefile/dump configuration.

**Status:** low at present.
