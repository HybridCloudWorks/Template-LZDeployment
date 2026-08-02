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
- [x] **Reconcile live ↔ corpus drift** *(executed 2026-08-02 — all seven
  work packages of
  [docs/plans/corpus-live-reconciliation.md](docs/plans/corpus-live-reconciliation.md)
  landed, including the WP4 platform-management promotion per
  [decision 0003](docs/decisions/0003-management-baseline-promotion.md).
  Remaining differences between the trees are deliberate and documented in
  the plan; the sole module-level divergence is the corpus-only
  `management-baseline/moved.tf` — see the open decision below.
  Operator-visible change: `terraform-apply.yml` is dispatch-only; merging
  to `main` no longer deploys.)*
- [x] **Close the action-pin drift blind spot** *(done 2026-08-02, WP5 —
  `Test-ActionPins.ps1` now enforces a canonical-SHA registry of 14 actions
  across both trees; pin drift fails CI instead of passing as "any 40-hex
  SHA".)*
- [ ] **Decide the `workloads-nonprod` parity control** *(added 2026-08-02)* —
  the layer exists **only** in the corpus (the live dogfood is prod-only), so
  it has no live counterpart and no drift check can see it. Either dogfood a
  nonprod instance or add a corpus-internal template parity check.
- [x] **Operator sign-off: workflow name collisions and dead files** *(signed
  off and executed 2026-08-02, WP5 — corpus template renamed
  `policy-diff-guardrails.yml.tmpl`, resolving the collision with live's
  `terraform-policy-checks.yml`; `deploy-from-release.yml` and
  `generate-and-release.yml` deleted along with their orphaned packager
  `terraform/compose-package/`; live workflows standardized on Terraform
  1.9.8.)*
- [ ] **Extend `Test-LzSchemaDrift` to compare schema enums against Terraform
  `contains([...])` validations** *(added 2026-08-02)* — the drift checker
  compares regex patterns only, so the azfw `Basic` defect class (a schema
  enum offering a value the Terraform validation rejects — or, as shipped, a
  value the module cannot actually deploy) is checker-invisible. The Basic
  case was fixed by narrowing the schema; the checker gap remains.
- [ ] **Decide whether the corpus `management-baseline/moved.tf` should
  mirror to live** *(added 2026-08-02)* — currently a deliberate corpus-only
  divergence: the `moved` block preserves state addresses for the alert
  rename in **regenerated** repos, which live state does not need. Either
  mirror it for strict byte parity or record the divergence as permanent in
  the reconciliation plan.
- [ ] **Add azurerm-backend fixture coverage to the renderer suite** *(added
  2026-08-02, final review)* — both test fixtures use `hcp-terraform`, so the
  azurerm form of the connectivity remote-state read and the `state_*` tfvars
  emission are never exercised by CI (verified manually: they render and
  validate). Related fragility, pre-existing: the renderer fails closed on a
  schema-valid config whose `backend.azurerm` omits the optional
  `useAzureAdAuth` key (schema default `true` is not applied at render time —
  `Unknown configuration path`); either teach the token engine schema
  defaults or gate the four reference sites.

---

## 🟡 Static Config-Generator (`frontend/`)

**Reference**: [Webapp-Plan (wiki)](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Webapp-Plan) —
the page itself is documented as legacy in [`frontend/README.md`](frontend/README.md)
(`site/` is the primary path).

- [x] **Host `frontend/` via the existing Pages workflow** *(done
  2026-08-02 — `deploy-pages.yml` now stages `site/` at the Pages root and
  `frontend/` under `/frontend/`; `Test-SiteNoNetwork.ps1` was extended to
  cover `frontend/` first, and the page's `file:`-protocol link rewrite keeps
  local opens working. The Pages source setting itself is still the Gate 2
  operator prerequisite in the
  [Stage 13 runbook](docs/runbooks/stage13-dogfood-execution.md).)*

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
- **[docs/plans/](docs/plans/)** — analyses of record awaiting execution (corpus↔live reconciliation)
- **[docs/decisions/](docs/decisions/)** — decision records; **[docs/runbooks/](docs/runbooks/)** — operator procedures
- **[GitHub wiki](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki)** — operator guidebook ("How to Get Started") and source material (build docs, factory design and stage readiness records, webapp/static-generator docs, including [Webapp-Plan](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Webapp-Plan))
- **[GitHub Issues](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues)** — cross-cutting or infrastructure-dependent work (e.g. TFC migration, #11)

---

**Owner**: Platform Engineering
