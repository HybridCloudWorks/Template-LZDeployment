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

**Last Updated**: August 6, 2026
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

## 🟠 Script Cleanup

- [ ] **Wire `Configure-DeploymentOptions.ps1` output into Terraform**
  *(blocked, 2026-08-06: two of the three modules it would gate —
  `keyvault-cmk` and `sentinel-siem` — are scaffold-only and render-blocked,
  so there is nothing to wire them to yet. Only `defender-baseline` is real.
  Sequence this after those modules exist.)* — it
  generates `.azure/deployment-options.yaml`, but no `terraform/live/*` layer
  reads this file to decide whether to call `defender-baseline`,
  `keyvault-cmk`, or `sentinel-siem`. *(2026-08-02: the "or document
  planning-only" half is done — the script now carries a PLANNING-ONLY notice
  and [`scripts/utilities/README.md`](scripts/utilities/README.md) states the
  wiring cost. This item stays open for the actual wiring, and that README
  references it by name — rename both together or not at all.)*

---

## 🟡 Terraform Module Completeness

- [x] **`keyvault-cmk` and `sentinel-siem` stay scaffolds** *(operator
  decision 2026-08-06: "leave those key vault and sentinel options")* — both
  remain `check "module_not_implemented"` with zero resources. This is a
  deliberate accepted state, not outstanding work: the renderer blocks
  scaffold-only modules from rendering (guards G02/G03), the wizard labels
  them scaffold-only, and PROD-TODO already forbids describing them as live
  capabilities in engagement collateral. Implementing either needs an
  architecture decision first (key hierarchy and rotation, vault scope,
  purge-protection posture; data connectors, retention tiers, workspace), so
  re-open this deliberately rather than by drift.

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
- [x] **Decide the `workloads-nonprod` parity control** *(done 2026-08-06 —
  corpus-internal check, not a nonprod dogfood)* — the layer exists only in
  the corpus, so no live-vs-corpus drift check can see it and the risk is that
  it silently falls behind `workloads-prod`. Renderer section 15c now asserts
  the two sibling layers agree on the layer-agnostic variable set, that each
  owns exactly one subscription variable and neither claims the other's, and
  that both honour contract #5 (inject `azurerm.hub` into `spoke-network`,
  which declares `configuration_aliases`) and contract #3 (remote-state read
  uses AAD auth). Dogfooding a real nonprod instance remains the stronger
  proof, but it needs Azure access — see [REVIEW.md](REVIEW.md).
- [x] **Extend `Test-LzSchemaDrift` to compare schema enums against Terraform
  `contains([...])` validations** *(done 2026-08-06)* — `contains([...],
  var.<name>)` lists are now extracted alongside validation regexes, a new
  `Get-LzSchemaEnum` reads the schema side, and direction 2c compares them as
  a set difference (so every offending value is named, not just one
  counterexample). Negated element-wise tests such as
  `!contains(["*", "0.0.0.0/0"], r)` are deny lists, not allowed-value sets,
  and are excluded — tested.
  **It found a live defect on its first run**: the schema offered
  `connectivity.firewall.type = "none"`, the wizard offered it as a menu
  option and only warned, and export emitted `firewall_type = "none"`, which
  the connectivity layer rejects. Fixed by narrowing, per the Basic
  precedent. See the new item below for supporting it properly.
- [x] **Decide whether the corpus `management-baseline/moved.tf` should
  mirror to live** *(decided 2026-08-06: no — the divergence is permanent)* —
  a `moved` block rewrites a state address. Live performed the alert rename
  directly and has never held state under
  `azurerm_monitor_metric_alert.cpu_high`, so mirroring it would add a block
  that can never match anything: parity for its own sake, implying a migration
  that does not apply to this tree. Recorded as permanent in
  [docs/plans/corpus-live-reconciliation.md](docs/plans/corpus-live-reconciliation.md).
- [x] **Add azurerm-backend fixture coverage to the renderer suite** *(done
  2026-08-06)* — new `factory/tests/fixtures/azurerm-config.json`, differing
  from `sample-config.json` **only** in its backend block so a diff between
  the two shows exactly this surface. Twelve assertions cover the azurerm
  branch end to end: `backend.tf` selects azurerm and forces
  `use_azuread_auth`, the connectivity layer's remote-state read takes the
  azurerm branch rather than the hcp one and also sets AAD auth (contract #3 —
  the state account disables shared keys, so the read would 403 at init), and
  the three `state_*` tfvars that feed those reads are emitted. The converse is
  asserted too: the hcp fixture must not emit the azurerm surface, or the
  branch is not actually conditional. The fixture omits the optional
  `useAzureAdAuth` key on purpose, so it doubles as a regression test for the
  schema-default seeding fix. All four rendered layers validate against the
  real azurerm 5.0.1 provider.
- [x] **Complete the azurerm provider 5.x migration** *(done 2026-08-06)* —
  all 33 declarations across both trees are at `~> 5.0`, the five live lock
  files carry the resolved 5.0.1 entry, and the canonical registry moved with
  them. Every 5.0 breaking change was audited against what these modules
  declare; none required a resource-level change.
- [ ] **Decide the resource-provider registration strategy under azurerm 5.0**
  *(added 2026-08-06)* — 5.0 changes `resource_provider_registrations` from
  `legacy` to `none`, so the provider no longer auto-registers ~60 resource
  providers. That suits the privilege split (the Reader plan identity should
  never attempt a registration), but it makes RP registration an explicit
  prerequisite for applying into a **fresh** subscription: the first apply
  will otherwise fail with "The subscription is not registered to use
  namespace 'Microsoft.…'". Either register them in the bootstrap/broker, add
  them to `Test-LzFirstApplyPreflight`, or set `resource_providers_to_register`
  explicitly in the layer provider blocks. Not chosen here — the right answer
  depends on which identity is expected to hold registration rights.
- [x] **Add `terraform` to `LZ_FACTORY_CI_TERRAFORM_ROOTS`** *(done
  2026-08-06)* — the default is now `factory/templates/terraform,terraform`,
  so Factory CI runs `terraform init` and `validate` over the live tree as
  well as the corpus. This is the check that would have caught the dependabot
  provider split-brain directly: the live tree was previously invisible to the
  only workflow that runs credential-free.
- [x] **Decide whether a firewall-less hub is supported** *(decided
  2026-08-06 — operator: a landing zone NEEDS at least one firewall)* —
  `connectivity.firewall.type = "none"` is rejected. The bound is enforced in
  three places that must move together: the schema enum, the wizard menu, and
  the `contains([...])` validation in both platform-connectivity layers.
  `hub-network` keeps membership-based NVA gating (`contains(["palo",
  "fortinet"])` rather than `!= "azfw"`) because the negation is what let an
  out-of-set value be treated as an NVA. Running without platform networking
  entirely remains available as `connectivity.model = none`.
- [ ] **Decide the disposition of `scripts/Initialize-ClientFork.ps1`**
  *(added 2026-08-06)* — under
  [decision 0004](docs/decisions/0004-factory-copy-is-a-disposable-installer.md)
  its hardening stages (Actions enablement, branch protection, required checks,
  required approvals, secret-scanning read-back) target the **disposable**
  copy and are not part of a client run; the broker already does that class of
  work on the surviving generated repo. Its `-CreatePrivateCopy` mirror
  mechanic is still the documented way to obtain a private copy. Retire the
  hardening stages, or retarget the script at the generated repo and reconcile
  the overlap with the broker. Operator call — an entry point is not deleted
  by a cleanup pass.

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

- [ ] 🚧 **ROADBLOCKED from a clone** (the wiki is a separate repository and
  is not checked out here; needs wiki access to verify) — Review the
  single-purpose docs migrated from `docs/` to the wiki on
  2026-08-01 and not yet individually verified against current repo state:
  `Build-Critical-Path`, `Build-README`, `Build-Standards-Reference`,
  `Build-Verification-Report`, `Deployment-Flow`, `Expanded-Scope`,
  `Fix-Login-Error`, `Quick-Start`, `Static-Generator-Design`,
  `Static-Generator-Implementation`, `Testing-Static-Generator` — the
  2026-08-01 wiki restructure filed them under "Source Material" with
  historical labels; content-level review/consolidation is still owed.
- [x] **Enforce `terraform/modules/*/README.md` variable tables** *(done
  2026-08-06)* — this was previously "no tooling currently enforces this
  beyond manual review", and it had drifted: five of eleven modules
  (`defender-baseline`, `nsg-flow-logs`, `sandbox`, `keyvault-cmk`,
  `sentinel-siem`) had **no Variables section at all** while declaring 41
  variables between them. Tables were generated from each module's own
  `description`/`type`/`default` fields rather than invented, mirrored to the
  corpus, and `factory/ci/Test-ModuleDocs.ps1` now fails CI in both directions
  — an undocumented variable is one nobody can discover without reading HCL, a
  stale row is one an operator sets and Terraform silently ignores. Scoped to
  variable names on purpose: a check that fails on a reworded description
  trains people to ignore it.
  *(Cost estimates in those READMEs are still manual — they cannot be derived
  from the HCL. Tracked in [REVIEW.md](REVIEW.md).)*

---

---

## 🧭 Why the remaining items are still open

Nothing below is open for lack of attention. As of 2026-08-06 every remaining
item falls into one of four classes, and the class is stated on each item:

| Class | Meaning | Items |
| --- | --- | --- |
| 🚧 **External** | Cannot be done from the repository at all | wiki doc review (separate repo) |
| 🎯 **Needs a design decision** | Blocked on a choice nobody has made | `nsg-flow-logs` wiring, `workloads-nonprod` parity, `management-baseline/moved.tf`, RP-registration strategy under azurerm 5.0 |
| 🔗 **Blocked on another item** | Ordering, not difficulty | `Configure-DeploymentOptions` wiring (waits on the two scaffold modules, which are an accepted deferral) |
| 🧹 **Ordinary remaining work** | Just needs doing | azurerm-backend fixture coverage, module README sync, `Initialize-ClientFork.ps1` disposition |

Decided and closed on 2026-08-06 by operator direction: the azurerm 5.0
migration (done), firewall-less hub support (implemented), the GitGuardian
incident (dropped from this list), and the `keyvault-cmk`/`sentinel-siem`
scaffolds (accepted as-is).

Operator- and Azure-dependent work is not here — it lives in
[PROD-TODO.md](PROD-TODO.md), which is gated on engagement-owner confirmation
of the target tenant.

**Every item that cannot currently be completed — from this file and from
PROD-TODO.md — is consolidated in [REVIEW.md](REVIEW.md)**, with the specific
blocker, who can unblock it, and the next concrete action.

## 📚 Key Documents

- **[PROD-TODO.md](PROD-TODO.md)** — production-readiness backlog for the customer motion
- **[CHANGELOG.md](CHANGELOG.md)** — historical record of completed work
- **[docs/plans/](docs/plans/)** — analyses of record awaiting execution (corpus↔live reconciliation)
- **[docs/decisions/](docs/decisions/)** — decision records; **[docs/runbooks/](docs/runbooks/)** — operator procedures
- **[GitHub wiki](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki)** — operator guidebook ("How to Get Started") and source material (build docs, factory design and stage readiness records, webapp/static-generator docs, including [Webapp-Plan](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Webapp-Plan))
- **[GitHub Issues](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues)** — cross-cutting or infrastructure-dependent work (e.g. TFC migration, #11)

---

**Owner**: Platform Engineering
