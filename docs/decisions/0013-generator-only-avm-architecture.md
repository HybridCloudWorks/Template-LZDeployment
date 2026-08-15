# Decision 0013 — Generator-only: emit AVM references, vendor nothing

- **Status**: **Accepted** — operator-directed 2026-08-15. The operator
  supplied a superseding refactor directive document and ratified
  **"complete every effort point"**; this record documents what was
  implemented, not a proposal. Implemented the same day (classification:
  [docs/refactor/CLASSIFICATION.md](../refactor/CLASSIFICATION.md)).
- **Date**: 2026-08-15 (directed, implemented, and recorded)
- **Deciders**: operator (superseding directive, 2026-08-15); implemented
  across the refactor branch; recorded by `docs-knowledge-curator`
- **Technical depth**: L300 (exact module pins, line counts, and workflow
  inventory)

## Context and Problem Statement

Until this refactor the repository carried the landing-zone architecture
**twice**: a working `terraform/` tree (11 bespoke modules, ~3,958 HCL
lines, 5 live layers, plus `backend-bootstrap/`) that the repository
deployed against a real tenant through its own numbered workflows (the
Stage 13 "dogfood instance"), and a vendored byte-parity mirror of the same
modules under `factory/templates/terraform/` that the renderer copied
verbatim into generated repositories. The duplication was a standing
hand-sync burden ([CROSS-DOMAIN-CONTRACTS.md](../CROSS-DOMAIN-CONTRACTS.md)
contract #1 documented it as a known drift gap), the self-deploying estate
contradicted the 2026-08-15 tenant-agnostic directive ("do not tie yourself
to a specific azure tenant/sub ID, this is meant to be a template" —
[REVIEW.md](../../REVIEW.md) §7), and every bespoke module was a
maintenance liability that Microsoft's Azure Verified Modules already cover.

## Decision

The repository is a **generator only**. Both copies of the bespoke
architecture are deleted: the working `terraform/` tree (modules, live
layers, `backend-bootstrap/`) and the vendored
`factory/templates/terraform` module mirror. In their place the generator
emits **three root-module layers** that reference Azure Verified Modules by
pinned registry source and version:

| Emitted layer | AVM pattern module | Pin |
| --- | --- | --- |
| `platform-management` | `Azure/avm-ptn-alz-management/azurerm` | `0.9.0` |
| `global` | `Azure/avm-ptn-alz/azurerm` (ALZ library `platform/alz` @ `2026.04.2` via the `alz` provider) | `0.21.0` |
| `platform-connectivity` | `Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm` **or** `Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm`, selected by the topology answer (`connectivity.model`) — never both | `0.17.3` / `0.17.1` |

Load-bearing properties of the model:

- **Module source is never vendored.** The emitted root modules carry only
  `source`/`version` references
  (`factory/templates/terraform/live/*/main.tf.tmpl`); `terraform init`
  downloads the pinned versions from the Terraform Registry.
- **Renovate owns the pins in the generated repository, forever.** The
  emitted `renovate.json` (`factory/templates/renovate.json`) tracks
  Terraform module and provider datasources; the pins in
  [factory-version.json](../../factory-version.json) (`avm.modules`,
  `avm.alzLibrary`) are the *initial* values only. The generated repository
  has **no dependency on the factory** after delivery.
- **Deploy order**: `platform-management` → `global` →
  `platform-connectivity`. The `global` layer reads platform-management's
  state (`data "terraform_remote_state" "management"`,
  `factory/templates/terraform/live/global/main.tf.tmpl`) for the Log
  Analytics workspace the ALZ policy defaults require — applying `global`
  first fails there by design rather than assigning policies with a
  dangling scope.
- **The self-deploying pipeline is deleted**: workflows
  `010-terraform-init.yml`, `020-rbac-validation.yml`,
  `terraform-plan.yml`, `terraform-apply.yml`, `azure-auth-test.yml`, and
  `dogfood-instance.yml`, plus the `dogfood-instance` entry points. The
  plan/apply/auth-test *intent* survives only as emitted workflow templates
  in `factory/templates/.github/workflows/`.
- **The dogfood release gate is replaced by the end-to-end generation
  proof.** `factory-version.json` `releaseGates` now carries
  `endToEndGenerationProofPasses` (the proof procedure is the
  `docs/refactor/VALIDATION.md` gate) in place of the retired
  `dogfoodInstanceAppliesGreen`.
- **Execution-time pin verification lives in Factory CI.**
  `.github/workflows/terraform-policy-checks.yml` renders **both** topology
  fixtures (`azurerm-config`, `vwan-config`) and runs
  `terraform fmt`/`init`/`validate` on the *rendered* output — `init` there
  is what re-verifies every AVM pin and provider constraint against the
  live registry (the module input surfaces could not be verified offline;
  [CLASSIFICATION.md](../refactor/CLASSIFICATION.md) UNRESOLVED-3).
- **`brownfield-import` is quarantined**, not deleted: its import-block
  generation targets the retired bespoke modules' resource addresses, and
  re-targeting against AVM pattern-module internal addresses is pending
  ([CLASSIFICATION.md](../refactor/CLASSIFICATION.md) UNRESOLVED-2). Its
  entry points refuse with a pointer to that record.

## Consequences

- **One corpus, no hand-sync.** Contract #1's "synced by hand" gap
  dissolves — there is no second tree to drift. The cross-domain contracts
  that governed live↔corpus parity are history where they name
  `terraform/live` or `terraform/modules`.
- **No in-place upgrade path.** `factory-version.json` records
  `upgradesFrom: []` for 0.10.0: a repository generated by 0.9.0 carries
  bespoke-module state and must be regenerated or state-migrated manually.
- **A registry dependency at init.** Generated repositories require
  Terraform Registry reachability at `terraform init`. This is the
  deliberate trade against vendoring; the pins plus
  `.terraform.lock.hcl` keep it deterministic.
- **Capability deltas are ratified, not accidental.** The bespoke corpus's
  capabilities the four-pin architecture does not carry (third-party NVA
  firewalls, workload spoke layers, hand-authored policies, several
  posture modules) are recorded with their wizard treatment in
  [decision 0017](0017-wizard-scope-vs-emitted-architecture.md).
- **Supersession of the corpus-scoped parts of earlier records.** The
  subject matter of the following decisions — the bespoke modules and live
  layers — no longer exists; the records stand as history of why the
  deleted code looked the way it did:
  - [decision 0003](0003-management-baseline-promotion.md) — the
    `wire_management_workspace` count-gated read is gone; the *principle*
    (management state is the only source for the workspace identity)
    survives in the `global` layer's remote-state read above.
  - [decision 0006](0006-resource-provider-registration.md) — broker-time
    registration stands, but the corpus↔broker drift check now covers only
    the `azurerm_*` types declared directly in the emitted root modules;
    the namespaces the AVM modules' **internal** resources need are
    maintained **by hand** in the broker list (see the comment at
    `factory/ci/Invoke-FactoryCI.ps1` above the "Resource provider
    coverage" check, and `Get-LzRequiredResourceProviders`).
  - [decision 0009](0009-nsg-flow-log-scope-and-workspace-target.md) and
    [decision 0012](0012-hub-subnet-nsg-scope.md) — the `nsg-flow-logs`
    and `hub-network` modules they govern are deleted; logging and
    network posture now flow through the ALZ library archetypes and the
    AVM pattern modules.
- **Related records landed alongside this one**: delivery authentication
  and template instantiation
  ([0014](0014-delivery-auth-app-pat-and-template-instantiation.md)),
  the azurerm-only emitted backend
  ([0015](0015-azurerm-only-emitted-backend.md)), self-contained emitted
  workflows ([0016](0016-self-contained-emitted-workflows.md)), and the
  wizard-scope ratifications
  ([0017](0017-wizard-scope-vs-emitted-architecture.md)).
