# Controlled test plan

Principle: change **one major variable at a time** and preserve evidence after each stage.

## Stage 0 — in progress

### HWiNFO 30-minute baseline
- Keep the laptop awake.
- Do not change BIOS, XTU, drivers or power settings during the run.
- Log CPU/core temperatures, effective clocks, throttling, GPU, SSD temperature, memory load, battery voltage/current/power and power-limit flags.
- Preserve the CSV even if the machine freezes.

Interpretation:
- freeze during the run → inspect last recorded rows and timestamp against event log;
- 30 min stable → encouraging but not conclusive, because historical sessions have survived longer;
- >2 h normal use after the current changes is much stronger evidence.

## Stage 1 — confirm current post-change state

After HWiNFO baseline:

```powershell
pnputil /enum-devices /problem
Get-PnpDevice -Class Firmware | Format-List FriendlyName,Status,InstanceId
powercfg /a
manage-bde -status C:
```

Record whether `oem28.inf` is truly gone and whether Firmware status is OK.

## Stage 2 — inspect XTU without changing values

Record:
- whether Intel XTU launches;
- core voltage offset / cache voltage offset if exposed;
- active tuning profile;
- any automatic startup profile.

Do not apply new values. If a non-zero undervolt/overclock is present, preserve a screenshot/export before reset/removal.

## Stage 3 — make crash capture trustworthy

Before using CrashOnCtrlScroll:
- ensure pagefile is System Managed on C: and large enough;
- verify dump type is kernel or automatic memory dump;
- confirm sufficient free disk space.

Only then enable manual crash generation if needed. A fully wedged machine may still fail to respond to the keyboard crash sequence.

## Stage 4 — RAM isolation

Run MemTest86 from USB, preferably multiple passes / overnight. Any error is significant. With one socketed 4 GB module, reseat/swap is straightforward if errors occur.

## Stage 5 — BIOS

Once BitLocker safety is resolved and evidence is preserved:
- update directly using HP's official N92 BIOS updater rather than relying on the failed Windows firmware capsule path;
- confirm physical BIOS version after update;
- restore BIOS defaults / NVRAM only in a controlled way and record settings first.

## Stage 6 — clean OS isolation

If instability remains:
- clean-install a known-good supported/test OS or use a live Linux environment without installing;
- do not import the seller/refurb driver image;
- test cold boot, idle, load and S3 transitions.

If updated firmware + clean OS + known-good RAM still hard-freeze, stop spending time and use the warranty/return path.
