# Raw evidence

This directory is for original diagnostic evidence and integrity records.

Currently committed directly:

- `battery-report.html.gz`

## Complete archives built in the ChatGPT working sandbox

A lossless `tar.gz` archive containing every mounted user evidence file from the troubleshooting conversation was created as:

`hprobook-evidence-all.tar.gz`

SHA-256:

`f9c98db4983be8b8ff7b95a7a1e7251e44af2dde01a2fb9b12997fb835124aa8`

A Windows-friendly ZIP containing the same mounted evidence set was also created as:

`hprobook-evidence-all.zip`

SHA-256:

`2d78d3166c4be0b1dccf8f5b0aa13e0961dd41eec04f15c591d3488e23bc374d`

The archives contain the EVTX originals and their duplicate uploads, all mounted screenshots, `1111.txt` copies, `setupapi.dev.log`, battery/system-power reports, the supplied Claude PDF and the redacted ChatGPT conversation export.

## Why the large raw archive is not committed directly

The GitHub connector available in this session does not accept a local sandbox file as an upload parameter. Routing tens of megabytes of binary EVTX/image/archive data through model text risks truncation or corruption, so the investigation deliberately does **not** claim those raw binaries are in Git when they are not.

The original conversation files are likewise referenced by exact size/SHA-256 in `evidence/manifests/evidence-manifest.csv`; `conversation/README.md` explains their archive status.

**Security:** raw evidence includes hardware identifiers and this repository is public. The BitLocker recovery password exposed during troubleshooting is intentionally redacted/excluded and should be rotated.
