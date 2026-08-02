# TODO - HCW Landing Zone Platform

> **Production-motion work lives in [PROD-TODO.md](PROD-TODO.md)** — everything
> required to run a customer engagement (fork → clone/initiate → wizard →
> generate the customer repo → deploy → dispose the clone) moved there on
> 2026-08-01. This file keeps only repo-internal engineering debt.

> **Factory transition notice (updated 2026-08-01):** This file formerly
> carried the whole open backlog (including the factory runtime work from the
> retired `HANDOFF.md`, whose completed content and durable decisions are
> archived in [CHANGELOG.md](CHANGELOG.md)). Stage completion evidence lives on
> the [GitHub wiki](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki)
> — Stage 14 evidence is
> [Factory-Stage-14-Readiness](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Factory-Stage-14-Readiness).
> Items below remain valid only where they are also confirmed by those
> documents or by a fresh code review.

**Last Updated**: August 1, 2026
**Status**: 🟡 IN PROGRESS
**Completed work**: [CHANGELOG.md](CHANGELOG.md)
**Production-readiness backlog**: [PROD-TODO.md](PROD-TODO.md)
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

This repo is the **Landing Zone Factory** (see [README.md](README.md)): it
renders a self-contained, per-customer landing-zone repository from
`lz-config.json`. The legacy self-deploying path (`terraform/live/` plus the
numbered workflows) is retained for compatibility and serves as the Stage 13
dogfood instance. The end-to-end customer motion is described in
[PROD-TODO.md](PROD-TODO.md).

1. **`site/`** — the 15-step offline wizard that exports `lz-config.json` and
   its derived artifacts.
2. **`bootstrap-broker.ps1` / `.sh`** — the Stage 9 non-interactive entry
   point. It consumes config/discovery artifacts, plans by default, and
   reconciles Entra, RBAC, GitHub, and backend prerequisites in apply mode.
   Operator activities are in [USER-CHECKLIST.md](USER-CHECKLIST.md).
3. **`scaffold-copy.ps1` / `.sh`** — the Stage 10 plan-first scaffold entry
   point. It verifies the exact renderer inventory and publishes the generated
   working tree only under explicit apply controls.
4. **`brownfield-import.ps1` / `.sh`** — the Stage 11 plan-first
   classification/import artifact generator. It never runs Terraform import.
5. **Numbered GitHub Actions workflows** (`.github/workflows/010-*.yml`,
   `020-*.yml`, ...) plus `terraform-plan.yml`/`terraform-apply.yml` deliver
   the legacy in-repo deployment against `terraform/`.
6. **`frontend/`** is a separate, optional static HTML/JS page (no backend)
   where a user picks deployment options and it generates a `.tfvars` file,
   fed into the same Terraform/workflow pipeline.

---

## 🔴 CI/CD Hygiene

- [ ] **Mark the GitGuardian incident a false positive** —
  `factory/tests/Test-Discovery.ps1:85` holds the canonical jwt.io sample token
  (header `{"alg":"HS256"}`, payload `{"sub":"1234567890"}`) solely to prove
  `Protect-LzSecretText` redacts JWT-shaped strings. It is not a credential;
  nothing to revoke or rotate. The check keeps failing until the incident is
  marked a false positive in the GitGuardian dashboard (a UI action outside the
  repository). Do **not** "fix" it by deleting the test or splitting the
  literal — the first removes real coverage, the second evades a scanner.

---

## 🟠 Factory Bootstrap

- [ ] **Fix `Get-LzEnvironmentSubscription` for the `bootstrap` environment**
  (`factory/bootstrap/LZFactory.Bootstrap.psm1`) — the function's switch has no
  `bootstrap` case, so it fails closed (throws
  `Unknown environment 'bootstrap'`). Reachable in **both** identity models:
  `Invoke-LzBootstrap -Apply` calls `Set-LzGitHubEnvironment` for every
  `plan.environments` entry — so any broker apply against a default wizard
  export (whose platform environments include `bootstrap`) throws.
  Pre-existing defect found during the 2026-08-02 minimal-identity-estate
  work; deliberately out of scope for that parity-preserving change — needs
  its own fix.

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

- [ ] Review the single-purpose docs migrated from `docs/` to the wiki on
  2026-08-01 and not yet individually verified against current repo state:
  `Build-Critical-Path`, `Build-README`, `Build-Standards-Reference`,
  `Build-Verification-Report`, `Deployment-Flow`, `Expanded-Scope`,
  `Fix-Login-Error`, `Quick-Start`, `Static-Generator-Design`,
  `Static-Generator-Implementation`, `Testing-Static-Generator` — the
  2026-08-01 wiki restructure filed them under "Source Material" with
  historical labels; content-level review/consolidation is still owed.
- [ ] Confirm every `terraform/modules/*/README.md` variable table and cost estimate stays in sync as modules change (no tooling currently enforces this beyond manual review)

---

## 📚 Key Documents

- **[PROD-TODO.md](PROD-TODO.md)** — production-readiness backlog for the customer motion
- **[CHANGELOG.md](CHANGELOG.md)** — historical record of completed work
- **[GitHub wiki](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki)** — operator guidebook ("How to Get Started") and source material (build docs, factory design and stage readiness records, webapp/static-generator docs, including [Webapp-Plan](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Webapp-Plan))
- **[GitHub Issues](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues)** — cross-cutting or infrastructure-dependent work (e.g. TFC migration, #11)

---

**Owner**: Platform Engineering
