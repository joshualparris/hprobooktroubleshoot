# Windows Crash Doctor release verification

This document is the release-verification source of truth for Windows Crash Doctor. It separates **implemented in source**, **verified by tests**, **packaged/release verified**, and **future hardening** so documentation does not treat those as interchangeable claims.

## Current version identity

The source tree currently identifies Windows Crash Doctor as:

- product: **0.3.0-preview.1**;
- engine: **0.3.0**;
- collector: **0.2.0**;
- rule set: **2026.09.12.2**;
- report schema: **2.0**;
- diagnostic registry: **2026.09.12.1**.

The collector version remaining at `0.2.0` is intentional and is not the product/engine version.

## Status vocabulary

- **Implemented** — the capability exists in the source tree and is integrated into the relevant code path.
- **Tested** — a focused repository/self-test exercises the capability.
- **Product-Gate verified** — the exact commit passed the full `Windows Crash Doctor Product Gate`, including the built `WindowsCrashDoctor.exe --self-test` path.
- **Published canary** — the already-verified release artifact was handed to the release job, hashes were rechecked, and the rolling canary release points to that same source commit.
- **Stable-release hardened** — future state requiring a deliberately versioned immutable release channel and additional supply-chain/productisation work such as Authenticode signing. A green canary is not the same claim.

## What a successful Product Gate proves

For one exact source commit, `.github/workflows/windows-crash-doctor-desktop.yml` requires the following before publication:

1. every PowerShell source parses under Windows PowerShell;
2. PSScriptAnalyzer reports no error-severity findings;
3. snapshot, telemetry and integration self-tests pass;
4. synthetic dump tests and the real Windows DbgHelp minidump smoke test pass;
5. the Pester integration suite passes;
6. the public-evidence guard passes;
7. the self-contained `win-x64` desktop executable builds with source-revision identity;
8. that **built executable** runs `--self-test`, extracts its embedded engine and proves the packaged engine path rather than only the repository checkout;
9. only after those checks pass, release assets are staged;
10. SHA-256 files are generated for the EXE, engine ZIP and installer/bootstrap assets;
11. `release-manifest.json` records source commit, product/engine/rule versions, verification stages, asset sizes and SHA-256 digests;
12. the exact verified artifact is uploaded as `WindowsCrashDoctor-verified-<commit>`;
13. the separate canary release job downloads that artifact, rechecks the hashes after handoff, and only then publishes it with `target_commitish` equal to the verified commit.

This means a successful Product Gate is stronger than “the tests passed” or “the EXE compiled”: it proves the repository tests and the packaged executable composed successfully for the same commit and that the published canary came from the verified artifact.

## What the Product Gate does not prove

Even when green, the current gate does not claim:

- Authenticode/code signing or a trusted Windows publisher identity;
- SmartScreen reputation;
- a full WPF UI automation/accessibility suite;
- exhaustive secret/PII detection for every possible evidence format;
- every future Windows/dump/provider combination;
- stable-channel immutability or long-term support guarantees;
- that every diagnostic registry entry is independently executed with its own subprocess timeout/retry record;
- that a diagnostic conclusion is causal rather than evidence-bounded.

Those are separate post-P0/stable-release improvements.

## Capability reconciliation

| Capability | Source status | Verification status / limitation |
|---|---|---|
| HWiNFO CSV telemetry | Implemented | Repository telemetry regression coverage exists. |
| LibreHardwareMonitor JSONL telemetry | Implemented | Uses the same telemetry finding path; missing provider-specific signals remain unknown rather than invented healthy evidence. |
| Embedded telemetry engine | Implemented | `TelemetryAnalysis.psm1`, registry and version files are embedded in the desktop EXE. Product-Gate verification requires the packaged EXE self-test to pass. |
| Privacy-reviewed shareable export | Implemented | Preview, default high-risk exclusions, redacted text derivatives, secret-pattern metadata and `export-manifest.json` are covered by the desktop self-test. The scanner is conservative, not exhaustive. |
| GUI/CLI installer SHA-256 verification | Implemented | Both installers verify downloaded release assets before activation/execution. The EXE remains unsigned. |
| SQLite run ledger | Implemented | `history.db` stores runs, findings, collector executions and comparisons, with legacy JSON migration. Current packaged self-test does not independently exercise every SQLite path. |
| Finding/evidence fingerprints | Implemented | SHA-256 fingerprints are attached to findings/evidence bundles and persisted. |
| Previous-run comparison | Implemented | NEW/RESOLVED/IMPROVED/WORSENED/UNCHANGED/UNKNOWN logic is integrated; basic comparison semantics are self-tested, while not every state has a dedicated fixture yet. |
| Preflight | Implemented | Runs before diagnosis and can block unavailable hard prerequisites; several optional checks degrade rather than abort. No separate full WPF preflight automation exists yet. |
| Diagnostic registry | Partially complete against the v2 roadmap | Canonical metadata/coverage/provenance registry exists and is shared by CLI/desktop. Collector command dispatch is not yet wholly generated from the registry. |
| Timeout/cancellation/retry runner | Partially complete against the v2 roadmap | Process runner has bounded timeout, cancellation, process-tree termination, retry classification/backoff and execution metadata. Per-diagnostic records for the monolithic collector are still partly inferred from evidence-file outcomes rather than each probe being an independently timed execution. |

## Current A3 verification snapshot

A3 branched from main commit `a7d811578dd9e4696bd759124e2424d0907ac56f` on 12 September 2026 while A1 telemetry/cardinality work was still advancing `main`.

The latest **completed** Product Gate independently reviewed before that branch was run `34683833695` for commit `a6afed717b8cf999d41d9ba946302d37cac0bff0`. Parser, PSScriptAnalyzer, core snapshot tests, dump tests, Pester/integrations, public-evidence guard and desktop compilation all passed, but the packaged EXE self-test failed inside embedded HWiNFO telemetry analysis. The release bundle/upload and canary publication were therefore skipped.

At that point the rolling canary still targeted older commit `b1f4b1f4b13eef4f55b83788a63cd4c956335ba4` and contained only the older EXE/checksum pair, not the current `0.3.0-preview.1` verified release-manifest contract.

**Therefore that older rolling canary must not be described as the current Product-Gate-verified v0.3 build.** After A1 obtains a green gate, A3 must update this section only after independently confirming the exact successful run, verified artifact, manifest/hash assets and canary target commit.

## Release acceptance checklist

A3 may call the current canary verified only when all of these are true for the same commit:

- [ ] latest intended `main` commit is identified;
- [ ] Product Gate conclusion is `success`;
- [ ] packaged EXE self-test step is `success`;
- [ ] verified release artifact `WindowsCrashDoctor-verified-<commit>` exists;
- [ ] release bundle contains `release-manifest.json`;
- [ ] required release assets have matching `.sha256` files;
- [ ] canary publication job succeeded;
- [ ] rolling canary `target_commitish` equals that verified commit;
- [ ] published canary includes the manifest and expected verified assets, not only a legacy EXE/checksum pair.

## P0/v2 versus post-P0 work

### P0 / v2 release-completion work

The immediate release-completion requirement is to make the packaged executable pass the Product Gate and prove the release handoff/published canary for the same commit. Documentation truthfulness is part of that completion work.

### Implemented v2 architecture that is no longer merely “planned”

SQLite run history, fingerprints, previous-run comparison, preflight, registry-backed coverage/provenance, privacy-reviewed export and resilient process execution are now real source capabilities. Some original roadmap acceptance criteria remain partial as described above.

### Future/post-P0 stable-release improvements

These remain unfinished and should not be implied by a green canary:

- Authenticode/code signing and publisher trust;
- immutable semantic stable release channel separate from the rolling canary;
- broader WPF UI automation/accessibility/localisation coverage;
- SBOM/build attestation and stronger supply-chain pinning;
- broader secret/PII classification and retention/purge controls;
- typed `EvidenceBundle`/incident architecture and a full crash/incident catalogue beyond the current diagnostic run ledger;
- true per-probe execution orchestration from the diagnostic registry;
- deeper WER/ETW/symbol/stack/deduplication/timeline capabilities from the 100-item product roadmap.

## Documentation audit scope

A3 reviewed the repository README surfaces, documentation index, desktop README, Crash Doctor engine README, current ProBook status, Phase 0 implementation record, GitHub Borrow Roadmap, 100-item roadmap/QA record, evidence/raw/conversation README files and the dated repository audit. Historical case-analysis documents are preserved rather than rewritten simply to match current product architecture.