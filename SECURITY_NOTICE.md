# Security and privacy notice

This is a **public troubleshooting repository**. Diagnostic evidence can contain secrets or identifying information even when the file looks harmless.

## Never commit

- BitLocker recovery passwords or recovery-key exports
- passwords, API keys, browser/session tokens or authentication cookies
- Wi-Fi passwords or exported WLAN profiles containing key material
- private keys, certificates with private material, or credential-manager exports
- full email addresses, phone numbers, home addresses or other personal data unless intentionally redacted
- serial numbers, asset tags or device IDs when they are not required for the diagnosis
- unreviewed browser histories, chat exports or screenshots

The BitLocker recovery password exposed during this investigation must stay out of Git history and should be rotated/replaced outside this repository.

## Treat raw logs as sensitive

EVTX files, `msinfo32` exports, SetupAPI logs, sleep reports, crash dumps and screenshots can contain usernames, machine names, paths, device identifiers, network details and fragments of other private data.

Windows Crash Doctor runtime data under `%ProgramData%\WindowsCrashDoctor` must also be treated as sensitive. Canary JSONL, incident bundles, reports and the ledger can contain process names, device identifiers, event messages and machine metadata. The app writes this data locally; it does not upload it automatically.

Before publishing raw evidence:

1. Keep an untouched private original.
2. Hash it so later redaction can be traced to the original.
3. Review the file for secrets and personal data.
4. Publish a redacted derivative when possible.
5. Record the original hash, redacted-file hash and redaction notes in the evidence manifest.

## Git is permanent enough to matter

Deleting a secret in a later commit does not remove it from prior Git history. If a secret is committed, rotate/revoke it first, then rewrite repository history if required.

## Repository convention

`evidence/raw/` is intentionally ignored by default. Raw evidence should be stored privately unless there is a deliberate decision to publish a reviewed copy.

`dist/` is generated packaging output and is ignored in source control. Release ZIPs should be produced by the Windows CI workflow or `scripts/package-windows-crash-doctor.ps1`, then verified by SHA-256.
