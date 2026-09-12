# Raw evidence and archive boundary

This directory documents original diagnostic evidence and the integrity boundary between what is actually committed to Git and what existed only in the troubleshooting workspace.

## Directly committed raw item

- `battery-report.html.gz`

No other large raw archive should be assumed to exist in Git merely because its filename is documented here.

## Complete archives created in the troubleshooting workspace

A lossless tar archive was created as:

`hprobook-evidence-all.tar.gz`

SHA-256:

`f9c98db4983be8b8ff7b95a7a1e7251e44af2dde01a2fb9b12997fb835124aa8`

A Windows-friendly ZIP of the same mounted evidence set was created as:

`hprobook-evidence-all.zip`

SHA-256:

`2d78d3166c4be0b1dccf8f5b0aa13e0961dd41eec04f15c591d3488e23bc374d`

These hashes are integrity records for those workspace artefacts. They do **not** claim that the archives are currently retrievable from this Git repository.

The archives covered the mounted EVTX files (including duplicate uploads), screenshots, text files, SetupAPI log, battery/system-power reports, supplied Claude PDF and redacted ChatGPT conversation export.

## Why the large archive is not committed

Routing tens of megabytes of binary evidence through a text-only connector risks truncation/corruption. The investigation therefore preserves truthful boundaries rather than claiming a binary upload succeeded when it did not.

The committed manifest at `../evidence/manifests/evidence-manifest.csv` records filename/size/SHA-256 information for the evidence set available to that session.

## If the archive is re-materialised later

Before trusting it:
1. calculate SHA-256;
2. compare it with the recorded hash above;
3. store it privately;
4. do not add it to public Git without a deliberate security review;
5. generate reviewed extracts instead of publishing the whole archive where possible.

## Crash Doctor relationship

Future Crash Doctor dump, ETW, ProcMon and WER artefacts should follow the same rule: preserve private originals, manifest them, and publish only what is necessary.

See [`../evidence/README.md`](../evidence/README.md) and [`../SECURITY_NOTICE.md`](../SECURITY_NOTICE.md).
