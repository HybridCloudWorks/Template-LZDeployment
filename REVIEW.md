# REVIEW — the official record of blocked work

**Created**: August 6, 2026 · **Promoted to official root file**: August 6, 2026
(operator direction)
**Scope**: every open piece of work that is blocked on the operator (a
decision, an access grant, tenant confirmation) or on an external system.

**File contract (operator-defined 2026-08-06).** This is the single file of
record for blocked work. [TODO.md](TODO.md) holds only work an engineer could
start right now from a clone (currently: none); when an item there acquires an
operator-shaped blocker it moves *here*, and when a blocker below is lifted the
item either gets done or moves back to TODO.md. Each entry states the specific
blocker, who can unblock it, and the next concrete action, so "still open"
never has to be re-derived. Anything in neither file was completed — see
[CHANGELOG.md](CHANGELOG.md).

**Nothing here is blocked on effort or difficulty.** The blockers are of four
kinds:

| Kind | Meaning |
| --- | --- |
| 🔐 **Needs Azure or GitHub access** | Requires a confirmed tenant, real credentials, or repository administration |
| 🎯 **Needs a decision** | The implementation is straightforward once someone chooses |
| 🚧 **Outside this repository** | Lives in another system entirely |
| 🔗 **Blocked on another item** | Ordering, not difficulty |

---

## 🔐 Requires Azure or GitHub access

These are the largest group and they share one root cause: **no landing-zone
identity estate exists**, and the engagement tenant has not been confirmed.
Read-only discovery on 2026-08-01 found no landing-zone app registrations at
all, no `AZURE_PLAN_CLIENT_ID` secret, and no `dev`/`prod`/`hub` environments.

The reachable tenant belongs to a **regulated-industry client**. Creating
identities there without engagement-owner confirmation is prohibited, so this
is a hard stop rather than a task anyone can pick up.

### 1. Create the live identity estate (PROD-TODO Phase 2, `[BLOCKER]`)
Every PR fails `azure/login` because `AZURE_PLAN_CLIENT_ID` does not exist.
This is the single upstream cause of the two permanently-red checks on every
pull request.
**Unblocked by**: engagement owner confirming the target tenant, then running
`Start-LandingZoneBootstrap.ps1` or the broker end to end. Needs Entra
application-administrator and management-group-root rights.

### 2. Enable required status checks on `main` (PROD-TODO Phase 1, `[BLOCKER]`)
`main` has **no** `required_status_checks`. This is not theoretical: it is
precisely why dependabot PRs #63–#68 merged while red and left `main` unable
to `terraform init` on four of five live stacks.
**Unblocked by**: repository administration. Apply the prepared protection
payload, or run `scripts/Initialize-ClientFork.ps1 -Repository <owner/repo>
-Apply`. Note the single-owner caveat — required approvals ≥ 1 deadlocks
self-merges, and this repo has one owner today.
**Retarget note**: this applies to the **upstream factory repo only**. Under
[decision 0004](docs/decisions/0004-factory-copy-is-a-disposable-installer.md)
client copies are disposable and are never hardened.

### 3. Verify the pipeline runs green end to end (PROD-TODO Phase 5, `[BLOCKER]`)
No recorded successful run of `010-terraform-init.yml`,
`020-rbac-validation.yml`, `terraform-plan.yml` or `terraform-apply.yml`.
**Unblocked by**: item 1. The PR leg stays red until the identity estate exists.

### 4. Execute and accept the Stage 13 dogfood instance (PROD-TODO Phase 4, `[BLOCKER]`)
`factory-version.json` still carries `dogfoodInstanceAppliesGreen = false`.
**Unblocked by**: items 1–3, then the gate-by-gate runbook at
[docs/runbooks/stage13-dogfood-execution.md](docs/runbooks/stage13-dogfood-execution.md).

### 5. Run Stage 14 release attestation (PROD-TODO Phase 5, `[BLOCKER]`)
**Unblocked by**: item 4. Until this passes, every customer deployment is
formally a verification exercise (factory v0.9.0,
`oidcTokenExchangeVerifiedLive = false`).

### 6. Supply `-SandboxSubscriptionId` at bootstrap (PROD-TODO Phase 2, `[BLOCKER]`)
Without it, platform-management's sandbox-cleanup Contributor assignment fails
`AuthorizationFailed` at apply. Only blocks engagements that enable the sandbox.
**Unblocked by**: the real subscription ID, per engagement.

### 7. Execute the Stage 9/10/11 test suites in a provisioned toolchain
Broker, scaffold and import suites have never run against authenticated
external services.
**Unblocked by**: a provisioned toolchain with real `az` and `gh` sessions.

### 8. Set GitHub Pages source to "GitHub Actions"
`deploy-pages.yml` exists and is SHA-pinned; the repository setting is a
one-time manual prerequisite.
**Unblocked by**: repository administration (Settings → Pages).

### 9. Resolve the backend duality / TFC migration
Tracked as GitHub Issue #11; blocked on interactive Terraform Cloud
org/workspace/token setup.
**Unblocked by**: an operator with TFC access.

---

## 🎯 Needs a decision

Implementation is straightforward once the choice is made. Each entry states
exactly what has to be decided.

### 10. Resource-provider registration strategy under azurerm 5.0
**New, introduced by this work — and now load-bearing: staying on 5.0 is
operator-ratified (2026-08-06), so this cannot be sidestepped by a rollback.** azurerm 5.0 changes
`resource_provider_registrations` from `legacy` to `none`, so the provider no
longer auto-registers ~60 resource providers. This suits the privilege split —
the Reader plan identity should never attempt a registration — but it makes RP
registration an explicit prerequisite for the **first apply into a fresh
subscription**, which will otherwise fail with *"The subscription is not
registered to use namespace 'Microsoft.…'"*.
**Decide**: register them in the bootstrap/broker, add them to
`Test-LzFirstApplyPreflight`, or set `resource_providers_to_register`
explicitly in the layer provider blocks.
**Depends on**: which identity is expected to hold registration rights. Not
chosen here because guessing wrong moves a privileged operation onto the wrong
principal.

### 11. Wire `nsg-flow-logs` into a live stack
The module exists with secure defaults (90-day retention) but **zero
`terraform/live/*` callers**, so no NSG flow logs are collected anywhere.
**Decide**: which NSGs populate `var.nsg_ids` — the module does not
auto-discover them — and which Log Analytics workspace receives traffic
analytics.
**Not decided here** because the answer determines cost and data-residency
posture, not just wiring.

### 12. Disposition of `scripts/Initialize-ClientFork.ps1`
Under decision 0004 its hardening stages (Actions enablement, branch
protection, required checks, required approvals, secret-scanning read-back)
target the **disposable** copy and are not part of a client run; the broker
already does that class of work on the surviving generated repo. Its
`-CreatePrivateCopy` mirror mechanic is still the documented way to obtain a
private copy.
**Decide**: retire the hardening stages, or retarget the script at the
generated repo and reconcile the overlap with the broker.
**Not done here**: deleting an operator entry point is the operator's call, not
a cleanup pass's.

### 13. Ownership policy for the generated repository
The *mechanism* is settled and needs no change — `github.ownershipModel` and
`github.ownerName` are required schema fields, and
`LZFactory.Scaffold.psm1` targets `ownerName/repositoryName`, so ownership is
explicit per engagement and never inherited from whoever is logged in.
**Decide**: which value CBTS puts in `ownerName` for a typical engagement, and
whether a repo created under one owner is transferred to the client afterward.
**Watch out**: `ownershipModel: personal` on a Free plan cannot use protected
environments (schema risk GH1), which silently removes the gate the apply
identity's `environment:<name>` OIDC subjects depend on.

### 14. Implement `keyvault-cmk` and `sentinel-siem`
**Operator-accepted deferral as of 2026-08-06** ("leave those key vault and
sentinel options"). Both remain `check "module_not_implemented"` with zero
resources. This is a decided state, not drift: the renderer blocks
scaffold-only modules from rendering (guards G02/G03) and the wizard labels
them scaffold-only.
**Would need, if re-opened**: key hierarchy and rotation policy, vault scope,
purge-protection and soft-delete posture, HSM vs software keys; and for
Sentinel, which data connectors, retention split across analytics and archive
tiers, and which workspace.

---

## 🚧 Outside this repository

### 15. Publish the prepared wiki review edits
The content review this entry used to track is **complete** (2026-08-06):
all 11 migrated docs were verified against the repository, verdicts are
recorded in [docs/wiki-review/README.md](docs/wiki-review/README.md), and the
wiki edits — a HISTORICAL banner per page plus corrected `Home.md` section
labels (the Build and generator sets were mislabeled "(reference)") — are
authored and preserved as
[docs/wiki-review/2026-08-06-historical-banners.patch](docs/wiki-review/2026-08-06-historical-banners.patch).
**Blocked**: pushing to `Template-LZDeployment.wiki` — the git proxy injects
credentials only for the session's authorized repository set, the wiki is not
in it, and adding it (`add_repo`) requires interactive approval an autonomous
session cannot grant. Read access works (that is how the review was done);
write does not.
**Unblocked by**: `git am` the patch and push from any machine with wiki write
access (commands in the review README), or approve `add_repo` for the wiki in
an interactive Claude session.

---

## 🔗 Blocked on another item

### 16. Wire `Configure-DeploymentOptions.ps1` output into Terraform
The script generates `.azure/deployment-options.yaml`, but no `terraform/live/*`
layer reads it to decide whether to call `defender-baseline`, `keyvault-cmk`
or `sentinel-siem`.
**Blocked on item 14**: two of the three modules it would gate are
scaffold-only and render-blocked, so there is nothing to wire them to. Only
`defender-baseline` is real. Sequence this after those modules exist.
The script already carries a PLANNING-ONLY notice and
[`scripts/utilities/README.md`](scripts/utilities/README.md) states the wiring
cost, so the current state is documented rather than misleading.

---

## ✋ Cannot be automated

### 17. Cost estimates in module READMEs
`factory/ci/Test-ModuleDocs.ps1` now enforces that every module README's
**variable table** matches `variables.tf`, in both directions. The **cost
estimates** in those same READMEs cannot be checked the same way: they are not
derivable from the HCL, and they go stale against Azure list prices rather
than against the repo.
**Needs**: periodic human review against current Azure pricing, ideally at
release time. The `azure-cost-governance` capability and the `azure-cost`
skill exist for exactly this, but the figures still need a human to accept
them.

---

## Environment limitations encountered

Recorded because they shaped *how* things were verified, not *whether* they
were done. Neither blocked any deliverable.

- **`registry.terraform.io` is not on this environment's egress allowlist**
  (403 at the proxy). Provider resolution through the normal path is
  impossible here. Worked around legitimately: `releases.hashicorp.com` *is*
  reachable, so azurerm 5.0.1 and random 3.9.0 were fetched from there into a
  local filesystem mirror, and all 34 root and module directories across both
  trees were initialised and validated against the real provider. Lock files
  were left unchanged — the mirror contributes an extra `h1:` hash for its own
  package form, which was reverted rather than committed.
- **GitHub Actions artifact download is not available to this session**, so CI
  evidence was read from job logs rather than the uploaded `factory-ci-output`
  artifact.
- **`Firecrawl_Search` and `microsoft-learn` MCP servers are unauthorized.**
  Neither was needed; `WebSearch` and direct raw-content fetches covered the
  azurerm 5.0 breaking-change research.

---

**Owner**: Platform Engineering
**See also**: [TODO.md](TODO.md) (repo-internal backlog),
[PROD-TODO.md](PROD-TODO.md) (production motion),
[CHANGELOG.md](CHANGELOG.md) (completed work)
