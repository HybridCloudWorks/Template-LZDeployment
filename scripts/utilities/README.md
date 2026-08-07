# scripts/utilities — standalone operator utilities (not part of the core flow)

Nothing in the repository calls these scripts. No workflow, no other script, and
no factory stage invokes them — they were moved out of `scripts/` (TODO.md,
"Script Cleanup", 2026-08-02) precisely so they stop reading as part of the
core bootstrap → plan → apply pipeline. They are operator-run, on demand, and
each requires an authenticated `az` session.

| Script | What it does | What wiring it in would take |
| --- | --- | --- |
| `Configure-DeploymentOptions.ps1` | Interactive selector for optional security/compliance modules (Defender, CMK/Key Vault, Sentinel); writes `.azure/deployment-options.yaml`. | Terraform would need to read the YAML: map its keys to `terraform/live/*` variables (e.g. via a small renderer step or `terraform.tfvars` generation) — today the file is a **planning-only artifact** no `terraform/live/*` layer consumes. |
| `Invoke-BulkOperations.ps1` | Fleet operations across multiple ALZ deployments: firewall rule updates, policy changes, compliance audits, cost exports. | A dedicated `workflow_dispatch` workflow with an inventory input and its own least-privilege identity; needs multi-subscription RBAC review first. |
| `Validate-ALZDeployment.ps1` | Pre-flight validation: Terraform config, Azure environment, OIDC federation, GitHub setup, resource quotas. | Natural candidate as a pre-flight job in `010-terraform-init.yml` (pwsh step before `terraform init`); needs its checks made non-interactive and exit-code clean. |
| `Verify-CostAccuracy.ps1` | Pulls actuals from the Azure Cost Management API, compares against estimates, flags variance/overruns per component. | A scheduled (cron) workflow publishing a step-summary report; needs a Cost Management Reader grant for the plan identity. |

Wiring any of these into workflows is a behavior change that needs its own
review — do not add call sites as a side effect of unrelated work.

## Note on `.azure/deployment-options.yaml`

`Configure-DeploymentOptions.ps1` writes `.azure/deployment-options.yaml`
(gitignored; `.azure/deployment-options.yaml.example` is the template). **No
`terraform/live/*` layer reads this file today** — enabling
`defender-baseline`, `keyvault-cmk`, or `sentinel-siem` still requires editing
the corresponding Terraform variables/call sites by hand. The YAML is a
planning and documentation artifact until the wiring tracked in REVIEW.md
§16 / TODO.md item 2.5 ("Wire `Configure-DeploymentOptions.ps1` output into
Terraform") lands.
