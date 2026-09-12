# Raw evidence status

The troubleshooting working session inventoried and hashed the user-supplied evidence available to that session. The resulting filename/size/SHA-256 inventory is committed at `evidence/manifests/evidence-manifest.csv`, including duplicate groups.

## What the manifest proves

The committed hashes make the evidence inventory auditable even though the large binary originals are not stored in this public repository. Matching SHA-256 values identify byte-identical duplicate uploads.

A hash proves byte identity for the file that was hashed; it does **not** prove that every historical event inside a reused Windows image belongs to the current physical ProBook.

## Complete archives outside Git

The working session recorded two complete archives of the mounted evidence set:

- `hprobook-evidence-all.tar.gz` — SHA-256 `f9c98db4983be8b8ff7b95a7a1e7251e44af2dde01a2fb9b12997fb835124aa8`
- `hprobook-evidence-all.zip` — SHA-256 `2d78d3166c4be0b1dccf8f5b0aa13e0961dd41eec04f15c591d3488e23bc374d`

Those archives are **not part of this Git repository**. Treat the hashes as integrity records for the working-session artefacts unless the archives are later independently re-materialised and verified.

## What the public repository contains

- analytical conclusions and corrections under `analysis/`;
- `evidence/manifests/evidence-manifest.csv` with the supplied-file inventory and duplicate hashes;
- `raw/battery-report.html.gz` as a small directly committed raw-report sample;
- `conversation/README.md` and `raw/README.md` documenting archive status;
- a current investigation status dashboard;
- one consolidated repeatable diagnostic collector plus an evidence-hashing script;
- evidence-handling and public-repository security/redaction guidance.

The large EVTX/image/raw-evidence set is intentionally not claimed as committed. Review `SECURITY_NOTICE.md`, `evidence/README.md` and `raw/README.md` before publishing diagnostic artefacts.

**Do not publish the BitLocker recovery password exposed in the original troubleshooting chat.**
