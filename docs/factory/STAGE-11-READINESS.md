# Stage 11 Completion — Brownfield Import Generation

**Date:** 2026-07-26
**Factory version:** 0.6.0
**Config schema:** 2.0.0
**Manifest version:** 1.6.0

## Scope

Stage 11 implements deterministic brownfield classification and import artifact
generation. It consumes the validated config, read-only discovery inventory,
and operator-owned classifications. It never runs Terraform import or changes
state.

Supported discovery candidates are management groups, resource groups, virtual
networks, Log Analytics workspaces, key vaults, and policy assignments. Stable
Azure IDs are taken from discovery or derived from conclusive inventory fields.

## Classification contract

- Ignore is the safe default and emits nothing.
- Adopt must be explicit and must include the exact Terraform address and an
  active layer. The factory does not guess addresses.
- Replace emits no import, deletion, or replacement command and requires an
  approval reference.
- Require-Approval emits no mutation and requires an approval reference.
- Classifications are pinned to the SHA-256 of
  `discovery-inventory.json`.
- A stale inventory requires the explicit `LZ_IMPORT_ALLOW_STALE=true`
  exception and a documented owner approval.

The JSON contract is
`factory/import/brownfield-classifications.schema.json`.

## Entry points and variables

- `brownfield-import.ps1` — canonical non-interactive entry point.
- `brownfield-import.sh` — strict Bash launcher.
- `factory/import/LZFactory.Import.psm1` — candidate, classification, artifact,
  and manifest functions.
- `LZ_CONFIG_PATH`, `LZ_DISCOVERY_PATH`,
  `LZ_BROWNFIELD_CLASSIFICATIONS`, `LZ_RENDERED_PATH`, and
  `LZ_IMPORT_EVIDENCE` — paths.
- `LZ_IMPORT_APPLY` — permits writing generated review artifacts.
- `LZ_IMPORT_ALLOW_STALE` — explicit stale-inventory exception.

## Outputs

Every run emits:

- `brownfield-classifications.generated.json`;
- `brownfield-import-plan.json`;
- `brownfield-import-audit.json`.

Apply may also emit, per adopted layer:

- `terraform/live/<layer>/imports.generated.tf`;
- `scripts/import-<layer>.generated.sh`.

Stage 11 registers those paths in `render-manifest.json`, removing obsolete
Stage 11 artifacts on rerun so Stage 10 exact-inventory verification remains
authoritative.

## Safety model

Discovery must assert `readOnly=true`. Every supported probe must be conclusive
and have status Ok or Empty; Forbidden, Unavailable, and Error stop generation.
Unknown/duplicate candidates, duplicate classifications, stale hashes, invalid
Terraform addresses, and inactive layers fail closed.

Generated shell commands are review artifacts only. The module contains no
Terraform execution path and plan/audit records explicitly state
`executesTerraformImport=false`.

## User-owned activities

Classification decisions, address/layer review, stale-inventory exceptions,
approval references, state backups, speculative plans, destructive-plan
exceptions, and any later command execution are recorded in root and generated
`USER-CHECKLIST.md`. These activities did not block Stage 11 code creation or
factory deployment.

## Validation status

Executable validation was intentionally skipped at the repository owner's
direction because the environment was declared not to contain the required
binaries. Static coverage was authored but not executed. No discovery, import
generator, Terraform command, plan, state read/write, or Azure mutation ran.

The last verified executable baseline remains Stage 8:

- Wizard: 48 passed.
- Discovery: 60 passed.
- Renderer: 175 passed.
- Total: 283 passed.

## Definition of done

- [x] Plan-only non-interactive entry points implemented.
- [x] Read-only/conclusive discovery gate implemented.
- [x] Inventory-hash-pinned classification contract implemented.
- [x] Adopt/Ignore/Replace/Require-Approval behavior implemented.
- [x] Exact address/layer validation implemented.
- [x] Deterministic import blocks and review-only commands implemented.
- [x] Renderer manifest registration and stale-artifact cleanup implemented.
- [x] Plan/audit evidence and operator checklists implemented.
- [x] Static tests authored without execution.
- [x] Versions, handoff, architecture, README, TODO, and changelog reconciled.

## Next boundary

Stage 12 is Factory CI: run the complete test corpus, schema/variable drift
checks, site no-network checks, static analysis, and Terraform validation over
the raw template corpus. Stage 11 live classification/import execution remains
an operator activity in `USER-CHECKLIST.md`.
