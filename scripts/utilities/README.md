# scripts/utilities — standalone operator utilities (not part of the core flow)

Nothing in the repository calls these scripts. No workflow, no other script, and
no factory stage invokes them — they were moved out of `scripts/` (TODO.md,
"Script Cleanup", 2026-08-02) precisely so they stop reading as part of the
core bootstrap → plan → apply pipeline. They are operator-run, on demand, and
each requires an authenticated `az` session.

| Script | What it does | What wiring it in would take |
| --- | --- | --- |
| `Configure-DeploymentOptions.ps1` | Interactive selector for optional security/compliance modules (Defender, CMK/Key Vault, Sentinel); writes `.azure/deployment-options.yaml`. | **Superseded — do not wire.** The three modules it gated were deleted by [ADR 0013](../../docs/decisions/0013-generator-only-avm-architecture.md), and the wizard's `lz-config.json` is now the answer record for exactly these choices (recorded-not-deployed, [ADR 0017](../../docs/decisions/0017-wizard-scope-vs-emitted-architecture.md)). The YAML is a **planning-only artifact** nothing consumes. |
| `Invoke-BulkOperations.ps1` | Fleet operations across multiple ALZ deployments: firewall rule updates, policy changes, compliance audits, cost exports. | A dedicated `workflow_dispatch` workflow with an inventory input and its own least-privilege identity; needs multi-subscription RBAC review first. |
| `Validate-ALZDeployment.ps1` | Pre-flight validation: Terraform config, Azure environment, OIDC federation, GitHub setup, resource quotas. | The workflow it was a candidate for (`010-terraform-init.yml`) was deleted by ADR 0013. The equivalent home today is the emitted `terraform-fmt-validate.yml` in the *generated* repository, or the factory's own `validate-render.ps1` gate; needs its checks made non-interactive and exit-code clean either way. |
| `Verify-CostAccuracy.ps1` | Pulls actuals from the Azure Cost Management API, compares against estimates, flags variance/overruns per component. | A scheduled (cron) workflow publishing a step-summary report; needs a Cost Management Reader grant for the plan identity. |

Wiring any of these into workflows is a behavior change that needs its own
review — do not add call sites as a side effect of unrelated work.

## Note on `.azure/deployment-options.yaml`

`Configure-DeploymentOptions.ps1` writes `.azure/deployment-options.yaml`
(gitignored; `.azure/deployment-options.yaml.example` is the template).
**Nothing reads this file, and nothing is planned to.** The wiring formerly
tracked as REVIEW.md §16 / TODO.md item 2.5 is **superseded**: the three
modules it would have gated (`defender-baseline`, `keyvault-cmk`,
`sentinel-siem`) were deleted by ADR 0013, and under ADR 0017 these choices
are collected by the `site/` wizard and preserved in the committed
`lz-config.json` answer record instead — warned at the question and at
render (guards G02/G03), never silently dropped.

The YAML is therefore a historical planning artifact. Use the wizard to
record optional-module intent.
