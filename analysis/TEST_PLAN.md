# Controlled HP ProBook test plan

Principle: change **one major variable at a time**, define success/failure before the change, and preserve evidence after every stage.

## Before every stage

1. Note the date/time and intended variable.
2. Run a baseline collector snapshot if the previous one is stale:

```powershell
.\scripts\collect-diagnostics.ps1
```

3. Preserve any HWiNFO log or other live telemetry.
4. Do not delete the previous evidence folder.
5. After the stage, run another collector and compare.

Crash Doctor can summarise each snapshot:

```powershell
.\windows-crash-doctor\Invoke-CrashDoctor.ps1 `
  -EvidencePath "<collector-folder>"
```

## Stage 0 — thermal/power baseline

### HWiNFO baseline

Keep the laptop awake and avoid unrelated changes while logging:
- CPU/core temperatures;
- effective clocks;
- throttling flags;
- GPU activity/temperature where available;
- SSD temperature;
- memory load;
- battery voltage/current/power;
- power-limit flags.

Interpretation:
- freeze during logging → preserve the CSV and exact last row/timestamp;
- 30 minutes stable → useful but weak;
- 2+ hours normal use → stronger;
- 24+ hours representative use → much stronger.

## Stage 1 — confirm current post-change state

Collect and specifically verify:

```powershell
pnputil /enum-devices /problem
Get-PnpDevice -Class Firmware | Format-List FriendlyName,Status,InstanceId
powercfg /a
manage-bde -status C:
```

Questions:
- Is the previously abnormal N92 firmware device gone?
- Does the current firmware resource report OK?
- Is hibernation/Fast Startup still disabled?
- What is BitLocker conversion/protection state?

Do not infer that an OK firmware device alone proves the hang is fixed.

## Stage 2 — inspect XTU without changing values

Record:
- whether Intel XTU launches;
- core/cache voltage offset if exposed;
- active profile;
- any startup/automatic profile;
- service/driver state.

Do not apply new tuning. If a non-default undervolt/overclock exists, preserve evidence before a later isolated reset/removal test.

## Stage 3 — make crash capture trustworthy

Before using any manual crash trigger:
- use a system-managed or otherwise adequate pagefile;
- configure kernel/automatic dump appropriately;
- confirm enough free disk space;
- record the configuration in a collector snapshot.

A fully wedged machine may still fail to generate a dump; fixing capture configuration makes that absence more meaningful but never guarantees a dump from a hard lock.

## Stage 4 — RAM isolation

Run MemTest86 from USB, preferably multiple passes/overnight.

Any memory error is significant. If practical:
- reseat the module;
- repeat;
- test with known-good compatible RAM.

Record tool version, pass count and result.

## Stage 5 — BIOS/firmware

Only after evidence is preserved and BitLocker recovery safety is confirmed:
- use HP's official N92 BIOS path rather than relying on the failed Windows firmware-capsule route;
- use reliable AC power;
- record current BIOS settings first;
- confirm physical BIOS version after the update;
- avoid combining the BIOS update with unrelated driver/software changes.

Run a fresh collector immediately after the update and before further modifications.

## Stage 6 — clean OS isolation

If instability remains:
- clean-install a known-good test OS or use an appropriate live environment;
- do not import the seller/refurb driver image;
- test cold boot, idle, load and supported sleep/resume states;
- keep the physical firmware/hardware constant.

If updated firmware + clean OS + known-good RAM still hard-freeze, the remaining probability shifts strongly toward motherboard/platform hardware and the practical next step is return/warranty.

## What counts as a failed stage

A stage fails if the original hard-freeze symptom recurs under the stage's conditions. Do not immediately begin another fix. First preserve:
- time;
- uptime;
- last task;
- power/resume state;
- current evidence;
- post-reboot snapshot.

## Future Crash Doctor support

The product roadmap includes proactive dumps, WER ingestion, ETW circular traces and an incident catalogue so several of these manual steps can eventually be captured automatically. Those planned capabilities are listed in [`../docs/ROADMAP_100.md`](../docs/ROADMAP_100.md); they should not be assumed available today.
