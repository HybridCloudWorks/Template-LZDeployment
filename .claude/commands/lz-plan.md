---
description: Plan a landing-zone change end to end across design, Terraform, pipeline, and docs
argument-hint: [what you want to build or change]
---

Plan the following landing-zone change: **$ARGUMENTS**

Use the `alz-orchestrator` agent to drive this. Before proposing anything:

1. Read `TODO.md`, `.claude/CROSS-DOMAIN-CONTRACTS.md`, and the relevant page(s) on
   the [wiki](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki) — the
   current phase constrains what is safe to change now.
2. Identify which scopes are affected: `terraform/live/global`,
   `platform-connectivity`, `platform-management`, `workloads-prod`, `sandbox`.

Then produce a plan covering, in order:

- **Design** — what Azure resources, which SKUs, which regions, and why
  (`azure-platform-architect`).
- **Terraform** — which modules and stacks change, whether a new module is
  warranted, what tests are needed (`terraform-module-engineer`).
- **Pipeline** — workflow changes, permissions, new gates
  (`github-actions-engineer`).
- **Cost & governance** — estimated recurring cost with stated assumptions, quota
  checks required, policy implications (`azure-cost-governance`).
- **Frontend** — whether the `.tfvars` generator needs a matching change.
- **Docs** — what gets recorded in `CHANGELOG.md` and `TODO.md`.
- **Risks** — anything that could force a replace or destroy on shared
  infrastructure, and anything you could not verify.

Output the plan. Do not start implementing, and do not run any apply.
