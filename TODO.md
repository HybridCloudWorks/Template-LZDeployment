# TODO - HCW Landing Zone Platform

> **Factory transition notice (2026-07-25):** This file is the legacy deployment
> backlog. It is not the source of truth for the Landing Zone Factory build.
> Stages 1–8 and current sequencing are recorded in [HANDOFF.md](HANDOFF.md);
> Stage 8 completion evidence is in
> [docs/factory/STAGE-8-READINESS.md](docs/factory/STAGE-8-READINESS.md).
> Items below remain valid only where they are also confirmed by those documents
> or by a fresh code review.

**Last Updated**: July 25, 2026
**Status**: 🟡 IN PROGRESS
**Completed work**: [CHANGELOG.md](CHANGELOG.md)
**External tracking**: [GitHub Issues](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues)

---

## 🔴 Repository Consolidation Carryover

PR #35 was squash-merged into `main` on 2026-07-26 as commit
`8bb10ae6435a9f80ad639f4d7092767e1d255713`. At consolidation time there were
no other open pull requests, and the local checkout was clean on `main`.

- [ ] **Delete merged remote branch `agent/stage-7-workflow-corpus`** — the
  approved GitHub connector can merge pull requests and update files, but does
  not expose branch-ref deletion. Delete the branch from merged PR #35 or the
  repository branches page, then verify it no longer resolves.

---

## 📋 What This Repo Is

This repo **is** the landing zone deployment — it is not a template that spins up a separate customer repo.

1. **`scripts/Start-LandingZoneBootstrap.ps1`** — the single local entry point. Validates CLI tools, authenticates to Azure/GitHub/Terraform Cloud, creates the OIDC service principal(s) and federated credentials, sets GitHub secrets/variables/environments, and configures the Terraform Cloud workspace.
2. **Numbered GitHub Actions workflows** (`.github/workflows/010-*.yml`, `020-*.yml`, ...) pick up from there — init, RBAC validation, plan, apply — and work together with the Terraform code under `terraform/` to actually deliver the landing zone.
3. **`frontend/`** is a separate, optional static HTML/JS page (no backend) where a user picks deployment options and it generates a `.tfvars` file, fed into the same Terraform/workflow pipeline.

---

## 🔴 CI/CD & OIDC Reliability (Blocking)

- [ ] **Verify the live Entra `pull_request` federated credential** — run the
  repository bootstrap/remediation against the live application registration,
  confirm the exact repo-scoped subject by API read-back, and prove token
  exchange from a pull request. Requires an authenticated Entra operator
  session and is not performed by PR #35.
- [ ] **Enable and verify required `main` status checks** — configure branch
  protection/rulesets using the stable Stage 7 check names and
  confirm the required contexts plus enforcement by GitHub API read-back.
  Requires repository administration access.
- [ ] **Verify the pipeline actually runs green** — confirm `010-terraform-init.yml`, `020-rbac-validation.yml`, `terraform-plan.yml`, and `terraform-apply.yml` all complete successfully on a real PR/push, now that the OIDC federated-credential gap and SHA-pinning are fixed. As of 2026-07-01 there is no recorded successful run of any of these.
- [ ] **Investigate 0-second workflow failures** — some historical runs of `010-terraform-init.yml` / `020-rbac-validation.yml` fail in 0 seconds, suggesting a trigger/syntax issue independent of the OIDC fix. Confirm once a run is attempted post-fix.
- [ ] **Migrate backend from `azurerm` to Terraform Cloud** — tracked as [GitHub Issue #11](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues/11), not here (blocked on interactive TFC org/workspace/token setup).

---

## 🟠 Script Cleanup

- [ ] **Decide fate of 4 orphaned utility scripts** — `Configure-DeploymentOptions.ps1`, `Invoke-BulkOperations.ps1`, `Validate-ALZDeployment.ps1`, `Verify-CostAccuracy.ps1` have no call site anywhere (not referenced from any workflow, other script, or doc). Either wire them into the real pipeline (e.g. `Validate-ALZDeployment.ps1` as a pre-flight check in `010-terraform-init.yml`) or move them out of `scripts/` into a clearly-labeled `scripts/utilities/` or similar so they don't read as part of the core flow.
- [ ] **Wire `Configure-DeploymentOptions.ps1` output into Terraform** — it generates `.azure/deployment-options.yaml`, but no `terraform/live/*` layer currently reads this file to decide whether to call `defender-baseline`, `keyvault-cmk`, or `sentinel-siem`. Either add that wiring or document that it's a planning-only artifact today.

---

## 🟡 Terraform Module Completeness

- [ ] Add `README.md` to the 6 modules missing one: `backup-baseline`, `hub-network`, `management-baseline`, `management-groups`, `policy-baseline`, `spoke-network` (match the pattern in `defender-baseline`, `keyvault-cmk`, `nsg-flow-logs`, `sandbox`, `sentinel-siem`: description, usage example, variable table, outputs, cost estimate)
- [ ] Implement `keyvault-cmk` — currently scaffold-only (`check "module_not_implemented"`, zero resources)
- [ ] Implement `sentinel-siem` — currently scaffold-only, same pattern
- [ ] Add `Microsoft.ApiManagement` coverage to `terraform/modules/policy-baseline/policy-tls-minimum.tf` — module header claims APIM is covered by the TLS 1.2 initiative; only 5 of 6 claimed services actually have policy definitions
- [ ] Verify variable-driven "secure by default" settings actually default secure:
  - `terraform/backend-bootstrap/main.tf`: `public_network_access_enabled = var.allow_public_access_during_setup` — confirm default is `false`
  - `terraform/modules/hub-network/firewall-threat-intel.tf`: `threat_intelligence_mode = var.firewall_threat_intel_mode` — confirm default is `Alert` or `Deny`
  - `terraform/modules/nsg-flow-logs`: confirm `flow_log_retention_days` defaults to 90 at the call site, and that `terraform/live/*` passes every NSG into `var.nsg_ids` (module itself doesn't auto-discover "all" NSGs)

---

## 🟡 Static Config-Generator (`frontend/`)

**Reference**: [docs/webapp/PLAN.md](docs/webapp/PLAN.md)

- [ ] Reconcile the generator's 47 policy toggles (`frontend/app.js`) against what's actually implemented in `terraform/modules/policy-baseline/`
- [ ] Wire or clearly label module toggles (e.g. Defender) that aren't yet connected to any `terraform/live/*` call
- [ ] Host the page somewhere reachable (GitHub Pages) instead of requiring a local file open
- [ ] Write a short usage guide: fill form → download `.tfvars` → where it goes

---

## 🟢 Documentation & Repo Hygiene

- [ ] Verify GitHub repo settings that can't be checked from a local clone: secret scanning enabled, required PR approval count (currently 0 — branch protection exists but doesn't require human review)
- [ ] Review the remaining single-purpose docs under `docs/` not yet individually verified against current repo state: `BUILD_CRITICAL_PATH.md`, `BUILD_README.md`, `BUILD_STANDARDS_REFERENCE.md`, `BUILD_VERIFICATION_REPORT.md`, `DEPLOYMENT_FLOW.md`, `EXPANDED_SCOPE.md`, `FIX_LOGIN_ERROR.md`, `QUICK_START.md`, `STATIC_GENERATOR_DESIGN.md`, `STATIC_GENERATOR_IMPLEMENTATION.md`, `TESTING_STATIC_GENERATOR.md` — likely consolidation/deletion candidates
- [ ] Confirm every `terraform/modules/*/README.md` variable table and cost estimate stays in sync as modules change (no tooling currently enforces this beyond manual review)

---

## 📚 Key Documents

- **[CHANGELOG.md](CHANGELOG.md)** — historical record of completed work
- **[docs/webapp/PLAN.md](docs/webapp/PLAN.md)** — static config-generator build plan
- **[GitHub Issues](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues)** — cross-cutting or infrastructure-dependent work (e.g. TFC migration, #11)

---

**Owner**: Platform Engineering
