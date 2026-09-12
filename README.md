# HP ProBook 11 G2 hard-freeze investigation

Central troubleshooting log for an HP ProBook 11 G2 that began hard-freezing immediately after purchase in September 2026.

## Current machine

- HP ProBook 11 G2 / board 818F
- Intel Core i3-6100U, 2C/4T, 2.30 GHz
- Intel HD Graphics 520
- 4 GB SK Hynix HMA451S6AFR8N-TF DDR4-2133, single-channel
- Samsung MZNTY128HDHP-000H1 128 GB SATA SSD
- BIOS N92 Ver. 01.04, 2 Nov 2016
- Windows 11 Pro 24H2 (unsupported CPU/TPM configuration)

## Symptom

The machine has produced genuine whole-system hard hangs with the display still lit/frozen and no recorded BSOD. Recovery required holding the power button. The current September incidents occurred within minutes of resuming from S4 / Fast Startup-style hybrid shutdown sessions.

## Strongest evidence so far

1. HP quick memory test passed; SSD SMART and Short DST passed.
2. Windows storage reliability counters show 0 read errors, 0 uncorrected errors, 40 C SSD temperature and 2,242 power-on hours.
3. The current BIOS is still N92 01.04 from 2016.
4. Windows had an HP N92 System Firmware 01.60 capsule device bound to `oem28.inf` in Code 10 / `CM_PROB_FAILED_START` state. The Claude-session transcript reports this package was subsequently uninstalled and the firmware resource returned to generic/OK status.
5. `setupapi.dev.log` proves the Windows image was Sysprep-respecialised onto this ProBook on 10 Sep 2026 and retained **154 non-present devices**, including an old HP ProBook 11 G1 computer object, 808F-platform devices, old Intel graphics and multiple previous SSDs. This is stronger evidence of a generalised/cloned refurb image than firmware telemetry alone.
6. Intel XTU is not merely historical residue: SetupAPI and system information show a live XTU component / ACPI driver stack on the current installation.
7. Conexant OEM audio services are live and have a substantial crash history; they also process power-resume notifications.
8. `powercfg /h off` has disabled hibernation and Fast Startup for the current A/B stability test.
9. A 30-minute HWiNFO sensor log is in progress as of this repository snapshot.

## Important evidence corrections

- The seven `BootAppStatus = 0xC000007B` records in the power report are largely historical / wrong-clock / July sessions. The reboot associated with the **12 Sep current freeze records `BootAppStatus = 0x0`**, so the old `0xC000007B` records do not prove a firmware boot app failed during the current hang.
- `volmgr 161` dump-creation failures do not by themselves prove the storage stack wedged. The machine has only about **1.38 GB page-file space**, which can itself make kernel/automatic crash-dump capture unreliable.
- Four `manage-bde` checks remaining at 99% do not prove BitLocker caused the hangs.
- Battery evidence does not support a simple power cut; the frozen lit screen and power-button timestamp support a true hang.
- The cloned-image hypothesis is **not dead**: SetupAPI contains actual previous computer/device nodes, not just N92/N72 telemetry strings.

## Repository layout

- `analysis/` — current interpretation, timeline, hypothesis register, Claude comparison, raw-evidence status and next-test plan
- `conversation/` — integrity notes for the supplied ChatGPT/Claude conversation records; originals are in the complete evidence archive
- `evidence/manifests/` — SHA-256 hashes and duplicate mapping for every mounted evidence file
- `raw/` — directly committed raw items plus the complete-archive integrity record
- `scripts/` — repeatable diagnostic collection commands
- `SECURITY_NOTICE.md` — public-repository redaction note

## Raw binary evidence

The original conversation includes large EVTX files, screenshots and reports. The connected GitHub writer cannot accept a local sandbox file directly, and routing tens of megabytes of binary data through model text risks truncation/corruption. Every supplied file is therefore recorded by filename, byte size and SHA-256 in `evidence/manifests/evidence-manifest.csv`, and a lossless complete archive was built in the working sandbox. See `raw/README.md`.

One small raw report (`battery-report.html.gz`) is committed directly as a connector integrity test. The large raw archive is not falsely claimed as uploaded.

**Do not add the exposed BitLocker recovery password to this repository.**
