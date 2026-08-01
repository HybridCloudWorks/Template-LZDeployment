# PROD-TODO — Production-Readiness Backlog (Factory Motion)

**Created**: August 1, 2026
**Scope**: the work needed to run the production motion below with a real
customer. Repo-internal engineering debt that does not gate the motion stays in
[TODO.md](TODO.md). Per-stage operator activities: [USER-CHECKLIST.md](USER-CHECKLIST.md).
Step-by-step operator guidebook: the wiki's
[How to Get Started](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki)
section.

## The motion (operator-defined, 2026-08-01)

CBTS forks this repo to a client; **the client owns that fork**. The client
clones the fork and runs the initiation process (bootloading, authentication,
authorization, OIDC). They run the `site/` wizard, which creates their unique
variables; those are saved, stored, and copied into the locations the clone's
tooling uses to deploy the landing zone **into a new repository**. The landing
zone is stored and managed from that new repo thereafter, and the clone is
deleted. Rinse and repeat per customer. Every component in this repo is
Created/Read/Updated/Deleted per engagement — **this repo is the factory, not
the long-lived deployment**.

**Tags**
- `[BLOCKER]` — the motion cannot complete for a real customer until this is done.
- `[HARDENING]` — the motion completes, but this step is risky, manual, or misleading.

Artifacts per engagement: **upstream repo** (CBTS-owned factory) → **client
fork** (client-owned factory instance) → **local clone** (disposable working
copy) → **generated customer repo** (long-lived landing-zone home).

---

## Phase 1 — Fork (CBTS → client-owned fork)

**Exists today (verified)**: the repo is a self-contained factory
([README.md](README.md) documents the identity); `.gitignore` excludes
`generated-output/`, `/lz-config.json`, and all `*-evidence/` directories, so
customer variables cannot land in the fork by accident; workflows are
SHA-pinned and travel with the fork.

**Missing / manual**

- [ ] **[HARDENING] Decide and document the fork mechanic and visibility.** A
  GitHub fork of a public repository is always public, and the legacy bootstrap
  (`scripts/Start-LandingZoneBootstrap.ps1`, phase 9 `Create-BootstrapPR`)
  commits `.lz-bootloader-state.json` — tenant ID, subscription ID, SP app IDs
  — into the repo (`010-terraform-init.yml` even triggers on that path). Prefer
  a **private copy** per client (template repository, `gh repo create
  --private` + push, or repo import) over a literal public fork. Record the
  decision in the wiki guidebook.
- [ ] **[HARDENING] Per-fork enablement checklist.** Forks do not inherit:
  Actions enablement (workflows are disabled on forks until enabled), branch
  protection/rulesets, secrets/variables, environments, or third-party
  integrations (qlty, GitGuardian). The wiki guidebook now lists these; script
  the fork-init (`gh` API) so it is not tribal knowledge.
- [ ] **[BLOCKER] Enable and verify required `main` status checks** *(moved
  from TODO.md)* — `main` currently has **no** `required_status_checks`;
  Terraform Plan/Apply, secrets-scan, and action-pinning exist in the repo
  while being advisory in GitHub settings, so a green merge proves nothing. Run
  Factory CI at least once, then configure branch protection/rulesets using the
  stable check names (including `Factory CI / Factory CI`) and confirm required
  contexts plus enforcement by GitHub API read-back. Requires repository
  administration. Must be repeated on every client fork (protection does not
  inherit) — fold into the fork-init script above.
- [ ] **[HARDENING] Verify GitHub repo settings not checkable from a local
  clone** *(moved from TODO.md)* — secret scanning enabled, required PR
  approval count (currently 0 — branch protection exists but does not require
  human review). Same read-back applies to each client fork.

**CRUD per engagement**
- Created: the client fork (client-owned; retained as the client's factory
  instance or retired after the customer repo takes over — Phase 6 decision).
- Read: upstream factory code, wiki guidebook.
- Updated: fork settings (Actions on, protection, integrations).
- Deleted: nothing at this phase.

---

## Phase 2 — Clone + Initiate (bootstrap, authentication, authorization, OIDC)

**Exists today (verified against `scripts/Start-LandingZoneBootstrap.ps1`)**

- **Legacy interactive bootstrap** (`scripts/Start-LandingZoneBootstrap.ps1`,
  "retained for compatibility" per README) — phases: (1) CLI validation
  (az ≥ 2.69.0, gh ≥ 2.67.0, git ≥ 2.43.0, terraform ≥ 1.9.0); (2.1–2.3)
  Azure / GitHub / Terraform Cloud authentication; (3) config gathering
  (org prefix, environments, repo name); (4) OIDC — four app registrations +
  SPs (`main`/`dev`/`prod` layers plus the **Reader-only `plan` SP** bound
  exclusively to the `pull_request` subject), federated credentials per
  layer/environment, and the `-SandboxSubscriptionId` RBAC-Administrator grant;
  (5) GitHub secrets (`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
  `AZURE_CLIENT_ID`, `AZURE_PLAN_CLIENT_ID`) and variables; (6) environments
  `dev`/`prod`/`hub`, each with the bootstrapping operator as required reviewer
  and protected-branch deployment policy; (7) TFC org/workspace +
  `TF_API_TOKEN`; (8) report to `.reports/bootstrap/`; (9) optional bootstrap
  PR. Idempotent via `.lz-bootloader-state.json`.
- **Factory path**: `factory/discovery/Invoke-Discovery.ps1` (read-only;
  emits `tenant-readiness-report.md` + `discovery-inventory.json`) and
  `bootstrap-broker.ps1` / `.sh` (non-interactive, plan-first, `-Apply`-gated;
  reconciles Entra, RBAC, GitHub, and backend prerequisites for the
  **generated** repo; default required check `qlty check`, override with
  `LZ_REQUIRED_STATUS_CHECKS`).

**Missing / manual**

- [ ] **[BLOCKER] Add the live Entra `pull_request` federated credential, then
  verify it** *(moved from TODO.md; re-confirmed 2026-08-01 on merged PR #53:
  `RBAC Audit & Validation` and `RBAC Compliance Checks` fail in ~10 s)* — every
  PR fails Azure login with `AADSTS700213: No matching federated identity
  record found for presented assertion subject
  'repo:saulpatinojr/HCW-Plan_LZDeployment:pull_request'`. The code fix landed
  (`terraform-plan.yml` authenticates as `AZURE_PLAN_CLIENT_ID`); the live
  Entra app registration was never updated. Fix (needs Application
  Administrator):

  ```bash
  az ad app federated-credential create --id <APP_ID> --parameters '{"name":"pr-plan","issuer":"https://token.actions.githubusercontent.com","subject":"repo:saulpatinojr/HCW-Plan_LZDeployment:pull_request","audiences":["api://AzureADTokenExchange"]}'
  ```

  Then run the bootstrap/remediation against the live app registration,
  confirm the exact repo-scoped subject by API read-back, and prove token
  exchange from a real pull request. The same failure will occur **per
  customer** if the plan SP's credential is skipped — the bootstrap creates it
  (`Setup-Azure-OIDC`), so the per-customer fix is "do not skip phase 4".
- [ ] **[BLOCKER] Supply `-SandboxSubscriptionId` at bootstrap (or grant
  manually).** Without it, platform-management's sandbox-cleanup Contributor
  assignment fails `AuthorizationFailed` at apply (the script warns:
  `scripts/Start-LandingZoneBootstrap.ps1:693`). Blocks any engagement whose
  config enables the sandbox subscription.
- [ ] **[HARDENING] Repo targeting breaks for org-owned forks.**
  `Start-LandingZoneBootstrap.ps1` resolves `$GithubOwner` from `gh api user`
  (`Confirm-Auth-GitHub`, used at `Main` ~line 1133), so secrets, environments,
  and every OIDC subject point at `<operator-login>/<repo>` — wrong whenever
  the client fork lives in an organization. Add a `-Repository <owner>/<name>`
  parameter (or derive from `gh repo view` on the clone's origin).
- [ ] **[HARDENING] Environment-selection bug**: choice `[1] Dev only` still
  yields `@('dev','prod')` (`Gather-DeploymentConfig`,
  `scripts/Start-LandingZoneBootstrap.ps1:404-405` — only choice `2` narrows).
- [ ] **[HARDENING] Per-customer inputs are hardcoded**: region fixed to
  `eastus`/`eus` (no prompt), repo name defaults to `HCW-Demo-LZDeployment`,
  `TERRAFORM_CLOUD_ENABLED` always `'true'`, TFC workspace hardcoded
  `landing-zone`. All must come from the wizard config or prompts.
- [ ] **[HARDENING] Reviewer gate is the bootstrapping operator** — in a
  single-owner repo that is self-approval. Replace with a client Team reviewer
  once one exists (the script comment at `Setup-GitHub-Environments` says the
  same). *(Operator-seeded item.)*
- [ ] **[HARDENING] Execute the Stage 9 broker, Stage 10 scaffold, and Stage 11
  import test suites in a provisioned toolchain** *(moved from TODO.md)* —
  authenticated external services and required binaries were intentionally
  unavailable during implementation; runtime validation is still owed before
  first customer use.
- [ ] **[HARDENING] Resolve the backend duality** *(moved from TODO.md;
  migration itself tracked as
  [GitHub Issue #11](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues/11),
  blocked on interactive TFC org/workspace/token setup)* — HCP Terraform is the
  recorded default backend decision (CHANGELOG), the wizard exports either
  backend, `terraform/live/*/backend.hcl` is azurerm, and the legacy bootstrap
  assumes TFC. Pick the backend per customer at wizard time and make the legacy
  script honor it.

**CRUD per engagement**
- Created (client tenant): 4 app registrations + service principals, 8+
  federated credentials, RBAC assignments (Contributor / Storage Blob Data
  Contributor / RBAC Administrator / Reader / Storage Blob Data Reader).
- Created (fork): 4–5 secrets, 5–7 variables, 3 environments, optional
  bootstrap branch + PR. Created (clone): `.lz-bootloader-state.json`,
  `.reports/bootstrap/*`.
- Deleted on dispose: **identities remain** (they serve the landing zone), but
  fork-bound OIDC subjects and fork-held secrets are residue — see Phase 6.

---

## Phase 3 — Wizard / unique variables

**Exists today (verified against `site/`)**: 15-step offline wizard
(`site/index.html`, no network calls) validating against
`factory/schema/lz-config.schema.json`; export disabled until validation
passes; emits 8 artifacts (`site/app.js` `exportArtifacts()`): `lz-config.json`
(the contract), `terraform.auto.tfvars` (global layer),
`connectivity.auto.tfvars` (with **deliberate commented operator placeholders**
for required `management_ip_ranges` and recommended
`log_analytics_workspace_id` — contract #4 in
[.claude/CROSS-DOMAIN-CONTRACTS.md](.claude/CROSS-DOMAIN-CONTRACTS.md); do not
"fix" by adding wizard fields), `backend.hcl` (hcp-terraform or azurerm),
`environments.json`, `deployment-metadata.json`, `CONFIGURATION.md`,
`NEXT-STEPS.md`.

**Missing / manual**

- [ ] **[HARDENING] The wizard's NEXT-STEPS.md teaches an interface that does
  not exist.** `site/app.js` (`nextStepsMarkdown`, ~lines 1790–1850) tells the
  operator to run `bootstrap-broker.ps1 -ConfigPath … -Phase discovery`
  (no `-Phase` parameter exists; discovery is
  `factory/discovery/Invoke-Discovery.ps1`), mentions `--rollback` (does not
  exist), and `scaffold-copy.ps1 -DryRun` / `-AutoPush` (real interface:
  plan-by-default, `-Apply`, `-Force`, `LZ_SCAFFOLD_*` variables). The operator
  hits an error at every hand-off. Fix the generator to emit the real
  interface (owner: `frontend-experience-designer`; cross-check
  `bootstrap-broker.ps1:11-16`, `scaffold-copy.ps1:12-20`).
- [ ] **[HARDENING] Variable placement is manual.** Downloads land in the
  browser's download directory; the operator must create
  `generated-output/<customer>/` and move all 8 files by hand (NEXT-STEPS step
  1). Provide a single bundle download and/or a `Place-Artifacts` helper with a
  hash check so "saved, stored, and copied into the locations the Terraform
  files use" is one verifiable step.
- [ ] **[HARDENING] Wizard is not hosted** — requires opening
  `site/index.html` from disk. Host per fork (GitHub Pages) or document the
  local-open flow as the supported path. (The separate legacy `frontend/`
  generator has the same gap; that one stays tracked in TODO.md.)
- [ ] **[HARDENING] Document the placeholder loop-back.** `management_ip_ranges`
  must be filled before the first connectivity plan;
  `log_analytics_workspace_id` can only be filled **after** platform-management
  applies. The wiki guidebook now walks this; keep it in the generated
  CONFIGURATION.md too.

**CRUD per engagement**
- Created: `generated-output/<customer>/` (gitignored) holding tenant and
  subscription IDs — customer-confidential configuration.
- Read: by discovery, broker, renderer, scaffold.
- Updated: only by re-running the wizard and re-exporting (never hand-edit —
  header in every tfvars says so).
- Deleted: with the clone. **Archive `lz-config.json` first** (to the customer
  repo or client records) — it is the regeneration key for the entire landing
  zone.

---

## Phase 4 — Generate the customer repo

**Exists today (verified)**: renderer
(`factory/renderer/LZFactory.Renderer.psd1` → `Invoke-LzRender`; staging-only
output, `render-manifest.json`, 22 fail-closed guards; scaffold-only modules
blocked from rendering); scaffold builder (`scaffold-copy.ps1` / `.sh`,
plan-first with `scaffold-plan.json` / `scaffold-audit.json` evidence,
timestamped backups, draft-PR mode for existing repos); generated workflow
corpus (`factory/templates/.github/workflows/`: terraform-plan/apply,
`azure-auth-test` OIDC verification, action-pinning, security-scan,
fmt-validate, policy-checks) plus a generated per-customer `USER-CHECKLIST.md`;
Factory CI green (PR #53).

**Missing / manual**

- [ ] **[BLOCKER] Execute and accept the Stage 13 dogfood instance** *(moved
  from TODO.md; operator-seeded — this is the proof of exactly the "deploy into
  a new repo" step)* — populate the variables in
  [USER-CHECKLIST.md](USER-CHECKLIST.md), run render and read-only plans, apply
  each layer through its protected environment, preserve
  `dogfood-report.json`, and independently read back Azure, state, OIDC, and
  GitHub controls. Only then set `dogfoodInstanceAppliesGreen=true` in a
  reviewed PR (`factory-version.json:70` is `false` today).
- [ ] **[BLOCKER] Reconcile the `spoke-network` template-corpus divergence** —
  `factory/templates/terraform/modules/spoke-network/` does not carry
  `configuration_aliases = [azurerm.hub]` (contract #5,
  [.claude/CROSS-DOMAIN-CONTRACTS.md](.claude/CROSS-DOMAIN-CONTRACTS.md)); a
  repo generated today drops the hub-side peering wiring that
  `terraform/live/workloads-prod/main.tf` depends on.
- [ ] **[HARDENING] Reconcile the remaining `terraform/live/` ↔ factory-corpus
  divergence** *(moved from TODO.md)* — `terraform/live/sandbox/variables.tf`
  still validates `location` with `^[a-z]+$` (corpus uses `^[a-z0-9]+$`, so the
  live tree rejects `eastus2`-style regions); the `workloads-prod` remote-state
  container layout should be re-verified against the corpus; the approved
  hub-network subnet re-layout plan lands in the PR's terraform-plan run.
  `Test-LzSchemaDrift` only compares the schema against `factory/templates/` —
  the live tree is synced by hand until Stage 13 regenerates this repo from the
  factory, which resolves the split permanently. *(Sandbox location-regex item
  operator-seeded.)*
- [ ] **[HARDENING] Broker's default required check assumes qlty.** The
  generated repo's branch protection defaults to `qlty check`
  (`factory/bootstrap/LZFactory.Bootstrap.psm1:293-295`) — an integration a
  fresh customer repo does not have, so protection waits on a check that never
  reports. Set `LZ_REQUIRED_STATUS_CHECKS` per engagement (documented in
  USER-CHECKLIST.md) or change the default to a check the generated corpus
  actually ships.
- [ ] **[HARDENING] Four entry points, one motion.** Discovery → broker →
  render → scaffold spans four commands wired by environment variables. A
  single wrapper (`Invoke-CustomerEngagement`) with per-phase gates would
  reduce operator error. (Nice-to-have; the wiki guidebook sequences them
  manually today.)

**CRUD per engagement**
- Created: rendered staging tree + `render-manifest.json`; the **new private
  customer repo** (default branch, protection, environments via broker);
  `scaffold-plan.json`, `scaffold-audit.json`, `*.lz-backup-*` directories.
- Updated: existing-repo mode pushes `LZ_SCAFFOLD_BRANCH` and opens a draft PR
  (this is also the future upgrade channel — Phase 7).
- Deleted: staging output and evidence with the clone **after** the generated
  repo is accepted (USER-CHECKLIST says keep backups until acceptance).

---

## Phase 5 — Deploy the landing zone (from the new repo)

**Exists today (verified)**: generated repos carry their own plan/apply
workflows (plan SP on `pull_request`, apply through protected environments,
`azure-auth-test` verification). In this repo (dogfood/legacy):
`010-terraform-init.yml`, `020-rbac-validation.yml`, `terraform-plan.yml`
(authenticates as `AZURE_PLAN_CLIENT_ID`, `-lock=false`, fork-PR guards,
per-layer change matrix), `terraform-apply.yml` (serialized, layer matrix +
dispatch), `dogfood-instance.yml` (Render/Plan/Apply, protected environments,
Terraform 1.9.8), `release-readiness.yml`; `terraform/backend-bootstrap/` for
AAD-only state storage (contract #3).

**Missing / manual**

- [ ] **[BLOCKER] Replace the `backend.hcl` placeholders** *(operator-seeded)*
  — all four live stacks (`terraform/live/global|platform-connectivity|platform-management|workloads-prod/backend.hcl`)
  carry `storage_account_name = "<REPLACE_WITH_OUTPUT_FROM_BOOTSTRAP>"`;
  `terraform init` fails until the operator pastes the
  `terraform/backend-bootstrap` output. Automate: emit per-layer `backend.hcl`
  from the bootstrap output or the wizard's exported `backend.hcl` (which today
  is a single file the operator must duplicate per layer, replacing `<layer>`).
- [ ] **[BLOCKER] Verify the pipeline actually runs green end-to-end** *(moved
  from TODO.md)* — confirm `010-terraform-init.yml`, `020-rbac-validation.yml`,
  `terraform-plan.yml`, and `terraform-apply.yml` complete successfully on a
  real PR/push. As of 2026-07-01 there is no recorded successful run of any of
  these; the PR leg stays red until the Phase 2 AADSTS item is fixed.
- [ ] **[HARDENING] Investigate 0-second workflow failures** *(moved from
  TODO.md)* — historical runs of `010-terraform-init.yml` /
  `020-rbac-validation.yml` fail in 0 seconds, suggesting a trigger/syntax
  issue independent of the OIDC fix. Confirm once a post-fix run is attempted.
- [ ] **[HARDENING] First-apply traps need loud errors.** The three known traps
  — unset `management_ip_ranges`, the `log_analytics_workspace_id` loop-back
  after platform-management, and the missing sandbox RBAC grant — are
  documented (wiki guidebook) but surface as raw Terraform/Azure errors.
  Pre-flight-check them in the plan workflow or the broker.
- [ ] **[HARDENING] Set customer expectations on module status** —
  `keyvault-cmk` and `sentinel-siem` are scaffolds (render-blocked),
  `defender-baseline` is not auto-deployed. Never describe them as live
  capabilities in engagement collateral; keep the wizard's feature table and
  `CONFIGURATION.md` accurate.
- [ ] **[BLOCKER] Run Stage 14 release attestation** *(moved from TODO.md)* —
  after dogfood is green: select exact successful Factory CI and full dogfood
  apply run IDs, approve the hash-pinned read-back attestation, retain the
  readiness report, and open the separate release-gate PR only when
  `readyForPromotion=true`. Until v1.0.0 gates pass, every customer deployment
  is formally a **verification exercise** (factory v0.9.0;
  `oidcTokenExchangeVerifiedLive` also `false`).

**CRUD per engagement**
- Created: Azure management groups, policies, hub/spoke networks, management
  baseline, state storage + per-layer state files (or TFC workspaces).
- Read: cross-layer remote state (AAD auth, `use_azuread_auth = true`).
- Updated: only through PRs in the customer repo (plan on PR, apply on merge
  through gated environments).
- Deleted: nothing by pipeline; destructive plans require the
  `approved-destroy` control.

---

## Phase 6 — Dispose the clone

**Exists today (verified)**: nothing scripted. [USER-CHECKLIST.md](USER-CHECKLIST.md)
carries the "Never store" list (user tokens, `TFE_TOKEN`, client secrets,
storage keys) and per-stage evidence-preservation steps; `.gitignore` keeps all
per-customer artifacts out of the fork.

**Missing / manual**

- [ ] **[HARDENING] Write and script the disposal runbook** (first cut now in
  the wiki guidebook). Order matters: **archive, then delete.**
  1. Archive to client records / the customer repo: `lz-config.json`,
     `bootstrap-plan.json` + `bootstrap-audit.json`, `scaffold-plan.json` +
     `scaffold-audit.json`, discovery inventory, dogfood/release evidence,
     `.reports/bootstrap/*`.
  2. Delete the clone directory — removes `.lz-bootloader-state.json`
     (tenant/subscription IDs), `generated-output/`, rendered staging,
     `.terraform/` caches, `*.lz-backup-*`.
  3. End sessions: `az logout` + `az account clear`, `gh auth logout`,
     remove the TFC token (`terraform logout` / credentials file), unset
     `TFE_TOKEN` and all `LZ_*` variables from the shell profile.
- [ ] **[HARDENING] Fork-side residue.** The fork retains secrets
  (`AZURE_CLIENT_ID`, `AZURE_PLAN_CLIENT_ID`, `AZURE_TENANT_ID`,
  `AZURE_SUBSCRIPTION_ID`, `TF_API_TOKEN`), variables, environments, and any
  bootstrap branch/PR (`bootstrap/phase-0-oidc-setup-*`, which committed
  `.lz-bootloader-state.json`). If the fork is retired once the customer repo
  takes over: delete the secrets, revoke the TFC token, archive the repo. If
  the fork stays as the client's factory instance: document that it holds
  tenant-scoped configuration.
- [ ] **[HARDENING] Identity residue — decide the end-state.** Legacy-script
  SPs carry federated credentials subject-bound to the **fork**
  (`repo:<owner>/<fork>:…`); the generated repo gets its own identities from
  the broker. Two write-capable identity sets must not persist with one
  unmonitored: either delete the fork-bound set (federated credentials, role
  assignments, app registrations) at disposal, or re-point its subjects to the
  customer repo and retire the broker set — pick one and put it in the runbook.
- [ ] **[HARDENING] Say what must NOT be deleted.** The state storage account
  and containers (or TFC workspaces), the landing-zone identities in the client
  tenant, and the customer repo survive disposal — they ARE the deliverable.
  The runbook needs this list as prominently as the deletion list.

**CRUD per engagement**
- Deleted: local clone (+ everything inside), CLI sessions, local tokens,
  optionally the fork's secrets/branches.
- Retained: customer repo, Azure resources + state, landing-zone identities,
  archived evidence.

---

## Phase 7 — Repeat (factory hygiene between engagements)

- [ ] **[HARDENING] Define the upgrade channels.** Client fork ← upstream:
  document fork-sync (or re-fork) policy. Customer repo ← factory corpus:
  `scaffold-copy.ps1` existing-repo mode (draft PR on `LZ_SCAFFOLD_BRANCH`)
  already supports this — document it as the supported regeneration/upgrade
  path per customer.
- [ ] **[HARDENING] Engagement provenance.** `deployment-metadata.json` and
  `factory-version.json` stamp factory/schema versions per export; keep a
  CBTS-side record of customer → factory version so a corpus fix can be mapped
  to affected engagements.
- [ ] **[HARDENING] Cross-engagement isolation on the operator workstation.**
  One clone per customer, never shared `generated-output/`; run
  `az account clear` and `gh auth logout` between engagements so a session from
  customer A cannot touch customer B's tenant.

---

## Provenance — items moved here from TODO.md (2026-08-01)

Moved, not duplicated; TODO.md keeps only repo-internal engineering debt.

| Former TODO.md item | Now lives at |
| --- | --- |
| Execute and accept the Stage 13 dogfood instance | Phase 4, first blocker |
| Run Stage 14 release attestation | Phase 5, last blocker |
| Add the live Entra `pull_request` federated credential, then verify it | Phase 2, first blocker |
| Enable and verify required `main` status checks | Phase 1 |
| Execute the Stage 9/10/11 test suites in a provisioned toolchain | Phase 2 |
| Reconcile the remaining `terraform/live/` ↔ factory-corpus divergence | Phase 4 |
| Verify the pipeline actually runs green | Phase 5 |
| Investigate 0-second workflow failures | Phase 5 |
| Migrate backend from `azurerm` to Terraform Cloud (pointer to Issue #11) | Phase 2 (backend duality) |
| Verify GitHub repo settings that can't be checked from a local clone | Phase 1 |

**Owner**: Platform Engineering
