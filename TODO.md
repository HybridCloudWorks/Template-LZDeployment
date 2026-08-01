# TODO - HCW Landing Zone Platform

> **Factory transition notice (updated 2026-08-01):** This file now carries the
> whole open backlog — legacy deployment debt plus the factory runtime work
> formerly tracked in `HANDOFF.md` (retired 2026-08-01; its completed content
> and durable decisions are archived in [CHANGELOG.md](CHANGELOG.md)). Stage
> completion evidence lives on the
> [GitHub wiki](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki) —
> Stage 14 evidence is
> [Factory-Stage-14-Readiness](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Factory-Stage-14-Readiness).
> Items below remain valid only where they are also confirmed by those documents
> or by a fresh code review.

**Last Updated**: August 1, 2026
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

1. **`bootstrap-broker.ps1` / `.sh`** — the Stage 9 non-interactive entry point. It consumes config/discovery artifacts, plans by default, and reconciles Entra, RBAC, GitHub, and backend prerequisites in apply mode. Operator activities are in [USER-CHECKLIST.md](USER-CHECKLIST.md).
2. **`scaffold-copy.ps1` / `.sh`** — the Stage 10 plan-first scaffold entry point. It verifies the exact renderer inventory and publishes the generated working tree only under explicit apply controls.
3. **`brownfield-import.ps1` / `.sh`** — the Stage 11 plan-first classification/import artifact generator. It never runs Terraform import.
4. **Numbered GitHub Actions workflows** (`.github/workflows/010-*.yml`, `020-*.yml`, ...) pick up from there — init, RBAC validation, plan, apply — and work together with the Terraform code under `terraform/` to actually deliver the landing zone.
5. **`frontend/`** is a separate, optional static HTML/JS page (no backend) where a user picks deployment options and it generates a `.tfvars` file, fed into the same Terraform/workflow pipeline.

---

## 🔴 CI/CD & OIDC Reliability (Blocking)

- [ ] **Execute and accept the Stage 13 dogfood instance** — populate the
  variables in `USER-CHECKLIST.md`, run render and read-only plans, apply each
  layer through its protected environment, preserve `dogfood-report.json`, and
  independently read back Azure, state, OIDC, and GitHub controls. Only then
  set `dogfoodInstanceAppliesGreen=true` in a reviewed PR.

- [ ] **Run Stage 14 release attestation** — select exact successful Factory CI
  and full dogfood apply run IDs, approve the hash-pinned read-back attestation,
  and retain the readiness report. Open a separate release-gate PR only when
  `readyForPromotion=true`.

- [ ] **Add the live Entra `pull_request` federated credential, then verify it**
  — CI is red on every PR: `RBAC Audit & Validation` and `RBAC Compliance
  Checks` fail at Azure login with
  `AADSTS700213: No matching federated identity record found for presented
  assertion subject 'repo:saulpatinojr/HCW-Plan_LZDeployment:pull_request'`.
  The code fix landed; the live Entra app registration was never updated, and
  this reproduces on any PR. Fix (needs Application Administrator):

  ```bash
  az ad app federated-credential create --id <APP_ID> --parameters '{"name":"pr-plan","issuer":"https://token.actions.githubusercontent.com","subject":"repo:saulpatinojr/HCW-Plan_LZDeployment:pull_request","audiences":["api://AzureADTokenExchange"]}'
  ```

  Then run the repository bootstrap/remediation against the live application
  registration, confirm the exact repo-scoped subject by API read-back, and
  prove token exchange from a pull request. Requires an authenticated Entra
  operator session and is not performed by PR #35.
- [ ] **Enable and verify required `main` status checks** — `main` currently has
  **no** `required_status_checks`, and Terraform Apply/Plan, secret scanning,
  and action pinning exist in the repo while being turned off in GitHub
  settings — every check on a PR is advisory, so a green merge proves nothing.
  Run Factory CI at least once, then configure branch protection/rulesets using
  the stable check names (including `Factory CI / Factory CI`) and confirm the
  required contexts plus enforcement by GitHub API read-back. Requires
  repository administration access.
- [ ] **Execute the Stage 9 broker, Stage 10 scaffold, and Stage 11 import test
  suites in a provisioned toolchain** — authenticated external services and the
  required binaries were intentionally unavailable/skipped during
  implementation; runtime validation of those suites is still owed.
- [ ] **Mark the GitGuardian incident a false positive** —
  `factory/tests/Test-Discovery.ps1:85` holds the canonical jwt.io sample token
  (header `{"alg":"HS256"}`, payload `{"sub":"1234567890"}`) solely to prove
  `Protect-LzSecretText` redacts JWT-shaped strings. It is not a credential;
  nothing to revoke or rotate. The check keeps failing until the incident is
  marked a false positive in the GitGuardian dashboard (a UI action outside the
  repository). Do **not** "fix" it by deleting the test or splitting the
  literal — the first removes real coverage, the second evades a scanner.
- [ ] **Reconcile the remaining `terraform/live/` ↔ factory-corpus divergence**
  — the 2026-08-01 remediation converged `org_prefix`,
  `firewall_threat_intel_mode`, and the automation `start_time` (see
  [CHANGELOG.md](CHANGELOG.md)), but `terraform/live/sandbox/variables.tf`
  still validates `location` with `^[a-z]+$` (corpus uses `^[a-z0-9]+$`), the
  `workloads-prod` remote-state container layout should be re-verified against
  the corpus, and the approved hub-network subnet re-layout plan lands in the
  PR's terraform-plan run. `Test-LzSchemaDrift` only compares the schema
  against `factory/templates/` — the live tree is synced by hand until Stage 13
  regenerates this repo from the factory, which resolves the split permanently.
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

**Reference**: [Webapp-Plan (wiki)](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Webapp-Plan)

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
- **[GitHub wiki](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki)** — build docs, factory design and stage readiness records, webapp/static-generator docs (including [Webapp-Plan](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Webapp-Plan))
- **[GitHub Issues](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues)** — cross-cutting or infrastructure-dependent work (e.g. TFC migration, #11)

---

**Owner**: Platform Engineering
