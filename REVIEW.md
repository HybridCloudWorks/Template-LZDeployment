# REVIEW — the official record of blocked work

**Created**: August 6, 2026 · **Promoted to official root file**: August 6, 2026
(operator direction)
**Scope**: every open piece of work that is blocked on the operator (a
decision, an access grant, tenant confirmation) or on an external system.

**File contract (operator-defined 2026-08-07, supersedes 2026-08-06).** This
file holds **only blockers a human-in-the-loop can resolve** — the registry of
who can unblock each item and the next concrete action, so "still open" never
has to be re-derived. [TODO.md](TODO.md) holds **all** action items repo-wide,
phased for handoff; its gated items reference the entries here instead of
duplicating them (the §-references below map to TODO.md phases). Anything in
neither file was completed — see [CHANGELOG.md](CHANGELOG.md).

**Nothing here is blocked on effort or difficulty.** The blockers are of four
kinds:

| Kind | Meaning |
| --- | --- |
| 🔐 **Needs Azure or GitHub access** | Requires a confirmed tenant, real credentials, or repository administration |
| 🎯 **Needs a decision** | The implementation is straightforward once someone chooses |
| 🚧 **Outside this repository** | Lives in another system entirely |
| 🔗 **Blocked on another item** | Ordering, not difficulty |

---

## 🔐 Requires Azure or GitHub access — **OUT OF SCOPE THIS PHASE**

> **Phase scoping (operator, 2026-08-06).** Items 1–9 are the **go-live
> chain**, and go-live is explicitly out of scope for the current phase. They
> are recorded here so they are not re-derived, but they are **deferred, not
> pending**: do not treat tenant confirmation, the identity estate, required
> status checks, or the Stage 13/14 gates as next steps until the operator
> opens the go-live phase.

These items share one root cause: **no landing-zone identity estate exists**,
and the engagement tenant has not been confirmed.
Read-only discovery on 2026-08-01 found no landing-zone app registrations at
all, no `AZURE_PLAN_CLIENT_ID` secret, and no `dev`/`prod`/`hub` environments.

The reachable tenant belongs to a **regulated-industry client**. Creating
identities there without engagement-owner confirmation is prohibited, so this
is a hard stop rather than a task anyone can pick up.

### 1. Create the live identity estate (TODO.md item 4.1, `[BLOCKER]`)
Every PR fails `azure/login` because `AZURE_PLAN_CLIENT_ID` does not exist.
This is the single upstream cause of the two permanently-red checks on every
pull request.
**Unblocked by**: engagement owner confirming the target tenant, then running
`Start-LandingZoneBootstrap.ps1` or the broker end to end. Needs Entra
application-administrator and management-group-root rights.

### 2. Enable required status checks on `main` (TODO.md item 4.2, `[BLOCKER]`)
`main` has **no** `required_status_checks`. This is not theoretical: it is
precisely why dependabot PRs #63–#68 merged while red and left `main` unable
to `terraform init` on four of five live stacks.
**Unblocked by**: repository administration. Apply the prepared protection
payload (`gh api -X PUT repos/<owner/repo>/branches/main/protection --input
<payload>` — the script route was retired 2026-08-07 by
[decision 0007](docs/decisions/0007-retire-client-copy-hardening.md)). Note
the single-owner caveat — required approvals ≥ 1 deadlocks self-merges, and
this repo has one owner today, so keep approvals at 0 in the payload while
solo operation continues.
**Retarget note**: this applies to the **upstream factory repo only**. Under
[decision 0004](docs/decisions/0004-factory-copy-is-a-disposable-installer.md)
client copies are disposable and are never hardened.

### 3. Verify the pipeline runs green end to end (TODO.md item 4.5, `[BLOCKER]`)
No recorded successful run of `010-terraform-init.yml`,
`020-rbac-validation.yml`, `terraform-plan.yml` or `terraform-apply.yml`.
**Unblocked by**: item 1. The PR leg stays red until the identity estate exists.

### 4. Execute and accept the Stage 13 dogfood instance (TODO.md item 4.7, `[BLOCKER]`)
`factory-version.json` still carries `dogfoodInstanceAppliesGreen = false`.
**Unblocked by**: items 1–3, then the gate-by-gate runbook at
[docs/runbooks/stage13-dogfood-execution.md](docs/runbooks/stage13-dogfood-execution.md).

### 5. Run Stage 14 release attestation (TODO.md item 5.1, `[BLOCKER]`)
**Unblocked by**: item 4. Until this passes, every customer deployment is
formally a verification exercise (factory v0.9.0,
`oidcTokenExchangeVerifiedLive = false`).

### 6. Supply `-SandboxSubscriptionId` at bootstrap (TODO.md item 4.4, `[BLOCKER]`)
Without it, platform-management's sandbox-cleanup Contributor assignment fails
`AuthorizationFailed` at apply. Only blocks engagements that enable the sandbox.
**Unblocked by**: the real subscription ID, per engagement.

### 7. Execute the Stage 9/10/11 test suites — and the engagement-wrapped validation gate — in a provisioned toolchain
Broker, scaffold and import suites have never run against authenticated
external services.
**Scope narrowed 2026-08-06.** The **standalone** post-render validation gate
([decision 0005](docs/decisions/0005-post-render-validation-gate.md)) no
longer belongs under this banner at all — it is **done**. `validate-render.ps1`
executed against a real render for the first time on 2026-08-06: standalone,
strict mode, on Linux, with **no `az`/`gh` authentication** — confirming this
entry's earlier claim that the validate leg needs only the local toolchain.
Record of that execution:

- **Render**: fresh 96-file render from
  `factory/tests/fixtures/azurerm-config.json` via `Invoke-LzRender` — not a
  stale CI render. **Toolchain**: PowerShell 7.5.2, Terraform 1.13.3, tflint
  0.58.1 (bundled ruleset; no `.tflint.hcl` in the rendered tree, so no
  plugin download), tfsec 1.28.14.
- **Strict run**: V01–V06 pass — V03 ran real `terraform init -backend=false`
  in 13 directories, V04 recorded the `configuration_aliases` directories as
  designed skips. V07 **fail** (6 real tflint
  `terraform_unused_declarations` findings in `factory/templates/` sources)
  and V08 **fail** (1 LOW tfsec finding, Defender security contact missing a
  phone number; 56 checks passed). `overallStatus: fail` and the entry point
  threw naming the gate IDs — exactly as designed. The findings were
  template-corpus debt, fixed 2026-08-07 (PR #77 — record in
  [CHANGELOG.md](CHANGELOG.md)); the skip-free strict pass they blocked is
  not yet re-confirmed, see below.
- **Operator-skip run**: with `LZ_VALIDATE_SKIP_LINT` /
  `LZ_VALIDATE_SKIP_SECURITY_SCAN=true`, `overallStatus: pass` with skip
  provenance recorded per contract.
- **Scaffold enforcement**: proven fail-closed via `Test-LzScaffoldValidation`
  (the function `Invoke-LzScaffold` calls) — passing report with matching SHA
  accepted; strict-fail report → `fail`; deleted report → `missing`; tampered
  `manifestSha256` → `stale`. No apply performed.

**What remains blocked here**: the broker/import/scaffold-apply suites against
authenticated `az` and `gh` sessions; running the validate phase inside
the full engagement wrapper (discovery → broker → render → validate →
scaffold) with real discovery artifacts; and the strict re-run confirming
V07/V08 pass with real tflint/tfsec and **no skips recorded** now that the
corpus is clean (the tools were unavailable where the 2026-08-07 fixes were
made). Tracked as [TODO.md](TODO.md) item 3.1.
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
**Update 2026-08-06**: the options paper now exists as
[decision 0006 (Proposed)](docs/decisions/0006-resource-provider-registration.md)
— the three candidates costed and a recommendation marked. **Awaiting operator
ratification**; nothing is implemented until then.
**Update 2026-08-07 — ratified and implemented; no longer awaiting a
decision.** The operator ratified
[decision 0006](docs/decisions/0006-resource-provider-registration.md)
in-session: Option A (broker-time registration) complemented by Option B's
read-only PF-D preflight finding; Option C ruled out even as belt-and-braces
(any `resource_providers_to_register` value makes the Reader plan SP attempt
a write). Implemented the same day (TODO item 2.1, closed): the broker
registers the 11-namespace list in every target subscription with a bounded
poll and per-subscription per-namespace audit entries; preflight PF-D
verifies read-only with exact `az provider register` remediations; Factory
CI's "Resource provider coverage" check fails when the template corpus needs
a namespace the broker does not register; the rendered provider blocks state
`resource_provider_registrations = "none"` explicitly (live tree mirrored).
**What remains and who holds it**: the end-to-end proof — a broker apply
against a real estate and a first apply into a fresh subscription with no
`MissingSubscriptionRegistration` — is toolchain/estate-gated and carried in
[TODO.md](TODO.md) item 3.1; the operator holds that gate (§7 toolchain).

### 11. Wire `nsg-flow-logs` into a live stack
The module exists with secure defaults (90-day retention) but **zero
`terraform/live/*` callers**, so no NSG flow logs are collected anywhere.
**Decide**: which NSGs populate `var.nsg_ids` — the module does not
auto-discover them — and which Log Analytics workspace receives traffic
analytics.
**Not decided here** because the answer determines cost and data-residency
posture, not just wiring.
**Update 2026-08-08**: the options paper now exists as
[decision 0009 (Proposed)](docs/decisions/0009-nsg-flow-log-scope-and-workspace-target.md)
— three coupled choices costed (NSG scope, workspace target, hosting stack),
with **A2 + B1 + C2 behind a default-off `enable_nsg_flow_logs` flag**
recommended. The paper also records four constraints found while costing it,
which narrow the field more than the money does: the module's storage-account
name is not unique per call, so at most one instance per `(region,
environment)` can exist estate-wide; Network Watcher is per-subscription, so
a connectivity-hosted call cannot reach spoke NSGs at all; the three workspace
inputs cannot be satisfied from what `management-baseline` exports today (its
`log_analytics_workspace_id` is the **full ARM ID**, not the short GUID the
identically-named module input wants); and the `enable_private_endpoint = true`
default has no `privatelink.blob.core.windows.net` zone to attach to in either
tree. It further notes that the wizard already collects
`security.nsgFlowLogs.{enabled,retentionDays,trafficAnalytics}` and no
`variable-map.json` entry consumes any of them, and that the module README's
"~$200/month" and its `estimated_monthly_cost_usd` output are both
indefensible. Per-GB list prices could **not** be verified in-session (egress
to `prices.azure.com` and the Azure MCP pricing tool were both refused), so
every figure is a stated-assumption estimate and a rate refresh is a
ratification prerequisite — the same weakness §17 already records.
**Awaiting operator ratification**; nothing is implemented until then, and no
`.tf` file was touched by the authoring pass. Five open questions are carried
at the end of the paper, the load-bearing ones being residency (a boundary
constraint moves the recommendation from B1 to B2) and whether the generated
default should be off or should follow the wizard's pre-checked box.

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
**Update 2026-08-07 — ratified and implemented; no longer awaiting a
decision.** The operator ratified
[decision 0007](docs/decisions/0007-retire-client-copy-hardening.md)
in-session: retire the hardening stages; keep `-CreatePrivateCopy` as the
documented private-copy mechanic; retargeting ruled out because the broker
is already the sole, tested hardening owner for generated repos.
Implemented the same day (TODO item 2.2, closed): the script is now only
the private-copy mechanic (create + mirror push + visibility read-back),
its help cites decision 0007, the four hardening-only parameters are gone,
and every live instruction that pointed operators at the hardening stages
was updated — including §2 above, whose script route is replaced by the
payload route. Nothing remains open; the script file itself survives by
design (decision 0001's rationale is unchanged).

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

*Noted 2026-08-06, no action needed: the two cancelled CodeQL default-setup
runs with no logs were GitHub-side runner churn, not repo debt — default setup
completes on the next push to `main`.*

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
  package form, which was reverted rather than committed. The same workaround
  suffices for the validation gate's V03: the 2026-08-06 execution (item 7)
  resolved azurerm 5.0.1 through a packed filesystem mirror fed from
  `releases.hashicorp.com` (`TF_CLI_CONFIG_FILE` pointing at a
  `provider_installation` block).
- **GitHub Actions artifact download is not available to this session**, so CI
  evidence was read from job logs rather than the uploaded `factory-ci-output`
  artifact.
- **`Firecrawl_Search` and `microsoft-learn` MCP servers are unauthorized.**
  Neither was needed; `WebSearch` and direct raw-content fetches covered the
  azurerm 5.0 breaking-change research.

---

**Owner**: Platform Engineering
**See also**: [TODO.md](TODO.md) (all action items, phased for handoff),
[CHANGELOG.md](CHANGELOG.md) (completed work)
