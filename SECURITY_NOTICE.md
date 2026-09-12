# Security and privacy notice

This is a **public troubleshooting repository**. Diagnostic evidence can contain secrets, personal data and fragments of process memory even when the filename looks harmless.

## Default policy

- Raw diagnostic evidence is **private by default**.
- Analysis should happen locally unless the user explicitly chooses another destination.
- Upload/export is opt-in.
- High-risk system changes are never implied by permission to collect/analyse evidence.
- Redaction is a separate step; do not modify the only copy of an original artefact.

## Never commit

- BitLocker recovery passwords or recovery-key exports;
- passwords, API keys, access tokens, cookies or session material;
- Wi-Fi keys or exported WLAN profiles containing key material;
- private keys or certificates containing private material;
- credential-manager exports;
- memory dumps that have not been reviewed for sensitive process memory;
- full email addresses, phone numbers, home addresses or unnecessary personal data;
- unreviewed browser histories, chat exports or screenshots.

The BitLocker recovery password exposed during this investigation must stay out of Git history and should be rotated/replaced outside this repository.

## Treat these artefacts as sensitive

At minimum:
- `.dmp`, `.mdmp` and full/kernel memory dumps;
- `.etl` ETW traces;
- `.evtx` event logs;
- WER `.wer` reports and associated archives;
- `msinfo32` exports;
- SetupAPI logs;
- battery/sleep/system-power reports;
- ProcMon traces;
- HWiNFO CSVs;
- screenshots;
- conversation exports;
- Crash Doctor support bundles.

Memory dumps are especially sensitive because they can contain application data or secrets that were resident in memory.

## Evidence handling workflow

Before publishing an artefact:

1. Keep an untouched private original.
2. Record its SHA-256.
3. Record when/where/how it was captured.
4. Classify its sensitivity.
5. Generate a derivative for analysis/export.
6. Remove secrets and unnecessary identifiers from the derivative.
7. Hash the derivative separately.
8. Record the redactions and provenance link.
9. Review the final file manually before committing/uploading.

## Windows Crash Doctor requirements

Current and future Crash Doctor features must:
- process locally by default;
- clearly state when administrator rights are required;
- use least privilege where practical;
- distinguish reading evidence from changing system configuration;
- require explicit approval before enabling dump policies, remote access, Driver Verifier or similar mutation;
- never upload dumps/traces silently;
- make retention and purge behaviour visible;
- enforce permissions-aware access to other users' crash artefacts;
- provide a preview of files/fields before support or bug-tracker export.

## Automated guard

`scripts/check-public-evidence.ps1` scans committed text-like files for the eight-group numeric pattern used by BitLocker 48-digit recovery passwords. GitHub Actions runs the guard on pushes/pull requests.

This is a **narrow safety net**, not a complete secret scanner. It will not reliably detect every password, token, memory-resident secret, private identifier or sensitive log field.

Future roadmap work expands redaction/export safety; see [`docs/ROADMAP_100.md`](docs/ROADMAP_100.md).

## Git permanence

Deleting a secret in a later commit does not remove it from prior Git history. If a secret is committed:
1. rotate/revoke it first;
2. assess whether history rewrite is needed;
3. do not rely on a normal delete commit as remediation.

## Repository convention

`evidence/raw/` is intentionally ignored. Public Git should contain tooling, analysis, manifests and intentionally reviewed extracts — not an automatic mirror of everything collected from a machine.
