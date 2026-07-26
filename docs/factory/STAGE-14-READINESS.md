# Stage 14 Completion — Release Evidence Attestation

**Date:** 2026-07-26
**Factory version:** 0.9.0
**Config schema:** 2.0.0
**Manifest version:** 1.9.0

## Scope

Stage 14 adds a credential-free release-evidence aggregation and promotion-
planning boundary. It consumes retained evidence instead of re-running cloud
operations:

- a complete, unskipped Factory CI report;
- a successful full Stage 13 protected apply report;
- an independently reviewed read-back attestation pinned to both report hashes.

It computes the five factory release gates and emits
`release-readiness-report.json` plus `release-gates.proposed.json`.

## Entry points and variables

- `.github/workflows/release-readiness.yml` — manual artifact aggregation.
- `release-readiness.ps1` and `release-readiness.sh` — operator entry points.
- `factory/release/Invoke-ReleaseReadiness.ps1` — fail-closed evaluator.
- `factory/release/release-attestation.schema.json` — reviewed attestation
  contract.
- `LZ_RELEASE_FACTORY_CI_REPORT`, `LZ_RELEASE_DOGFOOD_REPORT`, and
  `LZ_RELEASE_ATTESTATION_PATH` — exact evidence inputs.
- `LZ_RELEASE_EVIDENCE` — output directory.
- `LZ_RELEASE_EXPECTED_REPOSITORY` — repository binding.
- `LZ_RELEASE_MAX_EVIDENCE_AGE_HOURS` — maximum evidence age; default 168.
- `LZ_RELEASE_ATTESTATION_JSON` — repository-variable attestation.
- `LZ_RELEASE_ALLOW_INCOMPLETE=true` — emit incomplete diagnostic evidence
  without treating it as promotion-ready.

## Safety

The workflow has only `actions: read` and `contents: read`. It receives no OIDC
permission, Azure credentials, backend credentials, HCP token, or GitHub
administration permission. The evaluator never writes `factory-version.json`,
creates a tag or release, opens a PR, or declares v1.0.0.

The attestation binds the reviewer and approval reference to SHA-256 hashes of
the exact Factory CI and dogfood reports. Evidence freshness is enforced.

## Release semantics

`readyForPromotion=true` requires every finding and all five proposed gates to
pass. The resulting proposal remains review-only. Any gate change requires a
separate pull request and the operator approvals in `USER-CHECKLIST.md`.

All release gates remain unchanged in the Stage 14 implementation commit.

## Validation status

Local executable validation was intentionally skipped at the repository
owner's direction because this environment does not contain the required
binaries. No PowerShell test, schema validator, workflow, artifact download,
Factory CI, dogfood, Azure, OIDC, Terraform, or state command was executed.

## Definition of done

- [x] Manual credential-free evidence workflow implemented.
- [x] Hash-pinned read-back attestation contract implemented.
- [x] Factory CI completeness and freshness checks implemented.
- [x] Full dogfood apply eligibility and freshness checks implemented.
- [x] Five-gate computation and fail-closed reporting implemented.
- [x] Review-only promotion proposal implemented.
- [x] Root/generated user checklists updated.
- [x] Static contract coverage authored.
- [x] Versions and project documents reconciled.
- [x] Runtime validation skipped and documented without claiming success.

## Remaining operator boundary

Complete the live activities in `USER-CHECKLIST.md`, retain the exact artifacts,
author and approve the hash-pinned attestation, run Release Readiness, and open
a separate release-gate PR only if the report is promotion-ready.
