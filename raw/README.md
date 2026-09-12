# Raw evidence

This directory is for the original diagnostic evidence.

Currently committed directly:

- `battery-report.html.gz`

The original ChatGPT transcript is committed at `conversation/chatgpt-conversation-2026-09-12.md` with the exposed BitLocker recovery password redacted. The original Claude PDF supplied by the user is committed at `conversation/claude-conversation-2026-09-12.pdf`.

## Complete archive

A lossless `tar.gz` archive containing every mounted user evidence file from the troubleshooting conversation was built in the ChatGPT working sandbox as:

`hprobook-evidence-all.tar.gz`

SHA-256:

`f9c98db4983be8b8ff7b95a7a1e7251e44af2dde01a2fb9b12997fb835124aa8`

It contains the EVTX originals and their duplicate uploads, all screenshots, `1111.txt` copies, `setupapi.dev.log`, battery/system-power reports, the Claude PDF and the redacted ChatGPT conversation export.

The current GitHub connector does not accept a local binary-file parameter, so the multi-megabyte archive/EVTX set could not be streamed into GitHub without routing binary bytes through the language-model context. The SHA-256 manifest in `evidence/manifests/evidence-manifest.csv` provides an integrity record for every original file.

**Security:** raw evidence includes hardware identifiers and the repository is public. The exposed BitLocker recovery password is intentionally not included.
