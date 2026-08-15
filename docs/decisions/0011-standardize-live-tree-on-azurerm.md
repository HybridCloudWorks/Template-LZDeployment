# Decision 0011 — Standardize the live tree on the azurerm backend

- **Status**: **Accepted** — operator-decided in-session 2026-08-15, chosen
  from the presented pair: **Option A** (azurerm everywhere in the live
  tree) over Option B (migrate the live tree to Terraform Cloud). Issue #11
  resolves as **"standardize, don't migrate"**. Implemented the same day.
- **Date**: 2026-08-15 (authored, decided, and implemented)
- **Deciders**: operator (decided in-session 2026-08-15);
  `github-actions-engineer` (authored and implemented)
- **Technical depth**: L200 (backend selection over settled mechanisms)

## Context and Problem Statement

The repository carried a recorded backend duality, tracked as GitHub
Issue #11 ("Migrate Terraform backend from azurerm to Terraform Cloud"),
[TODO.md](../../TODO.md) item 4.6, and [REVIEW.md](../../REVIEW.md) §9:

- **HCP Terraform was the recorded default.** The legacy bootloader
  (`scripts/Start-LandingZoneBootstrap.ps1`) offered an interactive backend
  prompt whose default was HCP Terraform, carried a TFC auth-check phase, a
  TFC org/workspace/`TF_API_TOKEN` setup phase, and reported
  `hcp-terraform` as the fallback backend in its bootstrap report.
- **The live tree already holds azurerm state.** Four of the five
  `terraform/live/*` root stacks carried azurerm `backend.hcl` files
  (AAD-auth per
  [contract #3](../CROSS-DOMAIN-CONTRACTS.md#3-aad-only-state-access)),
  and `terraform-plan.yml` — the modern PR gate — initializes them with
  `-backend-config=backend.hcl` under `ARM_USE_OIDC`. The fifth,
  `terraform/live/sandbox/`, declared `backend "azurerm" {}` in `main.tf`
  while its `backend.hcl` was still TFC-shaped (`hostname =
  "app.terraform.io"`, `organization`, `workspaces`) — an init-breaking
  contradiction inside one stack.
- **Workflow `010-terraform-init.yml` assumed TFC.** It passed
  `cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}` to every
  `setup-terraform` step, ran a "Verify Terraform Cloud Connection" step,
  initialized `./terraform/live` (a directory with no root configuration)
  "with TFC backend", and its summary pointed at
  `vars.TF_CLOUD_ORGANIZATION` and `https://app.terraform.io`.

The item's gate was "interactive TFC org/workspace/token setup — an
operator with TFC access". That gate exists only if the TFC side of the
duality is the one kept.

**Deliberately out of scope**: the factory's client-facing render path.
`hcp-terraform` and `azurerm` are both valid `lz-config.json` backend
choices, the corpus templates render either, and
`factory/tests/fixtures/sample-config.json` is the hcp-terraform fixture
the tests pin. That dual-backend capability is a product feature and is
not touched by this decision — this record governs only the legacy
self-deploying live tree (the Stage 13 dogfood instance): `terraform/live/*`,
the numbered workflows, and the legacy bootloader.

## Considered Options

The pair as presented to the operator:

- **Option A — standardize on azurerm everywhere (the live tree).** Keep
  the state the live tree already holds; align workflow 010 and the
  bootloader to it; the TFC setup gate dissolves because nothing on the
  live path needs a TFC organization, workspace, or token anymore.
- **Option B — migrate the live tree to Terraform Cloud.** Honour the
  issue title as written: create the TFC org/workspaces, migrate the four
  azurerm state files, rewrite the azurerm `backend.hcl` files to TFC
  form, and keep workflow 010's TFC assumptions. Requires the interactive
  org/workspace/token setup (the gate), introduces a standing external
  SaaS dependency and a static `TF_API_TOKEN` credential — the only
  static credential in an otherwise OIDC-only estate — and abandons the
  AAD-only state posture contract #3 already enforces.

## Decision

**Option A.** azurerm everywhere in the live tree, one backend per stack.
azurerm removes the external org/token dependency and matches the state
the live tree already holds; Option B would have migrated working state to
acquire a dependency and a static credential the estate is designed not to
have.

Implemented 2026-08-15:

- `terraform/live/sandbox/backend.hcl` rewritten to the azurerm form its
  own `main.tf` already declared (container `sandbox`, key
  `terraform.tfstate`, `use_azuread_auth = true`), matching its four
  siblings.
- `.github/workflows/010-terraform-init.yml`: TFC credential
  (`cli_config_credentials_token`) removed from all `setup-terraform`
  steps; the TFC connectivity step replaced; init/validate/providers-lock
  run per layer with `-backend-config=backend.hcl` under `ARM_USE_OIDC`
  as the plan SP (contract #2 — every job in 010 is read-only); the
  global-layer plan runs in `terraform/live/global`; the summary names
  Azure Storage, not TFC.
- `scripts/Start-LandingZoneBootstrap.ps1`: azurerm is the default —
  the interactive backend prompt is retired (an unseeded run gets azurerm
  without asking); `TERRAFORM_CLOUD_ENABLED` defaults to `false`; the
  report's fallback backend is azurerm. The hcp-terraform code path
  survives **only** behind an explicit `-Backend`/`-ConfigPath` override
  for legacy estates and warns that workflow 010 no longer initializes a
  TFC backend.

## Consequences

- **Issue #11 closes as "standardize, don't migrate".** The recorded
  duality is resolved by keeping the backend the state already lives in,
  not by performing the migration the issue title named.
- **The gate dissolves rather than lifts.** TODO item 4.6's gate —
  interactive TFC org/workspace/token setup — no longer applies to
  anything on the live path. No operator TFC session is needed, ever, for
  this repository's own deployment.
- **The identity estate remains the go-live gate.** Workflow 010 still
  references the same secrets it did (`AZURE_PLAN_CLIENT_ID`,
  `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) and the `backend.hcl` files
  still carry the `<REPLACE_WITH_OUTPUT_FROM_BOOTSTRAP>` storage-account
  placeholder — init going green end-to-end is TODO item 4.1/4.5
  territory (REVIEW.md §1/§3), deliberately not part of this change.
  Consistency of backend, not go-live, was the deliverable.
- **The factory's dual-backend render capability is explicitly
  unaffected.** Generated repositories still choose either backend via
  `lz-config.json`; the broker still reconciles HCP workspaces for
  hcp-terraform configs (`Set-LzHcpBackend`, `TFE_TOKEN`); the fixtures
  and their tests are untouched. `dogfood-instance.yml` keeps its
  `TF_API_TOKEN` pass-through because the dogfood config may legitimately
  render an hcp-terraform estate.
- **Reversal cost is moderate and contained.** The state itself makes
  reversal a real migration (state moves into TFC workspaces), but the
  code paths are retained: the bootloader's TFC phase still exists behind
  the explicit override, and the corpus templates keep the TFC form of
  every touched file. Reversing this decision means a new decision record
  plus `terraform init -migrate-state` per layer — not an archaeology
  exercise.
- **Residual asymmetry, accepted**: `Dispose-Engagement.ps1` still sweeps
  `TF_CLOUD_*` variables and `TF_API_TOKEN`, and the legacy remediation
  docs still mention HCP workspaces — correct as cleanup of estates
  bootstrapped before this decision, and left in place deliberately.
