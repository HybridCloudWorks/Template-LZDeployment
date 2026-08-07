# Runbook — Engagement Disposal (Phase 6)

**Scope**: disposing of the local factory clone at the end of a customer
engagement. Execution tool: [`scripts/Dispose-Engagement.ps1`](../../scripts/Dispose-Engagement.ps1)
(plan-first; nothing is deleted without `-Apply`). Model:
[decision 0004](../decisions/0004-factory-copy-is-a-disposable-installer.md)
(the copy is a disposable installer; disposal is the defined end of every
engagement).

**The one rule**: **archive, then delete.** Every archived copy is verified by
SHA-256 against its source before anything is removed; disposal hard-fails if
`lz-config.json` cannot be archived and verified — it is the regeneration key
for the entire landing zone.

---

## 1. Archive (before any deletion)

Archive to client records or the customer repo (`-ArchivePath`):

| Artifact | Why it is kept |
| --- | --- |
| `lz-config.json` | Regeneration key for the whole landing zone — disposal hard-fails without it |
| `bootstrap-plan.json` + `bootstrap-audit.json` | Broker change evidence (identities, RBAC, GitHub, backend) |
| `scaffold-plan.json` + `scaffold-audit.json` | Exact published inventory and commit provenance |
| `discovery-inventory.json` + `tenant-readiness-report.md` | Tenant state at engagement time |
| `render-manifest.json` | What the renderer emitted |
| `.reports/**` | Legacy bootstrap reports |
| Dogfood / release evidence (`dogfood-report.json`, `dogfood-evidence/**`, `release-readiness*`) | Release-gate provenance |

The script verifies each copy by SHA-256 hash before step 2 runs.

## 2. Delete from the clone

- `.lz-bootloader-state.json` (tenant ID, subscription ID, SP app IDs)
- `generated-output/` (customer-confidential configuration)
- Rendered staging output (`LZ_RENDERED_PATH`, default `./rendered-output`)
- Every `.terraform/` cache
- `*.lz-backup-*` directories
- Finally, the clone directory itself

## 3. End sessions

- `az logout` + `az account clear`
- `gh auth logout`
- `terraform logout` (drops the HCP Terraform credential)
- Unset `TFE_TOKEN` and all `LZ_*` variables. The script clears the current
  process; shell-profile cleanup commands are **printed** for the operator —
  the script never edits profiles.

## 4. MUST NOT delete

These survive disposal — they **are** the deliverable. The script prints this
banner on every run:

- The state storage account and containers (or HCP Terraform workspaces).
- The landing-zone identities in the client tenant that serve the **customer
  repo** (the broker-created set).
- The customer repository itself.
- The archive written in step 1.

## 5. Fork-side residue

The client fork retains `AZURE_CLIENT_ID`, `AZURE_PLAN_CLIENT_ID`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TF_API_TOKEN`, variables,
environments, and any bootstrap branch/PR (`bootstrap/phase-0-oidc-setup-*`,
which historically committed `.lz-bootloader-state.json`).

- **Fork retired** once the customer repo takes over: delete the secrets,
  revoke the TFC token, delete bootstrap branches, archive the repo.
- **Fork retained** as the client's factory instance: record that it holds
  tenant-scoped configuration.

`Dispose-Engagement.ps1` prints the `gh` cleanup commands; it executes them
only with the explicit combination `-IncludeForkCleanup -Apply
-ForkRepository <owner>/<name>`.

## 6. Identity end-state — decision (2026-08-01)

Two write-capable identity sets must never persist with one unmonitored.

**Decision**: at disposal, the fork-bound legacy-script identity set —
federated credentials subject-bound to the fork (`repo:<owner>/<fork>:…`),
their role assignments, and their app registrations — is **deleted**, once the
generated repo's broker-created identities are verified working (OIDC token
exchange from a real PR and a gated apply in the customer repo).

**Documented alternative, narrow case only**: when the engagement never used
the broker path (no broker-created identities exist), re-point the fork-bound
subjects to the customer repo instead of deleting the set. Do not do both;
never leave both sets live.

## 7. Evidence

The script writes `disposal-plan.json` (what would happen) and
`disposal-audit.json` (what happened, with hashes). Preserve both with the
step-1 archive.
