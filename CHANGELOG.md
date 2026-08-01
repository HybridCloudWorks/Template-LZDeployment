# CHANGELOG - Completed Work

**Purpose**: Historical record of all completed tasks and deliverables  
**Last Updated**: August 1, 2026

---

## PROD-TODO implementation — production-motion tooling and corpus fixes (2026-08-01)

Implements the in-repo portion of the [PROD-TODO.md](PROD-TODO.md) backlog.
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
  [GitHub wiki](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki).
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
| [#31](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/31) | Merged into `feat/lz-factory-…` — rescued the three test suites (48 wizard, 60 discovery, 100 renderer at the time) that previously existed only in a session-scoped temp directory |
| [#28](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/28) | Squash-merged into `main` as `11f09cd` — carried everything |
| [#30](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/30) | Closed as **superseded**, not abandoned — its commit `0040033` reached `main` inside #28 via a real merge (shared SHA), so squashing it separately would have minted a duplicate |
| [#32](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/32) | Squash-merged as `7568bc3` — agent git/gh permissions (merged by a human; an agent cannot widen its own permissions) |
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
  [Factory-Stage-7-Readiness](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Factory-Stage-7-Readiness))
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
- 🟦 Backend inconsistency: bootloader/workflow-010 reference Terraform Cloud, but `terraform-plan.yml`/`terraform-apply.yml`/all `terraform/live/*/backend.hcl` use native `azurerm` backend. Decision: adopt TFC — tracked as [GitHub Issue #11](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues/11), blocked on interactive TFC org/workspace/token setup.
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
