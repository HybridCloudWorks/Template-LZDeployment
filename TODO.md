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

**Last Updated**: August 2, 2026
**Status**: 🟡 IN PROGRESS
**Completed work**: [CHANGELOG.md](CHANGELOG.md)
**Production-readiness backlog**: [PROD-TODO.md](PROD-TODO.md)
**External tracking**: [GitHub Issues](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues)

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
   where a user picks deployment options and it emits the legacy pipeline's
   two variable files (`terraform.auto.tfvars`, `connectivity.auto.tfvars`) —
   legacy status documented in [`frontend/README.md`](frontend/README.md).

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

## 🟠 Script Cleanup

- [ ] **Wire `Configure-DeploymentOptions.ps1` output into Terraform** — it
  generates `.azure/deployment-options.yaml`, but no `terraform/live/*` layer
  reads this file to decide whether to call `defender-baseline`,
  `keyvault-cmk`, or `sentinel-siem`. *(2026-08-02: the "or document
  planning-only" half is done — the script now carries a PLANNING-ONLY notice
  and [`scripts/utilities/README.md`](scripts/utilities/README.md) states the
  wiring cost. This item stays open for the actual wiring, and that README
  references it by name — rename both together or not at all.)*

---

## 🟡 Terraform Module Completeness

- [ ] Implement `keyvault-cmk` — currently scaffold-only (`check "module_not_implemented"`, zero resources)
- [ ] Implement `sentinel-siem` — currently scaffold-only, same pattern
- [x] Verify variable-driven "secure by default" settings actually default
  secure *(verdicts recorded 2026-08-02)*:
  - backend public access — **SECURE**: `allow_public_access_during_setup`
    defaults `false` (plus a lifecycle precondition);
  - firewall threat-intel — **SECURE with a caveat**:
    `firewall_threat_intel_mode` defaults `Alert`, but the feature itself is
    opt-in (`enable_firewall_threat_intel` defaults `false`);
  - nsg-flow-logs — retention defaults to 90 days, **but no live stack
    instantiates the module at all** (documented in its README; wiring
    tracked below).
- [ ] **Wire `nsg-flow-logs` into a live stack** *(added 2026-08-02)* — the
  module exists with secure defaults, but zero `terraform/live/*` callers
  exist, so no NSG flow logs are actually collected. Needs a design decision
  first (which NSGs go into `var.nsg_ids` — the module does not auto-discover
  them — and which Log Analytics workspace receives the traffic analytics).
- [ ] **Reconcile remaining live ↔ corpus module drift** *(added 2026-08-02)*
  — the factory-template copies of several modules have drifted from
  `terraform/modules/`, the same regeneration exposure the contract-#5
  spoke-network divergence had (a repo generated today resurrects code the
  live tree already fixed):
  - corpus `hub-network` still carries a duplicate
    `azurerm_firewall.hub_with_policy` resource the live tree eliminated;
  - corpus `management-baseline` lacks `alert_email_receivers` and still
    ships the old CPU>80% metric alert;
  - corpus `terraform.tf` pins `~> 1.6` / azurerm `~> 4.0` where the live
    tree requires `>= 1.9.0` / `~> 4.2`, across `backup-baseline`,
    `management-baseline`, `management-groups`, and `policy-baseline`.
  Cross-domain by nature — dispatch through `alz-orchestrator` so the
  reconciliation is sequenced, not edited one side at a time.

---

## 🟡 Static Config-Generator (`frontend/`)

**Reference**: [Webapp-Plan (wiki)](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Webapp-Plan) —
the page itself is documented as legacy in [`frontend/README.md`](frontend/README.md)
(`site/` is the primary path).

- [ ] **Host `frontend/` via the existing Pages workflow** —
  `deploy-pages.yml` publishes `site/` only. Before adding `frontend/`:
  the deploy needs a sibling staging layout (or link fixes) so both pages can
  ship from one Pages site, and `Test-SiteNoNetwork.ps1` must be extended to
  cover `frontend/` first so the no-network policy travels with it. Owner:
  `github-actions-engineer`.

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
