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

## Future incident-store model

The 100-item roadmap adds dumps, WER, ETW, trigger captures and a persistent incident catalogue. Those sources should enter the same provenance model rather than inventing parallel evidence stores.

See:
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
