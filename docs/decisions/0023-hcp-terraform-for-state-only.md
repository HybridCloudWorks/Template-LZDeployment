# Decision 0023 — HCP Terraform as a state backend, and only that

- **Status**: **Accepted** — plan-approved 2026-08-30 ("Local execution, TFC for
  state only"), implemented 2026-08-31. Partially reverses
  [decision 0015](0015-azurerm-only-emitted-backend.md).
- **Date**: 2026-08-31
- **Deciders**: operator (chose state-only over remote execution in the Phase 6
  plan)
- **Technical depth**: L200 (backend selection, the destroy gate's dependency on
  a saved plan file, credential surface)

## Context and Problem Statement

Decision 0015 cut HCP Terraform out entirely and made `azurerm` the only emitted
backend. The operator asked for it back — "there should be two options for the
state, TFC and Azure Storage" — which raises a question 0015 never had to
answer: *how much* of HCP Terraform comes back.

The obvious answer, and the wrong one, is "all of it": create the workspaces,
set them to remote execution, and let HCP Terraform run Terraform. That is how
most teams use it.

## Decision

**HCP Terraform holds the state. GitHub Actions runs Terraform.**

`backend.type` widens to `azurerm | hcp-terraform`, still defaulting to
`azurerm`. Under `hcp-terraform` each layer gets its own workspace
(`{prefix}-{layer}`), created by the bootstrap broker with
`execution-mode: local`, and the emitted `backend.tf` carries a `cloud` block
instead of an empty `azurerm` one. No `backend.hcl` is emitted — the `cloud`
block needs no partial configuration.

**`executionMode` is a `const`, not an enum with a default.** This is the part
worth reading twice.

The emitted plan and apply workflows refuse an unreviewed destroy by inspecting
a **saved plan file**:

```
terraform plan -input=false -no-color -out=tfplan
terraform show -json tfplan > plan.json     # then: any delete actions?
```

HCP Terraform **remote** runs do not support `terraform plan -out`. Switching a
workspace to remote execution therefore does not weaken that gate — it deletes
it, from both workflows, with no error and no warning. A configuration option
that silently removes a destroy guard is not an option; it is a trap. So the
schema fixes the value, guard G17 refuses anything else, and
`Set-LzHcpBackend` creates every workspace as local.

The broker does **not** reconfigure a workspace that already exists — it will
not take execution away from an operator who set it deliberately — but it
reports the mode, and a non-local one becomes a pending user activity.

## The credential trade, stated plainly

Azure authentication does not change. The workflows still federate to Azure with
GitHub OIDC, so **HCP Terraform never holds a credential to the tenant** — no
dynamic provider credentials, no stored service principal, no trust
relationship between TFC and Azure at all.

What it does add is **one static credential the `azurerm` path does not have**:
`TF_API_TOKEN`, set as a repository secret by the broker from the operator's
`TFE_TOKEN`, so the Terraform CLI can reach the workspace's state API. The
`azurerm` path has no long-lived secret anywhere. This is the cost of the
option, and a client choosing it should be choosing it knowingly — the wizard
says so on the backend step, and `validate()` warns on every export.

## Consequences

- **Schema 3.1.0**, additive: `backend.type` widens, `backend.hcpTerraform`
  appears, and `azurerm` remains the default, so every existing configuration
  keeps working unchanged.
- **The state-hardening layer is azurerm-only, structurally.** It reads the
  state storage account as a data source and puts a private endpoint in front of
  it. Under HCP Terraform there is no such account, so `Get-LzActiveLayers` does
  not emit the layer and G17 refuses the combination rather than rendering a
  data source pointing at nothing.
- **The free-tier cap is back in scope.** HCP Terraform's free tier caps
  resources *under management* at 500, and holding state elsewhere changes
  nothing about that — the resources are in the state it stores. The wizard
  estimates the count and refuses to export above the cap without an explicit
  acknowledgement.
- **`Set-LzHcpBackend` returns to the broker with a bug fixed.** The version
  removed by `e961cd5` returned a bare string array on its no-token path while
  the caller read `.pending` off it, which throws under StrictMode — the
  no-token case was the one path nobody had run.
- **Call-site position matters and is not symmetric.** `Set-LzAzurermBackend`
  runs *before* the identities, because the identity records carry data-plane
  role assignments scoped to the state storage account and a grant on a scope
  that does not exist fails. HCP Terraform has no such constraint — it needs the
  repository, not an Azure scope — so it is reconciled alongside the other
  repository configuration.

## What this does not do

Remote execution. Not because it is hard, but because getting it right means
first replacing the saved-plan destroy gate with something a remote run can
produce. Until that exists, remote execution is strictly worse than what this
factory emits today, and no amount of configuration ergonomics changes that.
