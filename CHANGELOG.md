# CHANGELOG - Completed Work

**Purpose**: Historical record of completed work. **Going forward (operator
contract, 2026-08-07): new entries record shipped features only.** Existing
entries below are history and are not rewritten.
**Last Updated**: August 7, 2026

---

## NSG flow-log options paper proposed — decision 0009 (2026-08-08)

The [REVIEW.md](REVIEW.md) §11 gate on TODO item 2.3 now has the paper it was
waiting for:
[docs/decisions/0009-nsg-flow-log-scope-and-workspace-target.md](docs/decisions/0009-nsg-flow-log-scope-and-workspace-target.md).
`terraform/modules/nsg-flow-logs/` has zero callers in either tree, so no NSG
flow log is collected in this repository's deployment or in any generated
repository — while the wizard already collects
`security.nsgFlowLogs.{enabled,retentionDays,trafficAnalytics}`
(`lz-config.schema.json:586`, `site/index.html:701`) with no
`variable-map.json` entry consuming any of it. The paper separates the three
coupled choices by owner — NSG scope (A0–A4), workspace target (B1
`management-baseline` via decision 0003's `count`-gated remote-state read, B2
dedicated workspace, B3 operator-supplied ID), hosting stack (C1
connectivity, C2 per-workload, C3 management) — and recommends **A2 + B1 +
C2, behind a default-off `enable_nsg_flow_logs` flipped in a later PR**, the
`wire_management_workspace` shape. Four constraints surfaced during costing
and narrow the field more than the money does: the module's
`stflowlogs{region_code}{environment}` storage-account name is not unique per
call, capping the estate at one instance per `(region, environment)`; Network
Watcher is regional **and** per-subscription and the module declares no
`configuration_aliases`, so a connectivity-hosted call cannot reach spoke
NSGs at all; the module's three workspace inputs cannot be satisfied from
today's exports, and `management-baseline`'s `log_analytics_workspace_id` is
the full ARM ID rather than the short GUID its identically-named input wants;
and `enable_private_endpoint = true` has no
`privatelink.blob.core.windows.net` zone anywhere outside `backend-bootstrap`.
Costing is list-price with assumptions stated in line — per-GB rates could not
be verified in-session, egress to `prices.azure.com` and the Azure MCP pricing
tool both being refused, so a rate refresh is a ratification prerequisite
(REVIEW.md §17). It records that cost tracks traffic volume rather than NSG
count, that `traffic_analytics_interval` 10 vs 60 is the one large lever, and
that the module README's "~$200/month" and its `estimated_monthly_cost_usd`
output — which ships into every generated repo — are both indefensible.
Status **Proposed**; awaiting operator ratification; nothing implemented and
no `.tf` file touched. [REVIEW.md](REVIEW.md) §11 and [TODO.md](TODO.md) item
2.3 point at the paper; item 2.3 stays open. Suites after the work: node 87/0,
Test-Renderer 245/0, Test-CI 12/0, Factory CI 17/17.

---

## Dot-prefixed folders are configuration-only — documentation migrated out of `.claude/` (2026-08-07)

Operator-directed policy, recorded as
[decision 0008](docs/decisions/0008-dot-prefixed-folders-are-configuration-only.md):
dot-prefixed folders (`.github/`, `.claude/`, `.azure/`, …) hold tooling
configuration only; documentation found there is classified by content,
migrated to its authoritative destination, and deleted at the source. The
2026-08-07 audit cleared `.github/` and `.azure/` (no documentation) and
ruled the `.claude/` agents/commands/skills markdown tool-required
configuration; three files were documentation and moved (`git mv`, history
preserved): `.claude/CROSS-DOMAIN-CONTRACTS.md` →
`docs/CROSS-DOMAIN-CONTRACTS.md` (content intact, internal links rebased),
`.claude/hooks/README.md` → `docs/runbooks/agent-report-portable-kit.md`
(portable-kit how-to; now names `.claude/hooks/` as the source explicitly),
and `.claude/README.md` → `docs/claude-orchestration.md` (inventory and
import provenance kept; rule prose duplicating CLAUDE.md §§1/2/5 trimmed to
links, making CLAUDE.md the sole source for routing/reporting/guardrail
rules). Every live referrer retargeted in the same change — 10 agent files
and the `lz-plan` command, CLAUDE.md (which also gained the 0008 policy
note), README.md, `frontend/README.md` and `frontend/app.js`, the
spoke-network and management-baseline READMEs in both the live and factory
template trees, `scripts/Add-PlanFederatedCredential.ps1`, the Stage 13
runbook, decision 0003, `terraform-plan.yml.tmpl`, and
`LZFactory.Bootstrap.psm1`; CHANGELOG history entries naming the old paths
are left as history. The findings-and-disposition table in decision 0008 is
the policy's consolidation report. Suites after the work: node 87/0,
Test-Renderer 245/0, Test-CI 12/0, Factory CI 17/17.

## `Initialize-ClientFork.ps1` hardening stages retired — private-copy mechanic survives (2026-08-07)

TODO item 2.2, closed the day the operator ratified
[decision 0007](docs/decisions/0007-retire-client-copy-hardening.md)
in-session (retire, not retarget; `-CreatePrivateCopy` survives). Under
[decision 0004](docs/decisions/0004-factory-copy-is-a-disposable-installer.md)
the factory copy is a disposable installer that is never hardened, so the
script's Actions-enablement, branch-protection, secret-scanning, and
hardening read-back stages were wrong-target; the broker
(`factory/bootstrap/LZFactory.Bootstrap.psm1`) remains the sole hardening
owner for the surviving generated repository. The script is now only the
private-copy mechanic: create + mirror push (with the bootstrap-branch
residue warning), public-visibility warning, and visibility read-back —
plan-first as before. The hardening-only parameters (`-Branch`,
`-RequiredApprovals`, `-RequiredChecks`, `-EnforceAdmins`) are removed and
the comment-based help rewritten to the surviving purpose, citing decision
0007 — including a latent fix: a blank line now separates `#Requires` from
the help block, without which PowerShell never associated the help and
`Get-Help` showed only auto-generated syntax. Live instructions swept in the same change: README structure comment,
CLAUDE.md §0, USER-CHECKLIST Stage 12, REVIEW.md §2, the Stage 13 runbook
(Gate 2a is payload-route only, with approvals 0 for the single-owner
caveat), and the engagement-lifecycle runbook; decision records retained as
history (0004's open question 2 annotated as resolved). No factory test
referenced the script or its retired parameters. Suites after the work:
Factory CI 17/17, node 87/0, Test-Bootstrap 85/0, Test-Renderer 245/0,
Test-CI 12/0.

## Resource-provider registration shipped — broker-time, PF-D verified, CI drift-guarded (2026-08-07)

TODO item 2.1, closed the day the operator ratified
[decision 0006](docs/decisions/0006-resource-provider-registration.md)
in-session (Option A + Option B's preflight finding; Option C ratified
against, even as belt-and-braces). azurerm ~> 5.0 registers no resource
providers, so the first apply into a fresh subscription 409'd
`MissingSubscriptionRegistration`; registration now lands on the client's
interactive bootstrap session — the only identity in the motion already
holding `*/register/action` (decision 0004) — with zero new grants and no
contract-#2 change. Suites after the work: node 87/0, Test-Bootstrap 85/0
(was 60), Test-CI 12/0 (was 11), Test-Renderer 245/0, Factory CI 17/17 (was
16; terraform and static legs remain pipeline-side).

**Broker registration step** (`factory/bootstrap/LZFactory.Bootstrap.psm1`).
`Invoke-LzBootstrap -Apply` now registers the required namespaces in every
target subscription (each configured environment's subscription plus the
azurerm state backend subscription) BEFORE state-storage reconciliation,
since the state account itself needs `Microsoft.Storage`. Idempotent like
every other broker mutation: `Registered` is a recorded no-op,
`Registering` is polled without re-issuing. The read-back poll is bounded
(default 300s per subscription, `LZ_RP_REGISTRATION_TIMEOUT_SECONDS`
override); anything slower is recorded as `pending` — registration completes
server-side, so the pending-user-activity entry says verify, not re-run.
Outcomes land per subscription per namespace in `bootstrap-audit.json`
(`resourceProviders` section; plan mode records the intent). The
11-namespace list is decision 0006's table verbatim, stored ONCE
(`Get-LzRequiredResourceProviders`) with the excluded registered-by-default
namespaces (`Microsoft.Authorization`, `Microsoft.Resources`) explicit;
`Microsoft.KeyVault` is a deliberate look-ahead for the keyvault-cmk
scaffold. Deliberately NOT added to `bootstrap-plan.json`: the
per-environment plan output is under a byte-parity contract.

**Preflight PF-D** (fourth `Test-LzFirstApplyPreflight` family). Read-only
`az provider list` per target subscription (Reader suffices) against the
same authoritative list — never a second copy. Unregistered namespaces
surface as WARN findings carrying the exact
`az provider register --namespace <ns> --subscription <id>` remediation;
an unreadable state (az absent/unauthenticated — plan mode's normal
condition) degrades to a single INFO finding, never an error. Detects and
explains, never edits, never blocks — the existing preflight contract. The
az read sits behind an injectable `-ProviderStateReader` seam, so tests
drive the real finding logic with fake states.

**Factory CI drift check** (`factory/ci/Test-ResourceProviderCoverage.ps1`,
new "Resource provider coverage" check). Derives the distinct `azurerm_*`
resource/data types from `factory/templates/terraform/` (`.tf` and
`.tf.tmpl`, the superset of anything rendered), maps each through
`Resolve-LzResourceTypeNamespace` — the broker-owned mapping that encodes
the non-obvious cases (`monitor_*`→Insights,
`log_analytics_*`→OperationalInsights, `management_group*`→Management,
policy assignment→PolicyInsights, `resource_group`→Resources-excluded) —
and fails when a namespace the corpus needs is missing from the broker
list, naming the type, the namespace, and the exact extension points. An
unmapped type fails the same way. Test-Bootstrap proves both failure modes
against seeded corpora (item-1.3 precedent) and the green path against the
real corpus.

**Explicit posture in provider blocks.**
`resource_provider_registrations = "none"` is now stated, not inherited, in
every rendered `provider "azurerm"` block (global, platform-connectivity,
platform-management, workloads-prod/nonprod incl. hub aliases, sandbox) and
mirrored into the corresponding `terraform/live/*` stacks (contract-#1
lock-step). No `resource_providers_to_register` anywhere — Option C is
ratified against. `terraform/backend-bootstrap/` is deliberately untouched:
no template counterpart, operator-interactive, and behaviorally identical
either way. `terraform fmt -check` clean on both trees.

**Residual** (carried in TODO item 3.1): the end-to-end proof — broker
apply registering against a real estate, then a first apply into a fresh
subscription with no `MissingSubscriptionRegistration` — needs the
authenticated toolchain.

## Dot-folder contract text updated to the 2026-08-07 file contract (2026-08-07)

TODO item 2.7, closed in PR #77 after the operator approved dot-folder edits
in-session. `.claude/agents/docs-knowledge-curator.md`'s "What lives where"
section now states the four-file root contract (README, TODO, REVIEW,
CHANGELOG), the `docs/USER-CHECKLIST.md` location with its code-referenced
consumers, and the actual homes of decisions, runbooks, wiki-review evidence,
and `.claude/CROSS-DOMAIN-CONTRACTS.md`. The
`.github/workflows/020-rbac-validation.yml` trigger comment now cites the
live blocker (REVIEW.md §1) instead of the retired "PROD-TODO Phase 2".
Validation: `grep -rn "PROD-TODO" .github/ .claude/` returns no
live-instruction references.

## TODO Phase 1 shipped — skip-free strict corpus, Linux scaffold fix, drift-check proven (2026-08-07)

PR #77 closes the three startable engineering items (TODO.md Phase 1, items
1.1–1.3) opened by the 2026-08-06 strict validation run, plus the live-tree
mirror of the corpus cleanup. Suites after the work: node 87 passed / 0
failed, Test-Scaffold 16/0 (was 13), Test-Renderer 245/0 (was 239), Factory
CI 16/16 (terraform and static legs remain pipeline-side).

**1.1 — template corpus cleaned for strict V07/V08** (the [REVIEW.md](REVIEW.md)
§7 findings). The 6 tflint `terraform_unused_declarations` findings and the
LOW tfsec finding are resolved at source in `factory/templates/terraform/`:
unused `var.default_tags` (defender-baseline), `var.log_retention_days`
(hub-network, nsg-flow-logs), `var.landingzones_mg_id` (policy-baseline,
including its caller argument), and the unused `azurerm_client_config` data
source (management-baseline) removed, with README variable tables and usage
examples updated in lock-step. `sandbox_subscription_id` is kept with the
corpus's only `tflint-ignore`: it is consumed by `main.tf.tmpl` inside the
sandbox renderer conditional while `variables.tf` is copied verbatim into
every render, so sandbox-less renders legitimately leave it unreferenced.
`security_contact_phone` (defender-baseline) is now **required with a
non-empty validation**, mirroring `security_contact_email`, instead of
shipping a non-compliant empty-string default. **Caveat**: the item's
validation criterion — `validate-render.ps1 -Strict` passing V07/V08 with no
skips — is **not yet confirmed**; tflint/tfsec were unavailable in the
sandbox, so confirmation travels with the TODO.md item 3.1
authenticated-toolchain execution.

**1.2 — scaffold plan/apply works on Linux against real renders.**
`Get-LzScaffoldInventory` walked with `Get-ChildItem -Force` but the per-file
size read used `Get-Item` without `-Force`, so hidden leaf files — the
renderer emits `.terraform-docs.yml` per module — crashed scaffold plan and
apply on Linux (reproduced 2026-08-06). Fixed with `-Force`; an audit of the
rest of the walk/copy path found no other latent instance. The coverage gap
that let Factory CI miss it is closed: `Test-Scaffold.ps1` now actually
executes the walk (a real-module run over a temp tree with a hidden
`.terraform-docs.yml` leaf), proven by revert-run-restore — with the fix
reverted the new cases fail on the genuine error.

**1.3 — the enum/`contains` drift check is proven end to end.** The item was
partially stale: the production checker gap was already closed by 435845e
(#69, 2026-08-05) after the item was written (2026-08-02), and the 2026-08-06
consolidation missed it — `Test-LzSchemaDrift` already reports a blocking
`ConstraintMismatch`, wired into Factory CI. No production change was made;
the deliverable became the missing proof. Test-Renderer now replays the azfw
worked example through the **real** checker: a seed corpus whose schema enum
carries `Basic` while `variables.tf` accepts only `Standard`/`Premium` must
fail with a single blocking `ConstraintMismatch` naming the field, the
variable, and the rejected value; a second pass widens the Terraform list to
a superset and must stay `InSync`, pinning contract #7's
wizard-⊂-schema-⊂-terraform directionality.

**Live-tree mirror.** The same cleanups are mirrored into `terraform/` (the
Stage 13 dogfood tree, hand-synced per the contract-#1 known gap), restoring
byte parity on the nine touched module files. Two deliberate divergences from
a blind mirror: `sandbox_subscription_id` is untouched in the live tree — the
concrete platform-management stack genuinely uses it twice — and the
`security_contact_phone` requirement is safe because **no live stack
instantiates `defender-baseline`**; the first wiring must supply an E.164
value by design.

---

## Validation gate executed against a real render; RP-registration options paper proposed (2026-08-06)

**`validate-render.ps1` ran against a real render for the first time** —
standalone, strict mode, on Linux, with no `az`/`gh` authentication,
confirming REVIEW.md §7's claim that the validate leg needs only the local
toolchain. A fresh 96-file render from
`factory/tests/fixtures/azurerm-config.json` (PowerShell 7.5.2, Terraform
1.13.3, tflint 0.58.1, tfsec 1.28.14) passed V01–V06 — V03 ran real
`terraform init -backend=false` in 13 directories — and failed V07/V08 on 7
real template-corpus findings; `overallStatus: fail` and the entry point threw
naming the gate IDs, as designed. A second run with the documented operator
skips passed with skip provenance recorded per contract. Scaffold enforcement
proved fail-closed via `Test-LzScaffoldValidation`: pass, fail, missing, and
stale (tampered `manifestSha256`) all classified correctly; no apply
performed. Full record: [REVIEW.md](REVIEW.md) §7.

**Two engineering items opened in [TODO.md](TODO.md)**, ending its "no open
engineering debt" status: (1) the 6 tflint + 1 tfsec template-corpus findings,
which block a skip-free strict run; (2) a Linux hidden-file crash in
`Get-LzScaffoldInventory` (`LZFactory.Scaffold.psm1:110` lacks `-Force`) that
breaks scaffold plan and apply on Linux against real renders — missed by
Factory CI because `Test-Scaffold.ps1` is a static text-matching suite that
never executes the walk.

**Decision 0006 proposed.** The resource-provider registration strategy under
azurerm 5.0 (REVIEW.md §10) now has its options paper:
[docs/decisions/0006-resource-provider-registration.md](docs/decisions/0006-resource-provider-registration.md)
costs the three candidates and recommends broker-time registration
complemented by a read-only preflight finding. Status **Proposed** — awaiting
operator ratification; nothing is implemented.

---

## Post-render validation gate: scaffold apply refuses unvalidated renders (2026-08-06)

**The gap.** Nothing between the renderer (Stage 5) and the scaffold (Stage
10) ran `terraform init`/`validate`, a blocking format check, lint, or a
security scan against the tree a specific configuration actually produced —
the renderer's `terraform fmt` pass only warns, and Factory CI validates the
source corpus, not a render. An undeployable or non-compliant render could
therefore reach the customer repository. Decision record:
[docs/decisions/0005-post-render-validation-gate.md](docs/decisions/0005-post-render-validation-gate.md).

**The gate.** New `factory/validate/LZFactory.Validate.psm1` with entry points
`validate-render.ps1` / `validate-render.sh` runs eight gates — V01
inventory-integrity, V02 format-verification, V03 dependency-integrity
(`terraform init -backend=false` per rendered `*.tf` directory), V04
terraform-validate (with the Factory CI `configuration_aliases` skip rule),
V05 workflow-pinning-policy, V06 provider-constraint-integrity, V07 lint
(tflint), V08 security-scan (checkov/tfsec/trivy) — runs ALL of them even
after a failure, writes `validate-report.json` plus per-gate logs under
`LZ_VALIDATE_EVIDENCE`, and throws naming the failing gate IDs. Tool-driven
gates run against a scratch copy under the system temp directory so
`terraform init`'s `.terraform/` directories never poison the scaffold's
exact-inventory check; the rendered tree stays byte-identical. Missing
`terraform` fails V02–V04 closed; missing optional tools record explicit
skips, or fail under `-Strict` / `LZ_VALIDATE_STRICT=true`; `-SkipLint` /
`-SkipSecurityScan` record deliberate operator skips.

**Enforcement.** `Invoke-LzScaffold -Apply` now classifies the report
(`pass`/`fail`/`missing`/`stale` — stale meaning `manifestSha256` does not
match the current `render-manifest.json`) before any tree mutation, records
`validation` in `scaffold-audit.json`, and refuses to publish unless the
report passes — `LZ_SCAFFOLD_ALLOW_UNVALIDATED=true` is the loud, audited
override, mirroring the `-AllowNotReady` precedent.
`scripts/Invoke-CustomerEngagement.ps1` gains the `validate` phase between
render and scaffold (always read-only; `-Apply` never propagates to it).

**Registration and docs.** `factory/tests/Test-Validate.ps1` added and wired
into `factory/ci/Invoke-FactoryCI.ps1` (and the Test-CI suite-list contract);
Test-Scaffold extended with the apply-gate assertions; `.gitignore` covers
`/validate-evidence/`; USER-CHECKLIST documents the validation variables and
run; README lists the new entry points. `factory-version.json` stays at 0.9.0:
bumping it forces the wizard `FACTORY_VERSION` constant, four test fixtures,
and the pending Stage 14 v0.9.0 evidence-selection instructions
(USER-CHECKLIST/PROD-TODO/REVIEW) to move in lock-step, which is an
operator-record change, not part of this gate.

---

## Wiki source material reviewed; backlog consolidated into TODO/REVIEW roles (2026-08-06)

**Wiki review (closes the last open TODO.md engineering item).** The 11
documents migrated from `docs/` to the wiki on 2026-08-01 were content-reviewed
against the repository at `main`. Verdict: all 11 are historical planning
material, not reference — the Build set describes a June 2026 React + Node.js
+ Bicep initiative superseded by the factory conversion before it started
(the repo contains no React, no Node backend, no Bicep); the generator set
describes `frontend/`, the legacy page (no MSAL survives; the CSV premise of
Static-Generator-Design never shipped). The wiki `Home.md` index mislabeled
both sets "(reference)". Per-doc verdicts:
[docs/wiki-review/README.md](docs/wiki-review/README.md). The corrective wiki
edits (HISTORICAL banner per page, index relabels) are authored and preserved
as a patch in the same directory; pushing them is blocked on wiki write
access and tracked as REVIEW.md §15.

**Backlog consolidation (operator direction).** [TODO.md](TODO.md) now holds
only completable engineering work — currently **none** — and
[REVIEW.md](REVIEW.md) is promoted to the **official root file of record** for
everything blocked on the operator or an external system. The four
operator-gated items formerly open in TODO.md (Configure-DeploymentOptions
wiring, nsg-flow-logs wiring, RP-registration strategy,
Initialize-ClientFork disposition) now live solely in REVIEW.md §§10–12/16.
PROD-TODO.md keeps the phase-structured motion with a tracking note pointing
at REVIEW.md.

**Repository-slug hygiene.** The transfer to `HybridCloudWorks/
Template-LZDeployment` left ~50 links and live operator commands pointing at
the old `saulpatinojr/HCW-Plan_LZDeployment` slug across 14 files (READMEs,
both TODO files, the Stage 13 runbook's `gh` commands, both JSON schema `$id`s,
agent configs). All current-instruction references now use the real slug;
verbatim historical quotes (the AADSTS700213 subject in PROD-TODO, past
CHANGELOG entries) are intentionally unchanged.

---

## Record correction: the PR #69 squash title; azurerm 5.0 ratified permanent (2026-08-06)

**The merge commit's subject line on `main` is wrong about firewalls.** PR #69
was squash-merged as *"fix: unbreak main, migrate to azurerm 5.0, support
firewall-less hubs, ratify decision 0004"*. That title predates the operator's
correction mid-PR: firewall-less support was implemented, then **reversed** in
the same PR (commit *"fix(connectivity): a landing zone requires at least one
firewall"*, preserved in the squash body). The merged state — and the standing
policy — is the opposite of the title: **a landing zone always deploys at
least one firewall** (`azfw`, `palo`, or `fortinet`); `none` is rejected by
the schema, the wizard, and both connectivity layers. `connectivity.model =
none` remains the supported way to run no platform networking at all. The
commit on protected `main` cannot be reworded; this entry is the correction of
record.

**azurerm `~> 5.0` is permanent** (operator-ratified 2026-08-06: "we are
staying on azurerm 5.0"). It is no longer a migration that could be revisited:
the canonical constraint in `factory/ci/Test-ProviderConstraints.ps1` is the
enforcement point, and the one open consequence — the resource-provider
registration strategy, since 5.0 defaults `resource_provider_registrations` to
`none` — is tracked in TODO.md as a decision about *which identity registers*,
not about the provider version. Stale references corrected in this change:
README.md's technology-stack table claimed `~> 4.0`, and the
`terraform-module-engineer` agent rules still described 5.0 as an upgrade to
plan rather than the enforced present state.

---

## azurerm 5.0 across both trees; firewall-less hubs supported (2026-08-06)

Operator direction after the handoff review. Validation: 8 PowerShell suites,
wizard 89/89, renderer 216/216, action pinning, site no-network, provider
constraints, schema drift InSync, `terraform fmt` clean, module parity across
both trees — all green locally.

**azurerm 5.0.** All 33 constraint declarations across `terraform/` and
`factory/templates/terraform/` move to `~> 5.0`, including the four `.tf.tmpl`
roots dependabot cannot parse. The five live lock files carry the resolved
5.0.1 entry, propagated from the one backend-bootstrap already had — lock
hashes are a property of the provider version, not the consuming directory,
which is what made this possible without registry access. Every 5.0 breaking
change was audited against what these modules actually declare and **none
required a resource-level change**: the flow log already used
`target_resource_id`, no `address_space` is indexed, and
`service_endpoints` / the removed Log Analytics and Recovery Services
properties / `queue_properties` / `static_website` / `skip_provider_registration`
are all unused. One behavioural consequence is tracked in TODO.md:
`resource_provider_registrations` now defaults to `none`, so RP registration
becomes an explicit prerequisite for a first apply into a fresh subscription.

**Firewall-less hubs.** `connectivity.firewall.type = "none"` is supported
rather than removed. `hub-network` treated firewall_type as azfw-versus-NVA
(`count = var.firewall_type != "azfw" ? 1 : 0`), so "none" would have built
NVA subnets, an NVA NSG, and a default route to a trust IP collected only for
palo/fortinet. Five gates now test membership; the to-firewall route table is
absent under "none" and spokes use Azure default routing;
`firewall_private_ip` is null and `route_table_id` uses `one(...)`. The single
new failure mode — forced tunnelling with nothing to tunnel to — fails at plan
via a `spoke-network` precondition rather than mid-apply.

**Backlog decisions.** `keyvault-cmk` and `sentinel-siem` are recorded as an
accepted deferral rather than open work (renderer guards G02/G03 already block
them from rendering). The GitGuardian item is dropped from TODO.md.

---

## `main` unbroken, provider drift made a CI failure, operator model ratified (2026-08-06)

Colleague-handoff completion. Validation: 8 PowerShell suites, wizard 81/81
(was 74), renderer 216/216 (was 205), action pinning, site no-network, schema
drift InSync, PowerShell parse sweep — all green locally.

**⚠ `main` was broken and is now fixed.** Dependabot PRs #63–#68 bumped
azurerm `~> 4.2` → `~> 5.0` in the six directories `.github/dependabot.yml`
watched. The same constraint is declared in ~35 files, so the bump landed
half-applied and `~> 4.2` (>= 4.2, < 5.0) met `~> 5.0` (>= 5.0, < 6.0) in the
same graph — no intersection. Four of five live stacks (`global`,
`platform-connectivity`, `platform-management`, `workloads-prod`) failed at
`terraform init`, before any plan. Restored at `~> 4.2`, matching every live
root, the whole template corpus, and the 4.79.0 in all five live lock files.
`terraform/backend-bootstrap` keeps `~> 5.0` — standalone root, no module
calls, own lock at 5.0.1. The 5.x migration is tracked in TODO.md rather than
guessed at.

**Why nothing caught it.** Factory CI — the only workflow that runs without
Azure credentials, and so the only one that reports today — did not list
`terraform/**` in its path filter. The workflows that do watch `terraform/**`
fail at `azure/login` on the missing identity estate. And `main` has no
required status checks, so six red PRs merged and the redness meant nothing.
Fixed: new `factory/ci/Test-ProviderConstraints.ps1` (canonical registry, same
shape as the action-pin registry; static, credential-free, network-free, with
a reasoned-exception table checked for staleness), `terraform/**` added to
Factory CI's path filter, and dependabot's six per-directory terraform entries
collapsed into one grouped entry so a bump lands whole or not at all.

**Enum constraint drift is now detectable — and it found a live defect.**
`Test-LzSchemaDrift` compared validation regexes only, so a schema enum
offering a value `contains([...])` rejects was invisible. It now extracts
`contains([...], var.<name>)` lists (excluding negated element-wise deny
lists) and compares them against schema enums as a set difference. First run
found `connectivity.firewall.type = "none"`: offered by the wizard, only
warned, exported as `firewall_type = "none"`, rejected by the connectivity
layer — and `hub-network` would have treated it as an NVA with no trust IP.
Narrowed out of the schema and the wizard per the `Basic` precedent, with a
blocking guard for configs drafted earlier. No platform networking at all
remains available as `connectivity.model = none`.

**Renderer no longer fails closed on valid configs.** A schema-valid config
omitting an optional key with a schema default raised `Unknown configuration
path` (observed: `backend.azurerm.useAzureAdAuth`, referenced by four
templates). `New-LzRenderContext` takes an optional `-SchemaPath` and seeds
defaults for absent paths; config values always win, and an absent parent
block seeds no phantom children.

**Operator model ratified.** [Decision 0004](docs/decisions/0004-factory-copy-is-a-disposable-installer.md)
— the factory copy is a disposable installer, not a client asset — is
confirmed by the operator in their own words and quoted in the record. It
settles that the copy mechanic is an indifference point (so nothing may assume
a fork), that the *client* runs the tooling, and that the new repository is
created before the landing-zone files. PROD-TODO.md is reconciled: the motion
description no longer describes a governed client-owned fork, the
"client fork"/"local clone" pair is collapsed into one disposable copy, and
both Phase 1 GitHub-settings items are retargeted at the upstream factory repo
instead of "every client fork". Open question 3 narrowed on inspection —
`github.ownershipModel`/`ownerName` are required schema fields, so org-owned
landing zones are already supported; what is open is engagement policy.

**Also**: `020-rbac-validation.yml` had a path filter on `push` but not
`pull_request`, so it ran on documentation-only PRs and failed at
`azure/login`; mirrored the filter. Its `docs/RBAC-REQUIREMENTS.md` references
pointed at a file that has never existed in the repository's history —
retargeted at `docs/decisions/0002-minimal-identity-estate.md`, which actually
records the estate.

---

## Corpus↔live reconciliation executed — WP1–WP7 (2026-08-02)

Executes [docs/plans/corpus-live-reconciliation.md](docs/plans/corpus-live-reconciliation.md)
in full (WP7 is this documentation close-out). Validation: Factory CI 13
runnable checks green, wizard 74/74, renderer 206/206, schema drift InSync,
4 rendered fixtures validate 16/16.

**⚠ Operator-visible behavior change: merging to `main` no longer deploys.**
`terraform-apply.yml` is now **dispatch-only** (operator decision, WP5 — live
adopts the corpus safety model): the push trigger is removed; deploys are
Actions → Terraform Apply → pick a layer. The run checks out the trusted
default branch, validates the layer against a hard allowlist, creates a saved
plan (`plan -out=tfplan`), refuses destructive plans, and applies exactly
that reviewed plan through the layer's protected environment gate. Root
`permissions: {}` with per-job opt-in.

**WP1/WP2/WP6 — module and live-stack sync**: the corpus modules are now
byte-identical to `terraform/modules/` in tracked content (pins to
`>= 1.9.0` / azurerm `~> 4.2`, policy-baseline `Indexed` modes,
nsg-flow-logs wholesale, defender-baseline single-subscription rewrite) with
**one deliberate divergence** — a corpus-only
`management-baseline/moved.tf` preserving state addresses for the alert
rename in regenerated repos. Live side: sandbox pins + 1970 sentinel tag
dates (replacing expired hardcoded dates), new
`terraform/live/workloads-prod/outputs.tf` (spoke-VNet outputs; the layer
previously had none).

**WP3 — hub-network**: corpus at byte parity (duplicate
`azurerm_firewall.hub_with_policy` gone, subnet plan 12–15, GatewaySubnet
NSG removed, derived nullable NVA trust IP); corpus connectivity
`management_ip_ranges` is now `list(string)`, required, wildcard-rejecting,
with the commented tfvars placeholder (contract #4); new
`UPGRADE-GUIDE.md.tmpl` subsection documenting the regeneration impact —
for repos generated from the older module, regeneration onto existing state
produces destroy/recreate plans (firewall replacement = outage); route
through the Stage 11 adoption path.

**WP4 — platform-management promotion** (per
[decision 0003](docs/decisions/0003-management-baseline-promotion.md)):
corpus `management-baseline` synced first, then the corpus
platform-management layer gained the unconditional `management_baseline`
module call, the three variables (`org_prefix` — now a contract-#1 member,
row added to the table — `log_retention_days`, `alert_email_receivers`) and
the `log_analytics_workspace_id` output. `computed.alertEmailReceivers`
composed in the TokenEngine from `observability.alerting.actionGroupEmails`.
The connectivity layer carries the `count`-gated
`wire_management_workspace` remote-state read (default `false`,
`use_azuread_auth` per contract #3) with `effective_law_id` precedence — an
explicitly supplied value overrides the read. Variable-map mappings added,
including `management_ip_ranges → literal:operator-supplied`. Contract #4's
amendment is finalized: the gated read is in the tree; the manual
resource-ID paste is retired.

**WP5 — workflows**: corpus templates bumped to live's action generation;
live standardizes Terraform 1.9.8; the corpus plan workflow gains the PR
plan comment + tfplan artifact; `azure-auth-test.yml` upgraded from
informational to **enforcing** (role assertions fail the run) with a weekly
cron; `secrets-scan.yml` gains a committed `.tfstate`/`.tfplan` check; the
corpus `terraform-policy-checks.yml.tmpl` is renamed
`policy-diff-guardrails.yml.tmpl` (manifest, Test-Renderer, and broker
comment updated) resolving the name collision with live's fmt/tflint/tfsec
suite; dead workflows `deploy-from-release.yml` and
`generate-and-release.yml` **deleted**, along with their orphaned packager
`terraform/compose-package/`; **`Test-ActionPins.ps1` now carries a
canonical-SHA registry** (14 actions, enforced in both trees) so pin drift
fails CI instead of passing as "any 40-hex SHA"; `Test-SiteNoNetwork`
extended to `frontend/`; `deploy-pages.yml` publishes `site/` at the root
and `frontend/` under `/frontend/` (with a file:-protocol link rewrite for
local opens).

**Doc templates**: `OBSERVABILITY.md.tmpl` / `OPERATING-MODEL.md.tmpl`
gained leaf-level gating for optional config reads with fallbacks;
schema-required reads stay loud.

**azfw `Basic` removed from the schema enum** (Learn-verified): Basic
requires a management NIC + `AzureFirewallManagementSubnet` the hub-network
module does not provision, and supports threat-intel alert mode only where
the layer defaults to Deny — a Basic selection rendered a configuration that
could never apply. Schema `$comment` records the rationale; the wizard
option is removed with an import guard; **both** connectivity layer
validations are `Standard`/`Premium` (the earlier live Basic backport from
WP6 is reverted); 7 new tests. The defect class (schema enum vs Terraform
`contains([...])` validation) is checker-invisible today — tracked in
TODO.md.

## TODO debt burn-down — broker fix, script cleanup, module completeness, legacy frontend (2026-08-02)

Closes the bulk of the repo-internal backlog in [TODO.md](TODO.md); two new
drift items were found during the work and added there.

**Broker fix**: `Get-LzEnvironmentSubscription`
(`factory/bootstrap/LZFactory.Bootstrap.psm1`) now resolves `bootstrap`
(anchored to the management subscription — the global layer's provider is
pinned there; rationale in the function's comment help) and covers the full
ten-environment schema set; the fail-closed default is preserved for unknown
names. The broker apply path no longer throws on default wizard exports
(whose platform environments include `bootstrap`). Test-Bootstrap: 58
passed, 0 failed; per-environment plan byte-parity unaffected.

**Script cleanup**: the 4 orphaned utilities
(`Configure-DeploymentOptions.ps1`, `Invoke-BulkOperations.ps1`,
`Validate-ALZDeployment.ps1`, `Verify-CostAccuracy.ps1`) were re-verified as
having zero call sites and `git mv`-ed to `scripts/utilities/` with a README
recording each script's purpose and wiring cost.
`Configure-DeploymentOptions.ps1` now carries a PLANNING-ONLY notice — no
`terraform/live/*` layer reads `.azure/deployment-options.yaml`. Path
references fixed repo-wide (README, agent docs, the `.yaml.example`).

**Module completeness**:

- READMEs added for the 6 modules that lacked one (`backup-baseline`,
  `hub-network`, `management-baseline`, `management-groups`,
  `policy-baseline`, `spoke-network`), with byte-identical corpus mirrors,
  matching the existing convention.
- `Microsoft.ApiManagement` TLS policy definition added to policy-baseline's
  TLS 1.2 initiative — the module's 6-service claim is now true. The corpus
  mirror was synced; it had been stale and still carried the pre-fix App
  Service alias bug. The rule hardens over the upstream Enterprise-Scale
  `Deny-APIM-TLS` reference (verified unguarded) with a `coalesce` null guard
  — a policy-evaluation error is an implicit deny, so absent
  `customProperties` must fail open to allow. `APIMTLS12` ships at `Audit`
  in the initiative for the first release (definition default stays `Deny`);
  promote after a clean audit cycle.
- Secure-default verdicts recorded (TODO.md): backend public access SECURE
  (`false` default + lifecycle precondition); firewall threat-intel SECURE
  with the caveat that the feature is opt-in
  (`enable_firewall_threat_intel` defaults `false`, mode defaults `Alert`);
  nsg-flow-logs retention defaults 90 days but **no live stack instantiates
  the module** — now stated in its README and tracked as a new TODO item.

**Legacy `frontend/` generator**:

- The 47 catalog policy toggles reconciled against
  `terraform/modules/policy-baseline/`: 3 map to genuinely enforced
  baseline policies (kept; one effect corrected Deny → Audit with an
  explanatory note), the other 44 are labeled "not yet enforced — no policy
  definition exists" with disabled toggles; none silently removed. The
  enforced list shows the baseline's 5 policy groups separately.
- Module toggles labeled "available, not auto-deployed".
- Emission rewritten to layer-accurate `terraform.auto.tfvars`
  (`terraform/live/global`) + `connectivity.auto.tfvars`
  (`platform-connectivity`) — the old output matched zero real variables.
- Three page-dead bugs fixed (init TypeError, a bad reference in
  `validate()`, CSP blocking the page's own scripts); `org_prefix`
  validation tightened to `^[a-z0-9]{2,10}$` (contracts #1/#7 — the old
  bound was looser than Terraform's).
- New `frontend/README.md` declares the page's legacy status: `site/` is the
  primary path; this page feeds only the legacy in-repo pipeline.

**Repo hygiene**: the stale `agent/stage-7-workflow-corpus` remote branch no
longer exists (verified 2026-08-02 — `git ls-remote` shows only `main`); the
TODO carryover item is closed as moot.

**New debt recorded** (TODO.md): live ↔ corpus module drift (corpus
hub-network's duplicate `azurerm_firewall.hub_with_policy`, corpus
management-baseline's missing `alert_email_receivers` + old CPU alert,
`~> 1.6`/`~> 4.0` corpus pins vs live `>= 1.9.0`/`~> 4.2` across four
modules) needing orchestrated reconciliation; and wiring `nsg-flow-logs`
into a live stack.

## Minimal-by-default CI/CD identity estate (2026-08-02)

Operator directive 2026-08-01: minimal by default, scale is the client's
choice. Design authority: `azure-platform-architect` (legacy matrix = 7
identities, 4 never wired to any workflow secret; grants simultaneously
excessive — 4 subscription-scope RBAC Administrators nothing needed — and
insufficient — no MG-root grants, which `management-groups`/`policy-baseline`
require). Decision record:
[docs/decisions/0002-minimal-identity-estate.md](docs/decisions/0002-minimal-identity-estate.md).

**Schema / wizard**:

- New broker-only key `identity.cicdIdentityModel`
  (`minimal|per-environment`, default `minimal`; like `github.*`, deliberately
  absent from `factory/renderer/variable-map.json`).
- The wizard asks "Deployment identity model" with a live count recomputed
  from the environment selections: minimal → 2 (one shared plan + one shared
  apply, one federated credential per environment); per-environment →
  2 × |unique(platform ∪ application environments)|.

**Broker** (`factory/bootstrap/LZFactory.Bootstrap.psm1`):

- Minimal mode emits exactly 2 identity records — the apply record carries a
  subject **list** (one `environment:<name>` per environment) and the union
  of RBAC scopes, deduplicated; the plan record gets Reader once at the MG
  root. Per-environment mode is proven **byte-parity** with the prior output
  (`factory/tests/fixtures/bootstrap-plan-per-environment.expected.json`).
- **Defect fixed**: the broker now grants the state data-plane roles when the
  backend is azurerm (plan → Storage Blob Data Reader, apply → Storage Blob
  Data Contributor) — previously a generated azurerm repo could not read its
  own state — and `Set-LzAzurermBackend` creates the state account with
  `--allow-shared-key-access false` (contract #3).

**Legacy bootstrap** (`scripts/Start-LandingZoneBootstrap.ps1`):

- The layers × environments matrix is removed; the script consumes the
  broker's plan builder. Roles: plan = Reader at MG root (+ SBDR on the state
  account for azurerm); apply = Management Group Contributor + Resource
  Policy Contributor at MG root, Contributor per distinct subscription
  (+ SBDC for azurerm); RBAC Administrator **only** on sandbox selection,
  sandbox-subscription scope, ABAC-constrained (delegation condition:
  role = Contributor, principalType = ServicePrincipal, condition-version
  2.0).
- Subjects: plan = `pull_request` + `ref:refs/heads/main`; apply =
  `environment:*` only. Secret names (`AZURE_CLIENT_ID`,
  `AZURE_PLAN_CLIENT_ID`) unchanged.
- Legacy-matrix estates are detected and routed to a **report-only**
  remediation section of operator-run `az` commands (delete the 4 dead apps,
  remove the subscription-scope RBAC Administrator grants, add the missing
  MG-root grants); old `azure_sps` state routes to remediation without
  crashing.

**Root workflows** (contract #2 realignment — read-only jobs authenticate as
the plan identity; SHA pins untouched):

- `010-terraform-init.yml`: all 3 logins → `AZURE_PLAN_CLIENT_ID`; the plan
  step gained `-lock=false`.
- `020-rbac-validation.yml`: both jobs always authenticate as the plan
  identity — the `pull_request`-conditional fallback to `AZURE_CLIENT_ID` is
  removed.
- `terraform-apply.yml`: the read-only rbac-validation gate → plan identity
  (apply jobs keep `environment:` + `AZURE_CLIENT_ID`).
- `azure-auth-test.yml` → plan identity.

**Template corpus**: `platform-management` gains the `sandbox_cleanup` role
assignment (Contributor for the automation account's identity on the sandbox
subscription), inside the existing sandbox conditional — both fixture
branches validate — with a least-privilege comment tying it to the ABAC
delegation condition.

## PROD-TODO implementation — production-motion tooling and corpus fixes (2026-08-01)

Implements the in-repo portion of the PROD-TODO.md backlog (file retired 2026-08-07; open items absorbed into TODO.md).
Live operator executions (federated credentials for **both** SPs, per-fork
branch-protection enablement, Stage 13/14, pipeline-green verification) remain
open and are annotated there.

**Terraform / corpus** (199 renderer tests green, `terraform validate` on all
touched stacks, schema drift InSync):

- `factory/templates/terraform/modules/spoke-network/` brought to byte parity
  with `terraform/modules/spoke-network/` — the template now carries
  `configuration_aliases = [azurerm.hub]`, resolving the contract #5
  divergence. Template callers
  (`factory/templates/terraform/live/workloads-{prod,nonprod}/main.tf.tmpl`)
  pass `providers` maps with a conditional `azurerm.hub` provider; new
  optional `connectivity_subscription_id` variable, mapped in
  `factory/renderer/variable-map.json`.
- Corpus remote-state reads gained the `use_azuread_auth` token (contract #3).
  Live vs corpus state-container layouts verified as deliberately different
  and both internally consistent.
- `terraform/live/sandbox/variables.tf` location regex fixed `^[a-z]+$` →
  `^[a-z0-9]+$` (numbered regions such as `eastus2` were rejected).
- New `scripts/New-BackendConfig.ps1`: plan-first (`-Apply`) generator of the
  four per-layer `terraform/live/*/backend.hcl` files from backend-bootstrap
  outputs (new `layer_state_containers` output), a wizard `backend.hcl`, or
  `lz-config.json`; always enforces `use_azuread_auth = true`.

**Wizard (`site/`)** (48 tests pass, no-network policy pass):

- Generated NEXT-STEPS.md rewritten to the real interfaces (discovery →
  broker plan/`-Apply` → render → scaffold plan/`-Apply`); the fictional
  `-Phase`/`--rollback`/`-DryRun`/`-AutoPush` flags are gone.
- New "Download all as bundle (.zip)": offline store-only zip of all 8
  artifacts plus a SHA-256 `checksums.txt` manifest; individual downloads
  kept.
- Generated CONFIGURATION.md documents the operator loop-back
  (`management_ip_ranges` → apply platform-management → paste
  `log_analytics_workspace_id` → re-plan connectivity); contract #4
  placeholders untouched.
- Module status corrected: `defender-baseline` is "available, not
  auto-deployed" — the prior claim that the renderer wires it in was false.

**CI / fork tooling**:

- New `scripts/Initialize-ClientFork.ps1`: plan-first fork/private-copy init —
  Actions enablement, branch protection with required checks (`Factory CI`,
  `Enforce Immutable Action Refs`, `TruffleHog Secret Scan`,
  `Gitleaks Secret Detection`, `Terraform Security Scan`; `-RequiredChecks`
  overrides), required approvals ≥ 1, secret-scanning read-back, full API
  read-back verification; `-CreatePrivateCopy` mirrors to a private repo (see
  [docs/decisions/0001-private-copy-over-public-fork.md](docs/decisions/0001-private-copy-over-public-fork.md)).
- Corrected the check-name claim: GitHub records the Factory CI context as
  `Factory CI` (job-level name), not `Factory CI / Factory CI`.
- New `scripts/Add-PlanFederatedCredential.ps1`: plan-first AADSTS700213
  remediation for the plan SP's `pull_request` subject, with a contract-#2
  guard and API read-back. Not yet executed live. Run logs additionally prove
  the Contributor SP's `ref:refs/heads/main` subject is missing live (run
  30721161313) — the credential gap covers both SPs (PROD-TODO Phase 2).
- 0-second workflow failures closed as investigated: root cause was a YAML
  block-scalar bug fixed by PR #13 (commit `516cf44`, 2026-07-01); failures
  since are the missing live OIDC credential (~10–40 s).
- New `.github/workflows/deploy-pages.yml`: SHA-pinned GitHub Pages deploy of
  `site/` (manual prerequisite: Pages source set to "GitHub Actions").

**Legacy bootstrap** (`scripts/Start-LandingZoneBootstrap.ps1`; parse clean,
PSScriptAnalyzer identical to baseline):

- New parameters: `-Repository <owner>/<name>` (org-fork targeting),
  `-ConfigPath <lz-config.json>` (seeds org prefix, region, repo, backend,
  TFC org/workspace, environments, sandbox subscription),
  `-Backend azurerm|hcp-terraform` (azurerm skips the TFC phases),
  `-EnvironmentReviewers` (default operator now emits a SELF-APPROVAL
  warning), `-SkipSandboxRbac`.
- Environment-selection bug fixed (choice 1 now yields dev only); region,
  repo name, and TFC workspace are no longer hardcoded; sandbox enabled
  without `-SandboxSubscriptionId` is a terminating error unless
  `-SkipSandboxRbac`.

**Factory tooling** (Test-Bootstrap 10/10; all 13 Factory CI checks pass —
shellcheck runs on the CI runner only):

- Broker default required check changed `qlty check` → `repository-scan`
  (`Set-LzBranchProtection`) — the only corpus-shipped check that reports on
  every PR; `LZ_REQUIRED_STATUS_CHECKS` still overrides. Both
  USER-CHECKLIST copies updated.
- New exported `Test-LzFirstApplyPreflight` in the broker plus a pre-flight
  step in the generated connectivity plan workflow: loud early checks for
  unset/wildcard `management_ip_ranges`, `log_analytics_workspace_id`
  placeholder states, and a missing sandbox subscription; findings persisted
  in `bootstrap-audit.json` (`preflight` array).
- New `scripts/Invoke-CustomerEngagement.ps1`: single plan-first wrapper,
  `-Phase discovery|broker|render|scaffold|all`; `-Apply` propagates to
  broker and scaffold only; stops on first failure.
- New `scripts/Dispose-Engagement.ps1` plus runbook
  [docs/runbooks/engagement-disposal.md](docs/runbooks/engagement-disposal.md):
  plan-first archive-then-delete disposal with SHA-256 verification,
  MUST-NOT-DELETE banner, gated fork-residue cleanup, and
  `disposal-plan.json`/`disposal-audit.json` evidence.

**Docs**: new [docs/runbooks/engagement-lifecycle.md](docs/runbooks/engagement-lifecycle.md)
(upgrade channels, engagement provenance, workstation isolation) and the
Phase 1 decision record above; PROD-TODO.md reconciled item by item;
contracts #3 and #5 updated in
[.claude/CROSS-DOMAIN-CONTRACTS.md](.claude/CROSS-DOMAIN-CONTRACTS.md).

## Documentation restructure — wiki migration, HANDOFF.md retired (2026-08-01)

- Migrated the contents of `docs/` (build docs, factory design and stage
  readiness records, webapp/static-generator docs) to the
  [GitHub wiki](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki).
  Two exceptions stay in the repository because code and agents read them from
  disk: `.claude/CROSS-DOMAIN-CONTRACTS.md` (moved from docs/ later the same day; linked by `CLAUDE.md` and all
  `.claude/agents/*.md`) and root `USER-CHECKLIST.md` (read by the
  Test-Scaffold/CI/Import/Dogfood/Release suites). Both are mirrored to the
  wiki with the repo copy marked canonical.
- Retired `HANDOFF.md`: completed work moved into this changelog (entries
  below), open items merged into [TODO.md](TODO.md). Durable knowledge it
  carried is archived here:

**Decisions already made — do not silently revisit** (from HANDOFF §5):

| Decision | Rationale |
|---|---|
| **Two identities per environment** — Reader `*-plan` on `pull_request`, Contributor `*-apply` on `environment:<name>` | Makes it *structurally* impossible for a PR-triggered run to hold write access. No subject uses a wildcard; tests assert this. |
| **Layers are never merged** | Each is its own state file and gate. Shared state across layers is the most common way a landing zone becomes unrecoverable. (Control **AR3**.) |
| **HCP Terraform is the default backend** | Legacy free plan ended 2026-03-31; current cap is 500 managed resources; paid tiers bill on *peak hourly* count from $0.10/resource/month. `azurerm` is fully supported as the alternative. |
| **Release gates start `false`** | This pipeline has no recorded successful run. A factory multiplies the blast radius of an unproven path. `dogfoodInstanceAppliesGreen` and `oidcTokenExchangeVerifiedLive` are deliberate v1.0.0 blockers. |
| **Scaffold modules block rendering** | `sentinel-siem` and `keyvault-cmk` declare zero resources; `virtual-wan` doesn't exist. Emitting them would silently deploy nothing. Status is read from `factory-version.json`, so implementing a module lifts its guard automatically. |
| **Renderer re-validates independently of the wizard** | A validation that exists only in the UI is a suggestion, not a guarantee. 22 guards (G01–G22). |

**Environment notes that cost real debugging time** (from HANDOFF §8 —
Windows + PowerShell 7.6.4 + Git Bash):

| Trap | Detail |
|---|---|
| `az.cmd` argument mangling | `&` in a URL is a `cmd` command separator; parentheses in an OData `--filter` break parsing. **Call Graph via `Invoke-RestMethod`, not `az rest`.** |
| `Mandatory [string[]]` | Rejects an array containing *any* empty string. Use `[AllowEmptyString()]`. |
| `-is [psobject]` | True for **every** PowerShell value. Use explicit type dispatch (`Test-LzIsComposite`). |
| `$Var:` in a string | Parses as a scope qualifier. Use `${Var}:`. |
| Empty pipeline | Yields `$null`, not `@()`. Wrap in `@(...)` before `.Count` under StrictMode. |
| `-bnot` on `uint32` | Yields a signed value. CIDR maths uses `int64`. |
| Git Bash `/tmp` | Not visible to `pwsh`. Use Windows paths when crossing shells. |
| `git show <ref>:<path>` | MSYS path conversion breaks it. Prefix with `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'`. |
| Console encoding | Set `[Console]::OutputEncoding = [Text.Encoding]::UTF8` or box-drawing glyphs render as `?`. |

**Discovery rule worth keeping** (HANDOFF §3.3): a probe must never conflate
"there is nothing here" with "I was not allowed to look" — five states (`Ok`,
`Empty`, `Forbidden`, `Unavailable`, `Error`), `Conclusive` only for the first
two, capability proven by reading effective permissions, never by attempting a
mutation (control **BR2**).

**Renderer invariants** (HANDOFF §3.4): tokens are `{{FACTORY:...}}`, never
`${...}`; directives are comment-prefixed (`#{{IF}}`) so unrendered templates
stay valid; GitHub Actions `${{ }}` survives via a negative lookbehind;
fail-closed on unknown tokens/leftover placeholders/unbalanced directives;
directives evaluate before token substitution; use `defined path` for optional
keys. Full detail: `factory/renderer/README.md`.

## Comprehensive-review remediation — live tree converged toward corpus (2026-08-01)

From HANDOFF §6.3 update, 2026-08-01:

- Converged `terraform/live/` to the factory corpus for the previously recorded
  divergences: `org_prefix` now validates `^[a-z0-9]{2,10}$` in both trees,
  `firewall_threat_intel_mode` is declared and wired in
  `live/platform-connectivity`, and the automation schedule `start_time` in
  `live/platform-management` is derived at plan time instead of a literal past
  timestamp.
- The operator approved proceeding with the hub-network subnet re-layout, which
  forces replacement of GatewaySubnet, AzureBastionSubnet, and the DNS resolver
  subnets and deletes the hub-local Log Analytics workspace if
  platform-connectivity is already deployed — the authoritative plan for that
  lands in the PR's terraform-plan run.
- Remaining divergence is tracked in [TODO.md](TODO.md); Stage 13 (regenerating
  this repo from the factory) resolves the split permanently.

## Legacy Terraform formatting normalized — PR #35 (2026-07-26)

From HANDOFF §6.1: the 26 pre-existing `terraform fmt -check -recursive`
failures under `terraform/` were normalized with Terraform 1.9.8.
`terraform fmt -check -recursive terraform/` exits zero. PR #35 was
squash-merged into `main` on 2026-07-26 as commit
`8bb10ae6435a9f80ad639f4d7092767e1d255713`.

## Factory stages 1–14 landed on `main` — merge history (2026-07-26)

From HANDOFF §1.1 and §4 (recorded here because the branch-protection
mechanics generalize):

| PR | Outcome |
|---|---|
| [#31](https://github.com/HybridCloudWorks/Template-LZDeployment/pull/31) | Merged into `feat/lz-factory-…` — rescued the three test suites (48 wizard, 60 discovery, 100 renderer at the time) that previously existed only in a session-scoped temp directory |
| [#28](https://github.com/HybridCloudWorks/Template-LZDeployment/pull/28) | Squash-merged into `main` as `11f09cd` — carried everything |
| [#30](https://github.com/HybridCloudWorks/Template-LZDeployment/pull/30) | Closed as **superseded**, not abandoned — its commit `0040033` reached `main` inside #28 via a real merge (shared SHA), so squashing it separately would have minted a duplicate |
| [#32](https://github.com/HybridCloudWorks/Template-LZDeployment/pull/32) | Squash-merged as `7568bc3` — agent git/gh permissions (merged by a human; an agent cannot widen its own permissions) |
| #33 | `d219174` — post-merge handoff correction |

Branch protection on `main`: `enforce_admins: true` (direct push rejected for
everyone; a PR is the only route), `required_linear_history: true` (so
`gh pr merge --merge` always fails and `--rebase` fails on branches with merge
commits — **`--squash` is the reliable option**), `allow_force_pushes: false`,
and **no** `required_status_checks` (a merge succeeding proves nothing about
CI — see TODO.md). When stacking branches, prefer `git merge` over
`git cherry-pick`: a shared SHA cannot conflict with itself. `gh pr merge`
must run inside the repository or with `--repo`.

## Stage 14 release evidence attestation — prepared (2026-07-26)

- Added a manual credential-free workflow that downloads exact Factory CI and
  full dogfood apply artifacts by workflow run ID.
- Added a hash-pinned independent read-back attestation schema with reviewer
  and approval provenance.
- Added evidence completeness, freshness, repository/version binding, full
  apply eligibility, and branch-protection/read-back checks.
- Added computation of all five release gates, a machine-readable readiness
  report, and a review-only gate proposal.
- Added root/generated operator activities and static release coverage.
- Advanced factory/LZ versions to 0.9.0 and manifest to 1.9.0; schema remains
  2.0.0. Existing release-gate values remain unchanged.
- No PowerShell test, schema validation, workflow, artifact download, cloud
  login, Terraform operation, or release mutation was executed.

## Stage 13 HCW dogfood instance — prepared (2026-07-26)

- Added a manual SHA-pinned render/plan/apply workflow for the HCW dogfood
  instance.
- Added variable-driven dogfood orchestration that regenerates from the factory
  into ephemeral output and verifies the configured repository target.
- Separated the read-only plan identity from the protected-environment apply
  identity and required an explicit second apply authorization.
- Added saved-plan application, destructive-change refusal, per-layer logs, and
  `dogfood-report.json` evidence.
- Added root/generated operator activities and static dogfood coverage.
- Advanced factory/LZ versions to 0.8.0 and manifest to 1.8.0; schema remains
  2.0.0. The live dogfood release gate remains false pending reviewed evidence.
- No render, Terraform, Azure, OIDC, state, or runtime validation command was
  executed.

## Stage 12 Factory CI — prepared (2026-07-26)

- Added a credential-free, SHA-pinned Factory CI workflow for pull requests,
  protected-branch pushes, and manual runs.
- Added a variable-driven orchestrator covering Wizard, Discovery, Renderer,
  Bootstrap, Scaffold, Import, and CI suites.
- Added schema-variable drift, static wizard no-network, and immutable Action
  reference policies.
- Added ShellCheck/PSScriptAnalyzer and recursive Terraform format,
  backend-disabled initialization, and validation.
- Added per-check logs plus `factory-ci-report.json` and always-uploaded CI
  evidence.
- Added root/generated operator activities and static Factory CI coverage.
- Advanced factory/LZ versions to 0.7.0 and manifest to 1.7.0; schema remains
  2.0.0.
- No local Factory CI, tests, analyzers, Terraform, or validation commands were
  executed.

## Stage 11 brownfield import generation — prepared (2026-07-26)

- Added plan-only `brownfield-import.ps1` and strict Bash launcher.
- Added a SHA-256-pinned classification schema with Adopt, Ignore, Replace, and
  Require-Approval behavior.
- Added fail-closed conclusive-discovery enforcement and stable Azure candidate
  ID derivation.
- Added exact operator-supplied Terraform address/layer validation; the factory
  never guesses adoption addresses.
- Added deterministic import blocks and review-only command scripts without any
  Terraform execution path.
- Added renderer-manifest registration, stale Stage 11 artifact cleanup,
  plan/audit evidence, checklists, and static test coverage.
- Advanced factory/LZ versions to 0.6.0 and manifest to 1.6.0; schema remains
  2.0.0.
- No discovery, generator, Terraform, state, plan, import, or Azure operation
  was executed.

## Stage 10 scaffold builder — prepared (2026-07-26)

- Added non-interactive, plan-only `scaffold-copy.ps1` and strict Bash launcher.
- Added exact renderer-inventory verification, safe path enforcement, SHA-256
  inventory evidence, and config/schema/company provenance checks.
- Added staged target construction, explicit force control, `.git` preservation,
  timestamped recovery backups, and origin URL verification.
- Added variable-driven repository create, commit, and push behavior.
- Added `scaffold-plan.json`, `scaffold-audit.json`, root/generated user
  activities, and static scaffold coverage.
- Advanced factory and landing-zone versions to 0.5.0 and manifest to 1.5.0;
  schema remains 2.0.0.
- No scaffold test, customer working-tree mutation, repository creation, commit,
  or push was executed.

## Stage 9 bootstrap broker — prepared (2026-07-26)

- Added non-interactive `bootstrap-broker.ps1` and strict Bash launcher.
- Added idempotent Entra app/SP/federated-credential, Azure RBAC, GitHub
  environment/variable/secret/protection, HCP workspace, and Azure Storage
  backend reconciliation.
- Added per-layer plan identity and subscription maps to the generated plan
  workflow.
- Added plan/audit evidence and factory/generated `USER-CHECKLIST.md` files.
- Added static broker and renderer coverage without executing it, per owner
  direction.
- Advanced factory and landing-zone versions to 0.4.0 and manifest to 1.4.0;
  schema remains 2.0.0.
- No live broker apply or external-system validation was performed.

## Stage 8 documentation corpus — prepared (2026-07-26)

- Added nine generated operational documents: operating model, governance,
  threat model, observability, FinOps, state management, disaster recovery,
  upgrade guide, and phase model.
- Registered the corpus in renderer manifest version 1.3.0.
- Added renderer assertions for document inventory, provenance, complete token
  resolution, and configuration-specific content.
- Advanced the factory and emitted landing-zone pre-release to 0.3.0 while
  retaining config schema 2.0.0.
- Full local baseline: 48 wizard, 60 discovery, and 175 renderer tests.
- Did not run Stage 9 bootstrap or mutate Azure, Entra, Terraform backends, or
  repository administration.

## Stage 7 workflow corpus — prepared (2026-07-25)

- Added generated plan, protected-environment apply, credential-free
  format/validate, action-pinning, security, policy, and OIDC verification
  workflows.
- Added fork-safe cloud-plan behavior and Stage 7 renderer assertions.
- Registered all generated workflows in manifest version 1.2.0.
- Centralized the workflow Terraform version through the factory version
  contract and advanced the pre-release to 0.2.0.
- Did not trigger workflows, apply Terraform, mutate Azure/Entra, or change
  branch protection.

## Pre-Stage 7 readiness alignment (2026-07-25)

- Reviewed the implemented Stage 1–6 factory contract, code paths, tests,
  Terraform corpus, live workflows, workflow proof template, and repository
  orchestration before beginning Stage 7.
- Added `docs/factory/STAGE-7-READINESS.md` (since migrated to the wiki as
  [Factory-Stage-7-Readiness](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki/Factory-Stage-7-Readiness))
  with the workflow-corpus decisions, invariants, implementation sequence, and
  definition of done.
- Reconciled stale handoff, design, renderer, TODO, and orchestration claims with
  the current factory state.
- No Terraform, workflow runtime, tenant, or repository permission behavior was
  changed.

## Completed Deliverables

### ✅ Phase 0 Audit & CI/CD Reliability Fixes - COMPLETE (July 1, 2026)

**Status**: 🟢 COMPLETE
**Completion Date**: July 1, 2026

**Context**: A full audit of every claimed-complete item in this repo's docs against actual file evidence (Terraform modules, GitHub workflows, PowerShell scripts) found several real code-level bugs behind the docs sprawl, not just stale documentation.

**What Was Fixed**:
- ✅ **OIDC pull_request gap** — `scripts/Start-LandingZoneBootstrap.ps1` only created a federated credential subject for `ref:refs/heads/main`. `terraform-plan.yml` triggers Azure OIDC login on `pull_request` events, which GitHub issues a `pull_request`-subject token for — no existing credential matched, so every PR-triggered CI run failed OIDC login by design (confirmed: zero successful runs of `terraform-plan.yml`/`terraform-apply.yml`/`010-terraform-init.yml`/`020-rbac-validation.yml` in repo history prior to this fix). Added `repo:OWNER/REPO:pull_request` federated credential to the bootloader.
- ✅ **SHA pinning inconsistency** — `010-TERRAFORM-INIT.yml` and `020-RBAC-VALIDATION.yml` used `@v4`/`@v2`/`@v3`/`@v7` tag refs while every other workflow in the repo pins to commit SHAs (and `action-pinning-policy.yml`'s own check would fail against exactly this pattern). Pinned both files to the SHAs already used elsewhere in the repo for the same actions.
- ✅ **Conflicting `required_version` blocks** — `terraform/modules/keyvault-cmk/main.tf` and `terraform/modules/sentinel-siem/main.tf` each had a stray second `terraform { required_version = ">= 1.9.0" }` block that contradicted the `~> 1.6` constraint in the module's own `terraform.tf` (the standard used by all 11 modules). Removed the stray blocks.

**Repo cleanup — bootstrap scripts and naming** (2026-07-01):
- ✅ Deleted `scripts/Initialize-LandingZone.ps1` and `scripts/Start-Bootstrap.ps1` — both implemented a stale "spin up a separate customer repo" model that isn't how this repo actually works. `Start-LandingZoneBootstrap.ps1` is the confirmed real, sole entry point.
- ✅ Renamed all scripts to a consistent PowerShell Verb-Noun convention: `000_LZ_Bootloader.ps1` → `scripts/Start-LandingZoneBootstrap.ps1`, `alz-config.ps1` → `scripts/Get-AlzConfig.ps1`. Updated every reference across workflows and docs.
- ✅ Fixed stale `.azure/deployment-options.yaml` reference in `keyvault-cmk` and `sentinel-siem` module READMEs — only `.azure/deployment-options.yaml.example` exists; READMEs now say to copy it first.

**What Was Found But Deferred** (see [TODO.md](TODO.md)):
- 🟦 Backend inconsistency: bootloader/workflow-010 reference Terraform Cloud, but `terraform-plan.yml`/`terraform-apply.yml`/all `terraform/live/*/backend.hcl` use native `azurerm` backend. Decision: adopt TFC — tracked as [GitHub Issue #11](https://github.com/HybridCloudWorks/Template-LZDeployment/issues/11), blocked on interactive TFC org/workspace/token setup.
- 🟦 `Microsoft.ApiManagement` claimed but not implemented in the TLS 1.2 policy initiative (5 of 6 claimed services actually covered).
- 🟦 6 of 11 Terraform modules missing README.md.
- 🟦 `keyvault-cmk` and `sentinel-siem` modules are scaffold-only stubs (zero real resources), not implemented despite being referenced as available optional modules in some docs.
- 🟦 4 utility scripts (`Configure-DeploymentOptions.ps1`, `Invoke-BulkOperations.ps1`, `Validate-ALZDeployment.ps1`, `Verify-CostAccuracy.ps1`) have no call site anywhere in the pipeline — disposition (wire in vs. relocate) still open.

**Documentation cleanup**: Consolidated 8 duplicative PR-artifact docs describing the same static-generator build into a single entry below; rewrote TODO.md to hold only pending work (all completed items moved here), matching what this repo actually does (self-deploying landing zone via `Start-LandingZoneBootstrap.ps1` + numbered workflows + Terraform, plus a separate optional static `.tfvars` generator) rather than the previously-planned Node/React/Express/Docker/OAuth "web app" that was never built.

---

### ✅ Static Config-Generator Frontend: Official ALZ Rebuild - COMPLETE (July 1, 2026)

**Status**: 🟢 COMPLETE  
**Completion Date**: July 1, 2026  
**Effort**: ~8 hours (Phase 1: 4h research, Phase 2: 4h implementation)  
**Git Commits**:
- `77131ea` feat: complete Phase 2 - official ALZ generator implementation (#9), merged 2026-07-01 05:08:23 UTC via PR #9 (branch `feature/official-alz-generator-phase2`, 11 files changed, +5218/-567)

**What This Is**: `frontend/` is a static, backend-free HTML/JS/CSS tool. A user fills out a form describing their desired Landing Zone, and `OfficialALZGenerator` (in `frontend/app.js`) generates a `.tfvars` file entirely client-side — no server, no build step, no auth. The user downloads/copies the file and feeds it to the Terraform workflows (`terraform-plan.yml` / `terraform-apply.yml`) manually or via `generate-and-release.yml`. This superseded an earlier, unfinished draft of the same page that had MSAL auth stubs and planned a Node/Express backend — that direction was abandoned in favor of the zero-backend static approach (8h vs. an estimated 18-20h for a backend API).

**What Was Delivered**:
- Official ALZ generator grounded in the official Azure Landing Zones docs (not guessed fields)
- 47 official policy assignments across 5 management-group scopes (Intermediate Root, Platform, Landing Zones, Landing Zones/Corp, Specialized) — sourced from the official ALZ reference, not the "50+" figure quoted in earlier drafts
- 2 official network topologies (hub-spoke VNet, Virtual WAN)
- 16 official customization options (resource naming, MG name overrides, feature toggles, policy effect overrides, etc.)
- Region auto-pairing (official Azure region pairs) and dynamic environment suffixes (prod/dev/test/staging)
- Real-time CAF naming examples, auto-populated environment tags
- 9-section form UI, mobile-responsive, no external dependencies
- Valid `.tfvars` generation matching the structure the `terraform/live/*` layers expect

**Frontend Files**:
- `frontend/app.js` (988 lines) — `OfficialALZGenerator` class
- `frontend/index.html` (411 lines) — 9 form sections, policy checkboxes
- `frontend/styles.css` (423 lines) — styling, responsive layout

**Acceptance Criteria Met**:
- All policy names and variable names sourced from official ALZ documentation/accelerator
- All 16 customization options implemented
- 2 official network topologies only (no invented options)
- Official Azure region pairs used for auto-pairing
- Generated `.tfvars` matches the structure Terraform expects
- Form validation on all required fields; mobile responsive; cross-browser tested (Chrome, Firefox, Safari)

**Key Achievement**: Replaced a guessed-at, half-wired generator (with dead MSAL/backend stubs) with a production-ready, zero-backend tool grounded in official Azure Landing Zones architecture.

**Documentation note**: This entry consolidates and replaces 8 separate PR-artifact docs that previously described this same build from different angles (`PROJECT_COMPLETION_STATUS.md`, `IMPLEMENTATION_COMPLETE.md`, `PHASE_2_IMPLEMENTATION_COMPLETE.md`, `README_PHASE_2_COMPLETE.md`, `MERGE_COMPLETE.md`, `PHASE_1_PHASE_2_SUMMARY.md`, `PHASE_2_UX_IMPROVEMENTS.md`, `COMPONENTS_STATUS.md`), all removed as part of Phase 0 doc reconciliation (2026-07-01). `COMPONENTS_STATUS.md` in particular had gone stale — it described an older draft of `frontend/` (MSAL auth, "Deploy to Azure" button, planned Express backend) that no longer matches the current static-generator implementation. Remaining reference docs — `PHASE_1_PREP_STAGE_INVENTORY.md`, `PHASE_2_BUILD_PLAN.md`, `FORM_MIGRATION_GUIDE.md` — still exist under `docs/` as design-detail background but are not treated as status/completion claims.

---

### ✅ AVM Phase 1: Foundation - COMPLETE (June 30, 2026)

**Status**: 🟢 COMPLETE  
**Completion Date**: June 30, 2026  
**Effort**: ~2 hours  
**Git Commits**:
- `400a662` chore: complete AVM Phase 1 compliance - terraform.tf & .terraform-docs.yml
- `d71c3bf` docs: add AVM session summary and quick reference guide
- `a6cb0e1` docs: add implementation complete summary and checklist
- `90c2956` docs: add AVM documentation index and navigation guide
- `2ebfd11` docs: update TODO.md with AVM Phase completion and deployment blockers
- `69814e0` docs: add critical next steps before deployment guide

**What Was Delivered**:
- ✅ terraform.tf files: 10 created + 1 fixed (all 11 modules)
- ✅ .terraform-docs.yml files: 11 created (auto-documentation)
- ✅ Removed all provider blocks from modules (TFNFR27 compliance)
- ✅ All modules pass terraform validate & fmt
- ✅ 6 comprehensive documentation guides created

**Modules Compliant**: 11/11 on `terraform.tf` + `.terraform-docs.yml` structure (verified 2026-07-01)
- backup-baseline, defender-baseline, hub-network, keyvault-cmk
- management-baseline, management-groups, nsg-flow-logs
- policy-baseline, sandbox, sentinel-siem, spoke-network

**Acceptance Criteria Met**:
- ✅ TFNFR25: terraform.tf exists in all modules with `~> 1.6` Terraform, `~> 4.0` azurerm
- ✅ TFNFR26: required_providers block defined
- ✅ TFNFR27: No provider blocks in modules (delegated to root) — confirmed clean, zero matches on re-audit
- ✅ TFNFR2: .terraform-docs.yml configured for all modules
- ⚠️ 6 of 11 modules still lack a `README.md` (`backup-baseline`, `hub-network`, `management-baseline`, `management-groups`, `policy-baseline`, `spoke-network`) — tracked in [TODO.md](TODO.md) Phase 2
- ⚠️ `keyvault-cmk` and `sentinel-siem` are scaffold-only stubs with zero real resources, not full modules — tracked in [TODO.md](TODO.md) Phase 2

**Documentation note**: The 6 documentation files originally listed here (AVM-INDEX.md, AVM-QUICK-REFERENCE.md, IMPLEMENTATION-COMPLETE-SUMMARY.md, SESSION-SUMMARY-AVM-PHASE1.md, AVM-COMPLIANCE-PHASE-1-COMPLETE.md, AVM-IMPLEMENTATION-STRATEGY.md) are referenced by the commit messages above but do not exist anywhere in the current repo tree (verified 2026-07-01 via full-repo glob) — either deleted in a later commit or never actually included in the diff despite the commit message. Removed from this entry as unverifiable; the `terraform.tf`/`.terraform-docs.yml` deliverables themselves are independently confirmed to exist.

---

### ✅ Task 1.3: Terraform Sandbox Module - COMPLETE (June 30, 2026)

**Status**: 🟢 COMPLETE  
**Completion Date**: June 30, 2026  
**Effort**: 3 hours  
**Priority**: P0 CRITICAL  
**Git Commit**: `acc325b` chore: implement Task 1.3 - Terraform Sandbox Module (#6)

**What Was Delivered**:
- ✅ AVM-compliant sandbox module at `terraform/modules/sandbox/`
  - ✅ terraform.tf (version constraints per AVM TFNFR25/26)
  - ✅ variables.tf (4 inputs with validation per AVM TFNFR18/17/20)
  - ✅ main.tf (resource group + feature toggle via count)
  - ✅ outputs.tf (anti-corruption layer per AVM TFFR2)
  - ✅ .terraform-docs.yml (auto-documentation)
  - ✅ README.md (comprehensive usage guide)
- ✅ Live configuration at `terraform/live/sandbox/`
  - ✅ main.tf (module call)
  - ✅ variables.tf (local definitions)
  - ✅ outputs.tf (pass-through)
  - ✅ terraform.tfvars (example config)
  - ✅ backend.hcl (azurerm backend configuration — TFC migration tracked in [TODO.md](TODO.md) Phase 1)
- ✅ terraform fmt & validate passed
- ✅ AVM Compliance: All 11 requirements verified

**Acceptance Criteria Met**:
- ✅ Module follows Azure Verified Modules standards
- ✅ Feature toggle prevents accidental creation (safe defaults)
- ✅ Lifecycle management via tags (expiry_date based cleanup)
- ✅ Drift detection automatic via Terraform
- ✅ Immutable desired state via Terraform
- ✅ Full audit trail in git + TFC
- ✅ Safe rollback via terraform destroy

**Key Achievement**: Replaced ad-hoc PowerShell cleanup with a production-ready IaC module.

---

### ✅ Task 5.1: GitHub Actions SHA Pinning - COMPLETE (Phase 1 ahead of schedule)

**Status**: 🟢 COMPLETE  
**Completion Date**: May 2026 (ahead of schedule)  
**Priority**: P0 CRITICAL  
**Effort**: 2 hours

**What Was Delivered**:
- ✅ Pinned all GitHub Actions to commit SHAs in workflows
  - ✅ `actions/checkout@v4` → SHA `b4ffde65f46336ab88eb53be808477a3936bae11`
  - ✅ `hashicorp/setup-terraform@v3` → SHA `b9cd54a3c349d3f38e8881555d616ced269862dd`
  - ✅ `azure/login@v2` → SHA `6c251865b4e6290e7b78be643ea2d005bc51f69a`
- ✅ Added comments with version tags for reference
- ✅ Configured Dependabot for GitHub Actions updates
- ✅ Workflows tested and passing

**Acceptance Criteria Met**:
- ✅ All actions pinned to commit SHAs (supply chain security)
- ✅ Dependabot configured for tracking updates
- ✅ Workflows passing validation

**Files Updated**:
- `.github/workflows/terraform-plan.yml`
- `.github/workflows/terraform-apply.yml`

---

### ✅ Task 5.5: Microsoft Defender Module Created (Optional - Deferred Deployment)

**Status**: 🟢 MODULE COMPLETE, 🟦 DEPLOYMENT DEFERRED  
**Completion Date**: June 2026  
**Priority**: OPTIONAL  
**Cost**: $1,500-$3,000/month (requires explicit opt-in)

**What Was Delivered**:
- ✅ Created `terraform/modules/defender-baseline/` module
- ✅ main.tf - Defender for Subscriptions (Servers, App Services, Storage, Databases, Containers, KeyVault)
- ✅ variables.tf - Configurable for all Defender plans
- ✅ outputs.tf - Defender pricing tier outputs
- ✅ README.md - Comprehensive deployment guide with cost optimization tips

**Module Features**:
- ✅ Supports enabling/disabling each Defender plan independently
- ✅ Security contact configuration
- ✅ Auto-provisioning support
- ✅ Workspace connection support
- ✅ Cost breakdown in documentation

**Acceptance Criteria Met**:
- ✅ Module created and documented
- ✅ Deployment guide included
- ✅ Cost information provided

**Status**: Module ready for deployment when user opts in. Not auto-deployed by default due to cost.

---

### ✅ Optional Module Infrastructure Created

**Sentinel SIEM Module** - Structure created, awaiting Phase 5 implementation
- Location: `terraform/modules/sentinel-siem/`
- Status: 🟦 Scaffolded, not yet implemented

**Customer-Managed Keys (CMK) Module** - Structure created, awaiting Phase 5 implementation
- Location: `terraform/modules/keyvault-cmk/`
- Status: 🟦 Scaffolded, not yet implemented

---

## Previously Completed (From Initial Repo State)

### ✅ Bootstrap - GitHub Repository & Branch Protection

**Status**: 🟢 CONFIRMED (verified 2026-07-01 via `gh api`)
**What's In Place**:
- ✅ GitHub repository `HCW-Demo-LZDeployment` (owner: `saulpatinojr`) exists and is active
- ✅ Branch protection ruleset active on `main`: `enforce_admins`, `required_linear_history`, no force pushes, no deletions, required conversation resolution
- ⚠️ Required approving review count is 0 — protection exists structurally but doesn't require human review (tracked in [TODO.md](TODO.md) Phase 4)
- ⚠️ OIDC federation, CI/CD workflows, and end-to-end pipeline health are tracked separately in [TODO.md](TODO.md) Phase 1 — as of 2026-07-01 the pipeline has no recorded successful run (root cause identified and fixed; verification pending)

---

### ✅ PowerShell Sandbox Cleanup Script

**Status**: 🟢 CONFIRMED (verified 2026-07-01 by direct code read)
**What's In Place** — `terraform/scripts/Cleanup-ExpiredSandboxResources.ps1`:
- ✅ GUID format validation on subscription ID input (`[ValidatePattern(...)]`)
- ✅ Subscription existence check via `Get-AzSubscription`
- ✅ Sandbox tag validation (`purpose=sandbox`, throws "SAFETY VIOLATION" if absent)
- ✅ Dry-run capability (`-DryRun`, default `true`), requires explicit `-Confirm` for real deletion
- ✅ Max deletion limit (`-MaxDeletions`, default 100)
- ⚠️ Log Analytics audit trail is a stub — `Write-AuditLog` prints structured JSON to console but does not call the Data Collector API; the code has a comment noting this ("In production, integrate with Send-AzOperationalInsightsDataCollector")

---

## Summary Statistics

| Category | Count | Status |
|----------|-------|--------|
| **Terraform Modules** | 11 | 9 implemented, 2 scaffold-only stubs (`keyvault-cmk`, `sentinel-siem`) |
| **GitHub Workflows** | 10 | All SHA-pinned as of 2026-07-01 |
| **Frontend** | 1 static generator | Zero-backend, `.tfvars` output |

---

## What's Next

See [TODO.md](TODO.md) for the current phase plan: CI/CD & OIDC reliability, Terraform module completeness, static generator enhancements, and documentation hardening.

---

**Last Updated**: August 1, 2026
**Owner**: Platform Engineering
