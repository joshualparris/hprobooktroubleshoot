# HP ProBook 11 G2 — consolidated cross-chat case history

**Consolidated:** 15 September 2026  
**Purpose:** preserve the safe, decision-relevant history of the HP ProBook 11 G2 purchase and troubleshooting across related chats without publishing secrets or unreviewed raw logs.

## Provenance rule

This file is a synthesis, not a verbatim chat archive. Where earlier conversation text was compacted or reconstructed, the repository should preserve that distinction. Technical claims are carried forward only when supported by the existing case evidence or repeated source records.

## Purchase

- Model: **HP ProBook 11 G2**.
- CPU: **Intel Core i3-6100U**, 2 cores / 4 threads, 2.30 GHz.
- Graphics: Intel HD Graphics 520.
- Memory: **4 GB DDR4-2133**, single-channel.
- Storage: **Samsung 128 GB SATA SSD**.
- Screen: 11.6 inch.
- Seller-supplied OS: Windows 11 Pro.
- Seller listing also included AC adaptor/cable, working battery and a **3-month warranty**.
- Approximate purchase price: **AU$89 delivered**.
- Received: **Friday 11 September 2026**.

Earlier fleet-value research considered that price very good for the hardware, but also identified **8 GB RAM** as the preferred configuration for practical use.

## Initial symptom

Soon after arrival the laptop produced genuine whole-system hard freezes. One early incident occurred after Ctrl+Alt+Delete. The display remained frozen/lit and the machine had to be powered off forcibly.

A second current-machine freeze occurred on **12 September 2026 at about 2:14 pm**, around the lock screen / effectively idle state.

## Initial hardware checks

HP UEFI diagnostics were run from Esc -> F2.

Results:

- Memory Quick Check: **PASS**.
- SSD SMART: **PASS**.
- SSD Short DST: **PASS**.

Task Manager around the early investigation showed low CPU/disk/GPU activity but already significant RAM use on a 4 GB system. Later telemetry independently confirmed severe memory pressure.

These results reduce the likelihood of a simple, obvious RAM or SSD failure. They do not eliminate intermittent hardware faults.

## Event-log and power-state findings

The two September freezes were not well explained by classic crash signatures. Around the second incident there was no convincing WHEA sequence, storage reset storm, graphics TDR, BugCheck/BSOD or clear drive-failure signature.

Power/event evidence instead showed that the current incidents clustered shortly after **S4 / hybrid-shutdown / Fast Startup-style resume behaviour**.

`powercfg /h off` was therefore used as a controlled A/B change to disable hibernation and Fast Startup rather than stacking many changes at once.

Kernel-Power 41 / EventLog 6008 records were treated as evidence of an unclean shutdown aftermath, not as proof of root cause.

## Reused Windows-image finding

The supplied Windows installation is not a clean original install for this hardware.

SetupAPI and Windows history showed:

- Sysprep Respecialize immediately before sale;
- substantial retained non-present-device history;
- previous HP hardware identities and older storage-device history;
- Macrium imaging history;
- old/mismatched HP/OEM driver state; and
- servicing/component-store errors.

This proves the machine was supplied with a **generalised/reused refurb Windows image** rather than a pristine per-device install.

It does **not** prove malicious intent by the seller.

## BIOS and firmware

Current physical BIOS during the investigation:

- **N92 Ver. 01.04**
- dated **2 November 2016**.

Windows also recorded an **HP N92 System Firmware 01.60** firmware-class device in a **Code 10 / failed-start** state during the investigation.

That mismatch is a real low-level abnormality, but the repository deliberately does not claim that it single-handedly caused the freezes.

## Windows 11 compatibility

The supplied system runs **Windows 11 Pro 24H2** on a 6th-generation Intel Core i3-6100U platform. This generation falls outside Microsoft's normal supported Windows 11 Intel CPU baseline.

That unsupported configuration is a compatibility risk factor, particularly in combination with old HP firmware and OEM drivers. It is not by itself proof of the hard-freeze mechanism.

## Memory pressure

The 4 GB configuration is a proven performance constraint.

Evidence included:

- only roughly 330 MB available in one MSINFO32 capture;
- later HWiNFO logging showing RAM commonly around 80–86%; and
- peak pressure above 92%, with roughly 311 MB free at the low point.

This can explain sluggishness, paging and stalls. It still does not cleanly explain a complete whole-system hard lock by itself.

## Storage and temperature evidence

Current evidence remains comparatively reassuring:

- HP SSD SMART and Short DST passed;
- Windows storage reliability counters showed no convincing current read errors;
- HWiNFO drive warning/failure indicators remained clear during the captured interval;
- HWiNFO temperature data materially weakened an overheating theory for that interval; and
- no strong incident-time storage-failure signature has been established.

## Current working model

The best-supported problem family remains:

> **firmware / power-state / unsupported-platform interaction on a reused refurb Windows image, with severe 4 GB memory pressure acting as a likely stall amplifier**

This remains a ranked technical model, **not a confirmed single root cause**.

## Controlled next steps

The investigation sequence is intentionally one-variable-at-a-time:

1. preserve evidence and capture current post-change state;
2. measure stability with hibernation/Fast Startup disabled;
3. make pagefile/crash-dump capture trustworthy;
4. inspect Intel XTU state without changing values;
5. run stronger memory testing if instability persists;
6. update the physical HP N92 BIOS using HP's official route once recovery-key and power safety are assured;
7. repeat representative-use telemetry;
8. isolate the seller-supplied Windows image with a clean/live OS where practical; and
9. if freezes persist after firmware, known-good memory and clean-OS isolation, use the seller's **3-month warranty/return path**.

## Consumer / eBay review conclusion

The fairest current consumer assessment is:

- **good purchase price**;
- **basic hardware not proven faulty**;
- **poor software/firmware preparation before sale**;
- **not genuinely ready-to-use as supplied**, given two immediate hard freezes and the amount of troubleshooting required.

A roughly **3/5 item assessment** is defensible at this stage, with seller feedback depending partly on how the seller responds under the advertised warranty.

The full evidence-aware review wording lives at:

- `docs/PURCHASE_SELLER_AND_EBAY_REVIEW.md`

## Related but not automatically merged into this physical-device case

Other chats have involved ProBook-family machines, DNS/Tailscale problems, browser certificate issues, Windows lab use, and broader HP laptop troubleshooting. Those records should only be attached to this specific HP ProBook 11 G2 case when machine identity is positively established. Similar symptoms or the word “ProBook” alone are not enough to merge histories.

This avoids contaminating the current-machine timeline with evidence from another laptop.

## Privacy exclusions

The public repository must not contain:

- the BitLocker recovery password previously exposed in chat;
- replacement recovery keys;
- credentials/tokens;
- private account details;
- unreviewed raw dumps/logs containing identifying data; or
- unnecessary serial numbers and other unique hardware identifiers.

The prior conversation export intentionally redacted the BitLocker recovery password. Keep it that way.
