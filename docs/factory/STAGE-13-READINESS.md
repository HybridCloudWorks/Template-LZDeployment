# Stage 13 Completion — HCW Dogfood Instance

**Date:** 2026-07-26
**Factory version:** 0.8.0
**Config schema:** 2.0.0
**Manifest version:** 1.8.0

## Scope

Stage 13 implements the real HCW dogfood path. It materializes an operator-
approved configuration from GitHub repository variables, regenerates the
landing-zone instance into an ephemeral working directory, and supports:

- render-only generation without cloud authentication;
- read-only Terraform plans through the plan identity;
- protected-environment Terraform applies through the apply identity;
- layer selection or ordered execution of every rendered layer;
- destructive-change rejection before apply;
- per-operation logs and `dogfood-report.json` evidence.

The implementation does not commit tenant identifiers, generated `.tfvars`,
credentials, plans, state, or dogfood output.

## Entry points and variables

- `.github/workflows/dogfood-instance.yml` — manual render/plan/apply workflow.
- `dogfood-instance.ps1` and `dogfood-instance.sh` — operator entry points.
- `factory/dogfood/Invoke-Dogfood.ps1` — render, plan, apply, safety, and
  evidence orchestration.
- `LZ_DOGFOOD_CONFIG_JSON` — complete approved HCW `lz-config.json` stored as a
  repository variable.
- `LZ_DOGFOOD_CONFIG_PATH`, `LZ_DOGFOOD_OUTPUT`, and
  `LZ_DOGFOOD_EVIDENCE` — runtime paths.
- `LZ_DOGFOOD_MODE` — `Render`, `Plan`, or `Apply`.
- `LZ_DOGFOOD_LAYER` — an emitted layer or `all`.
- `LZ_DOGFOOD_REPOSITORY` — expected repository slug.
- `LZ_DOGFOOD_PLAN_CLIENT_ID`, `LZ_DOGFOOD_TENANT_ID`, and
  `LZ_DOGFOOD_SUBSCRIPTION_ID` — plan-time OIDC values.
- `AZURE_APPLY_CLIENT_ID` — protected-environment apply identity.
- `LZ_DOGFOOD_TERRAFORM_VERSION` — pinned Terraform version, default `1.9.8`.
- `LZ_DOGFOOD_APPLY=true` — second apply authorization asserted only by the
  protected apply job.
- `TF_API_TOKEN` — existing secret used only when the selected backend is HCP
  Terraform.

## Safety contract

The workflow is manual-only. Plan and apply identities remain separate. Apply
checks out `main`, requires a selected protected environment, requires the
explicit apply flag, consumes the saved plan, and refuses any delete action.
No user token or client secret is accepted.

## Evidence and release gate

Every run uploads logs and `dogfood-report.json`. The report records the
configuration hash, factory version, mode, layer, checks, mutation status, and
whether the run is eligible to support the dogfood release gate.

`dogfoodInstanceAppliesGreen` remains `false`. Code completion cannot prove a
live deployment. It may become `true` only after an independently reviewed,
successful protected apply plus Azure, state, OIDC, and GitHub read-back.

## Validation status

Local executable validation was intentionally skipped at the repository
owner's direction because this environment does not contain the required
binaries. The workflow, runner, wrappers, evidence contract, and static test
were authored but not executed. No render, Terraform init/plan/apply, Azure
login, OIDC exchange, or state operation was performed.

## Definition of done

- [x] Variable-driven dogfood render/plan/apply path implemented.
- [x] Read-only plan and protected apply identities separated.
- [x] Explicit apply authorization and destructive-change refusal implemented.
- [x] Machine-readable evidence and retained logs implemented.
- [x] Runtime configuration and generated output excluded from source control.
- [x] Root/generated operator checklists updated.
- [x] Static contract coverage authored.
- [x] Versions, handoff, architecture, README, TODO, and changelog reconciled.
- [x] Local/live validation skipped and documented without claiming success.

## Remaining operator boundary

Populate the documented variables, complete a render and plan, approve and run
each layer through the protected apply environment, review evidence, and
perform independent read-back. These activities are tracked in
`USER-CHECKLIST.md` and do not block Stage 13 code publication.
