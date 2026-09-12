# Evidence workflow

This repository separates **analysis** from **evidence** so conclusions can be checked later.

## Recommended layout

```text
evidence/
  README.md
  manifests/
    evidence-manifest.csv
  extracts/
    <small reviewed text extracts>
  raw/
    <private/unreviewed original files — gitignored>
```

`evidence/raw/` is intentionally ignored. Diagnostic files often contain usernames, serial numbers, network details, recovery material and other private information.

## Hash originals before editing

From PowerShell:

```powershell
.\scripts\hash-evidence.ps1 -InputPath .\evidence\raw -OutputCsv .\evidence\manifests\evidence-manifest.csv
```

The manifest records relative path, byte size, modified time, SHA-256 and duplicate-content groups. Hashes let us prove that a later extract or redacted derivative came from a particular original without publishing the original itself.

## Evidence quality labels

When adding a claim to `analysis/`, identify its source quality where useful:

- **Direct observation** — user saw the behaviour or captured it live.
- **Current-machine telemetry** — output clearly tied to the present ProBook hardware/session.
- **Inherited-image history** — event/device history that may belong to previous hardware.
- **Derived inference** — interpretation that combines observations; not directly logged.
- **External transcript** — a claim reported by another analysis session but not independently re-captured here.

This matters because the reused Windows image contains historical hardware and events that should not automatically be attributed to the current ProBook.

## Publishing checklist

Before moving anything out of `raw/`:

1. Verify the timestamp and which machine/session it belongs to.
2. Hash the untouched source.
3. Redact secrets and unnecessary personal data.
4. Keep enough surrounding context to avoid misleading excerpts.
5. Record the source filename and hash in the extract or analysis note.
6. Re-read `../SECURITY_NOTICE.md` before committing.
