# HP ProBook 11 G2 purchase, seller assessment and eBay review

**Consolidated:** 15 September 2026  
**Scope:** purchase/listing context, condition on arrival, evidence-backed seller assessment, and fair eBay-review wording.

This document deliberately separates **observed facts**, **technical interpretation**, and **consumer-review opinion**. It does not convert a troubleshooting hypothesis into an accusation against the seller.

## Purchase and listing context

The purchased machine was described as a used/refurbished **HP ProBook 11 G2** with:

- 11.6-inch display;
- Intel Core i3-6100U at 2.3 GHz;
- 4 GB DDR4 RAM;
- Intel HD Graphics 520;
- 128 GB SSD;
- webcam, Wi-Fi N, HDMI, card reader and 3 x USB 3.0;
- AC adaptor/cable;
- battery tested working;
- Windows 11 Pro installed by the seller; and
- a 3-month seller warranty.

The purchase was approximately **AU$89 delivered**. Earlier fleet-value research rated that purchase price as very good for the hardware class, while also preferring an 8 GB configuration for practical use.

The laptop was received on **Friday 11 September 2026**.

## What happened immediately after arrival

The machine suffered genuine whole-system hard hangs shortly after purchase. The display remained lit/frozen, there was no useful BSOD, and recovery required holding the power button.

Two current-machine September incidents were investigated in detail. The second occurred on **12 September 2026 at about 2:14 pm**, while the machine was effectively idle/at the lock screen. The supplied power/event evidence later showed a strong association between the current incidents and low-level S4/Fast Startup-style power-state transitions.

That is significant for an eBay assessment because a normal buyer should not have to carry out firmware, event-log, SetupAPI, BitLocker, storage, sensor and power-state analysis just to establish whether a freshly supplied refurbished laptop is stable.

## Hardware evidence: what passed

The investigation does **not** support saying that the seller supplied a proven bad SSD or obviously failed RAM.

Established reassuring findings include:

- HP UEFI Memory Quick Check: **passed**;
- SSD SMART check: **passed**;
- SSD Short DST: **passed**;
- Windows storage reliability counters did not show convincing current read-error evidence;
- a later HWiNFO capture materially weakened overheating as the explanation for the captured interval;
- no convincing incident-time WHEA, SATA/AHCI timeout storm, graphics TDR, BSOD or classic storage-failure sequence was found around the second freeze.

The machine therefore remains potentially useful hardware at a very low purchase price.

## Proven software/refurbishment concerns

The strongest criticism of the supplied machine is not “dead hardware”; it is **software/firmware preparation**.

The investigation established that:

1. The physical BIOS was **HP N92 01.04 dated 2 November 2016**.
2. Windows had recorded an **HP N92 System Firmware 01.60** device in a failed-start / Code 10 state during the investigation.
3. The delivered Windows installation had been **Sysprep-respecialised** onto this ProBook immediately before sale.
4. It retained substantial previous-hardware/non-present-device state, including evidence from other HP hardware and prior storage devices.
5. The image contained old/mismatched OEM driver history and Windows servicing problems.
6. The supplied operating system was **Windows 11 Pro 24H2** on a 6th-generation Intel platform that is outside Microsoft's normal supported Windows 11 CPU baseline.
7. The machine had only **4 GB RAM**, with independently observed severe memory pressure. That is a real performance limitation even though it does not by itself explain the hard locks.

The evidence therefore supports describing the supplied OS as a **reused/generalised refurb image that was not a clean diagnostic baseline**. It does not prove the seller knowingly intended to mislead anyone.

## Current technical assessment

The current best-supported problem family is:

> **firmware / power-state / unsupported-platform interaction on a reused refurb Windows image, with severe 4 GB memory pressure acting as a likely stall amplifier**

This is still a hypothesis family rather than a confirmed single root cause.

The hardware has **not** been proven defective. Likewise, the fact that a reused/generalised image was supplied does not by itself prove that the seller knew it would freeze.

## Fair consumer assessment

A balanced assessment is approximately **3/5 for the item as initially supplied**, or neutral-to-cautiously-positive seller feedback depending on how the seller responds under the advertised 3-month warranty.

### Positive factors

- Very low purchase price: about AU$89 delivered.
- Core hardware diagnostics passed.
- SSD evidence is substantially more reassuring than alarming.
- Battery and charger were supplied as expected.
- The listing included a 3-month warranty.
- The machine may still become a useful small laptop after proper firmware/software remediation and a RAM upgrade.

### Negative factors

- Two genuine hard freezes occurred almost immediately after purchase.
- The supplied Windows installation was not a clean refurb baseline.
- The physical BIOS was extremely old.
- Windows had a failed firmware-device state during investigation.
- Windows 11 was supplied on unsupported-generation hardware.
- 4 GB RAM is inadequate for a comfortable Windows 11 experience.
- Considerable expert-level troubleshooting was required immediately after delivery.

## Recommended honest eBay review

> The laptop was very inexpensive and the basic hardware appears to be in reasonable condition, but unfortunately it wasn't really ready to use as supplied.
>
> Within the first day it suffered two complete system freezes requiring a forced shutdown. Hardware diagnostics have since passed the RAM and SSD, so I can't say the hardware itself is faulty.
>
> However, further investigation showed the supplied Windows 11 installation appears to have been a reused/generalised refurb image containing drivers and hardware history from other HP computers. The laptop was also running a very old 2016 BIOS and had a failed HP firmware device showing in Windows. Windows 11 is installed despite this 6th-gen Intel model not being officially supported.
>
> For the price it may still turn out to be good value, and the listing did include a 3-month warranty, but I expected a refurbished computer to arrive with a clean, stable installation rather than require substantial troubleshooting immediately.
>
> Overall: good price and seemingly sound basic hardware, but the software/firmware preparation before sale could have been considerably better.

## Claims the evidence does **not** currently justify

Avoid presenting any of the following as established fact:

- “the laptop has a bad SSD”;
- “the RAM is faulty”;
- “the motherboard is definitely faulty”;
- “the seller knowingly sold a defective laptop”;
- “the seller deliberately cloned Windows to deceive buyers”;
- “Windows 11 itself is definitely the root cause”;
- “the failed firmware capsule/device definitely caused the freezes”; or
- “the laptop is unusable”.

Those claims go beyond the evidence currently available.

## Warranty / return threshold

The investigation plan remains:

1. preserve evidence;
2. continue controlled testing with hibernation/Fast Startup removed as a variable;
3. make crash-dump capture trustworthy;
4. inspect the XTU/OEM state without stacking unrelated changes;
5. update the BIOS through HP's official N92 method when BitLocker/recovery/power safety is assured;
6. test memory properly if instability persists;
7. isolate the supplied Windows image with a clean OS/live environment where practical; and
8. if low-level hard freezes survive firmware, known-good memory and clean-OS isolation, use the **3-month warranty/return path** rather than endlessly tweaking the supplied image.

## Privacy boundary

This is a public repository. The following must remain private/redacted:

- BitLocker recovery passwords;
- raw EVTX/ETL/dump material containing account or machine-identifying data unless deliberately reviewed and redacted;
- private account details;
- credentials/tokens;
- unnecessary hardware identifiers such as serial numbers.

See `SECURITY_NOTICE.md` and `evidence/README.md` before publishing diagnostic artefacts.

## Related case records

- `analysis/STATUS.md` — current operational source of truth.
- `analysis/MASTER_ANALYSIS.md` — detailed technical reasoning.
- `analysis/FORENSIC_UPDATE_2026-09-12.md` — later sensor/power correlation.
- `analysis/TEST_PLAN.md` — controlled diagnostic sequence.
- `conversation/CONSOLIDATED_CASE_HISTORY_2026-09-15.md` — cross-chat safe history.
