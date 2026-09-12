# Evidence workflow

This repository separates **evidence**, **analysis**, **case history** and **product code** so later conclusions can be audited.

## Directory model

```text
evidence/
  README.md
  manifests/
    evidence-manifest.csv
  extracts/
    <small reviewed/redacted derivatives>
  raw/
    <private/unreviewed originals — gitignored>
```

`evidence/raw/` is intentionally ignored. Diagnostic artefacts can contain usernames, serial numbers, network details, recovery material, application content and process memory.

## Chain of custody

For every important raw artefact, aim to preserve:

- original filename;
- byte size;
- SHA-256;
- capture time;
- machine/session/boot identity where known;
- tool/command that created it;
- whether it is original, derived or redacted;
- sensitivity classification;
- relationship to an incident.

From PowerShell:

```powershell
.\scripts\hash-evidence.ps1 `
  -InputPath .\evidence\raw `
  -OutputCsv .\evidence\manifests\evidence-manifest.csv
```

The manifest supports duplicate detection and lets a reviewed derivative be linked back to an untouched original without publishing the original bytes.

## Evidence quality labels

Use these labels in analysis when useful:

- **Direct observation** — a person observed the behaviour as it happened.
- **Current-machine telemetry** — evidence clearly tied to the current hardware/session.
- **Inherited-image history** — information that may belong to hardware previously associated with the Windows image.
- **Derived inference** — a conclusion produced by combining observations.
- **External transcript** — reported by another analysis session but not independently re-captured.
- **Planned/expected** — a design or hypothesis, not observed evidence.

The distinction is essential on a reused Windows installation.

## Crash Doctor outputs are derived evidence

`crash-doctor-report.md` and `crash-doctor-report.json` are **derived analysis artefacts**. They are reproducible from the named input folder and should not replace the originals.

If a finding matters:

1. preserve the original collector folder;
2. record its hash/manifest where practical;
3. retain the report that was produced from it;
4. do not edit the source evidence to make the report cleaner.

The current desktop workflow also calculates an evidence-bundle SHA-256 fingerprint and persists run/finding provenance in the local SQLite diagnostic run ledger. Those records improve comparison/auditability but still do not replace the source evidence itself.

## Shareable export

The current desktop app includes a privacy-reviewed shareable-export path. It plans the bundle before writing the ZIP, excludes high-risk/unscannable artefacts by default, redacts supported sensitive text patterns in derivatives and writes `export-manifest.json`. Original evidence remains unchanged.

This is a conservative safety layer, not proof that an export is free of every possible secret or personal identifier. A human review is still appropriate before external publication.

## Current run ledger versus future incident store

Windows Crash Doctor now has a local SQLite **diagnostic run ledger** containing runs, findings, collector outcomes and run comparisons. This supports durable history and before/after analysis.

The larger roadmap still calls for a broader **crash/incident catalogue** covering always-on detection, WER/ETW/trigger captures, lifecycle state, deduplication, retention and richer incident relationships. Do not describe that broader incident-store architecture as complete merely because the diagnostic run ledger exists.

See:

- [`../docs/RELEASE_VERIFICATION.md`](../docs/RELEASE_VERIFICATION.md)
- [`../docs/WINDOWS_CRASH_DOCTOR_PLAN.md`](../docs/WINDOWS_CRASH_DOCTOR_PLAN.md)
- [`../docs/ROADMAP_100.md`](../docs/ROADMAP_100.md)

## Publishing checklist

Before moving anything from private storage into public Git:

1. Verify which machine/session/boot it belongs to.
2. Hash the untouched source.
3. Review for secrets and personal data.
4. Redact a derivative rather than editing the only original.
5. Keep enough surrounding context to prevent misleading excerpts.
6. Record the source filename/hash and redaction notes.
7. Re-read [`../SECURITY_NOTICE.md`](../SECURITY_NOTICE.md).
8. Confirm the file is actually required for public reproducibility.