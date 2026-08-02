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

- [x] **[HARDENING] Decide and document the fork mechanic and visibility.** A
  GitHub fork of a public repository is always public, and the legacy bootstrap
  (`scripts/Start-LandingZoneBootstrap.ps1`, phase 9 `Create-BootstrapPR`)
  commits `.lz-bootloader-state.json` — tenant ID, subscription ID, SP app IDs
  — into the repo (`010-terraform-init.yml` even triggers on that path). Prefer
  a **private copy** per client (template repository, `gh repo create
  --private` + push, or repo import) over a literal public fork.
  *(Done 2026-08-01: decision recorded in
  [docs/decisions/0001-private-copy-over-public-fork.md](docs/decisions/0001-private-copy-over-public-fork.md);
  `scripts/Initialize-ClientFork.ps1 -CreatePrivateCopy` implements the
  private-copy mechanic.)*
- [x] **[HARDENING] Per-fork enablement checklist.** Forks do not inherit:
  Actions enablement (workflows are disabled on forks until enabled), branch
  protection/rulesets, secrets/variables, environments, or third-party
  integrations (qlty, GitGuardian). The wiki guidebook now lists these; script
  the fork-init (`gh` API) so it is not tribal knowledge.
  *(Done 2026-08-01: `scripts/Initialize-ClientFork.ps1` — plan-first; enables
  Actions, configures branch protection with required checks and ≥1 required
  approval, reads back secret-scanning state, and verifies every setting via
  GitHub API read-back.)*
- [ ] **[BLOCKER] Enable and verify required `main` status checks** *(moved
  from TODO.md)* — `main` currently has **no** `required_status_checks`;
  Terraform Plan/Apply, secrets-scan, and action-pinning exist in the repo
  while being advisory in GitHub settings, so a green merge proves nothing. Run
  Factory CI at least once, then configure branch protection/rulesets using the
  stable check names and confirm required contexts plus enforcement by GitHub
  API read-back. Requires repository administration. Must be repeated on every
  client fork (protection does not inherit) — fold into the fork-init script
  above. *(Corrected 2026-08-01: GitHub records the Factory CI check context
  as `Factory CI` — the job-level name — not `Factory CI / Factory CI` as this
  item previously claimed. Tooling shipped (this PR):
  `scripts/Initialize-ClientFork.ps1` wires the default required checks
  `Factory CI`, `Enforce Immutable Action Refs`, `TruffleHog Secret Scan`,
  `Gitleaks Secret Detection`, `Terraform Security Scan`; caveat — the first
  two are path-filtered and can wait forever on non-matching PRs, the three
  secrets-scan checks always report; `-RequiredChecks` overrides. Operator
  execution pending.)* *(Plan-verified live 2026-08-01, read-only: current
  `main` protection has empty required contexts, `strict=false`, required
  approvals 0, `enforce_admins=true`; Actions is enabled; secret scanning and
  push protection are already on. The protection payload was prepared and
  plan-verified against the live repo — preserved in the session scratchpad
  as `protection-main.json` — but the mutation needs interactive operator
  approval: apply it, or run `scripts/Initialize-ClientFork.ps1 -Repository
  saulpatinojr/HCW-Plan_LZDeployment -Apply`, accepting its required-approvals
  ≥ 1 floor. Single-owner caveat: required approvals ≥ 1 deadlocks
  self-merges — this repo has one owner today.)*
- [ ] **[HARDENING] Verify GitHub repo settings not checkable from a local
  clone** *(moved from TODO.md)* — secret scanning enabled, required PR
  approval count (currently 0 — branch protection exists but does not require
  human review). Same read-back applies to each client fork. *(2026-08-01:
  Tooling shipped (this PR): `scripts/Initialize-ClientFork.ps1` performs the
  full API read-back including secret-scanning state and required approvals —
  operator execution pending.)*

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
  (org prefix, environments, repo name); (4) OIDC — **minimal identity
  estate by default since 2026-08-02** (the old layers × environments matrix
  is removed; the script consumes the broker's plan builder): one shared
  read-only **plan** SP (Reader at MG root, subjects `pull_request` +
  `ref:refs/heads/main`) and one shared **apply** SP (Management Group
  Contributor + Resource Policy Contributor at MG root, Contributor per
  distinct subscription, subjects `environment:*` only, one federated
  credential per environment); `per-environment` is the explicit 2 × N
  scale-out (`identity.cicdIdentityModel`); RBAC Administrator only on
  sandbox selection, sandbox-subscription scope, ABAC-constrained; legacy
  `sp-terraform-*` matrix estates are detected and routed to a report-only
  remediation section (see
  [docs/decisions/0002-minimal-identity-estate.md](docs/decisions/0002-minimal-identity-estate.md));
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
  **generated** repo; default required check `repository-scan` since
  2026-08-01, override with `LZ_REQUIRED_STATUS_CHECKS`).

**Missing / manual**

- [ ] **[BLOCKER] Create the live landing-zone identity estate — the OIDC
  bootstrap never ran against this repo** *(moved from TODO.md as "add the
  federated credential"; re-confirmed 2026-08-01 on merged PR #53: `RBAC Audit
  & Validation` and `RBAC Compliance Checks` fail in ~10 s)* — every PR fails
  Azure login with `AADSTS700213: No matching federated identity record found
  for presented assertion subject
  'repo:saulpatinojr/HCW-Plan_LZDeployment:pull_request'`, and run
  30721161313 shows the same `AADSTS700213` for the **Contributor SP's
  `ref:refs/heads/main` subject**, so push-triggered runs on `main` fail the
  same way. **Superseding finding — read-only live discovery, 2026-08-01
  (operator-approved)**: the earlier premise "the live Entra app registration
  was never updated" understates it. In the reachable tenant — a
  client tenant; its identity is recorded in CBTS-side engagement records
  (2026-08-01 session evidence), not in this file — **no landing-zone app
  registrations exist at all**: 420 visible apps enumerated, none
  HCW/terraform/plan-named, and both GitHub-named candidate apps carry ZERO
  federated credentials. The repository holds only 3 secrets
  (`AZURE_CLIENT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, all last
  updated 2026-05-29) — `AZURE_PLAN_CLIENT_ID` and `TF_API_TOKEN` do **not**
  exist — and the only repo environment is `copilot` (no dev/prod/hub).
  **Conclusion**: the legacy bootstrap's OIDC/GitHub phases (4–6) never ran
  against this repo. The real remediation is executing the Phase-2 bootstrap
  end-to-end (`Start-LandingZoneBootstrap.ps1` or the broker) in the
  **confirmed** engagement tenant; credential patching
  (`scripts/Add-PlanFederatedCredential.ps1`) has no legitimate target until
  that estate exists. *(Updated 2026-08-02: the packaged bootstrap run now
  creates the **minimal** estate by default — 2 identities, one shared plan
  and one shared apply, per
  [docs/decisions/0002-minimal-identity-estate.md](docs/decisions/0002-minimal-identity-estate.md)
  — superseding any earlier expectation of the 7-app legacy matrix with its
  subscription-scope RBAC Administrator grants.)*
  **Open question / hard stop**: which tenant and subscription the three
  2026-05-29 secrets actually reference is unverifiable from a clone (secret
  values are unreadable). The engagement owner must confirm the intended
  deployment tenant before **any** identity is created. The reachable tenant
  belongs to a **regulated-industry client** — creating identities there
  without engagement-owner confirmation is **prohibited**.
  [REVIEW REQUIRED] — the unredacted identifiers (client name, tenant GUID)
  live in the 2026-08-01 session evidence and CBTS-side engagement records,
  not in this file; engagement-owner review is still required before acting
  on this item.
  The same failure will occur **per customer** if the bootstrap's phase 4 is
  skipped — the per-customer fix remains "do not skip phase 4".
- [x] **[BLOCKER] Privilege-split hazard: the plan-secret fallback in
  `020-rbac-validation.yml`** *(found 2026-08-01 during the read-only live
  check above)* — the workflow's client-id expression
  (`github.event_name == 'pull_request' && secrets.AZURE_PLAN_CLIENT_ID ||
  secrets.AZURE_CLIENT_ID`) fell back to `AZURE_CLIENT_ID` when
  `AZURE_PLAN_CLIENT_ID` was unset, so a PR run would authenticate as the
  **Contributor-designated** client id — a contract-#2 violation
  ([.claude/CROSS-DOMAIN-CONTRACTS.md](.claude/CROSS-DOMAIN-CONTRACTS.md))
  waiting to go live the moment the identity estate was created.
  *(Resolved in-repo 2026-08-02: the fallback expression is removed — both
  `020-rbac-validation.yml` jobs, all three `010-terraform-init.yml` logins,
  `terraform-apply.yml`'s read-only gate, and `azure-auth-test.yml` now
  always authenticate as `AZURE_PLAN_CLIENT_ID`; a missing plan secret fails
  the login outright instead of silently escalating. The operator
  requirement stands and is folded into the first blocker above: the
  `AZURE_PLAN_CLIENT_ID` secret must be added in the same change that
  creates the identity estate, or every read-only job fails.)*
- [ ] **[BLOCKER] Supply `-SandboxSubscriptionId` at bootstrap (or grant
  manually).** Without it, platform-management's sandbox-cleanup Contributor
  assignment fails `AuthorizationFailed` at apply. Blocks any engagement whose
  config enables the sandbox subscription. *(Hardened 2026-08-01: sandbox
  enabled without `-SandboxSubscriptionId` is now a terminating error in the
  script unless `-SkipSandboxRbac` is passed, and `-ConfigPath` seeds the
  value from `azure.subscriptions.sandbox` in `lz-config.json`. Supplying the
  real subscription ID per engagement remains operator work.)*
- [x] **[HARDENING] Repo targeting breaks for org-owned forks.**
  `Start-LandingZoneBootstrap.ps1` resolved `$GithubOwner` from `gh api user`,
  so secrets, environments, and every OIDC subject pointed at
  `<operator-login>/<repo>` — wrong whenever the client fork lives in an
  organization. *(Fixed 2026-08-01: new `-Repository <owner>/<name>`
  parameter; falls back to `gh repo view` on the clone's origin, then the
  config, then the operator login with a loud warning.)*
- [x] **[HARDENING] Environment-selection bug**: choice `[1] Dev only` yielded
  `@('dev','prod')` (`Gather-DeploymentConfig` — only choice `2` narrowed).
  *(Fixed 2026-08-01: each menu choice now maps to exactly its environments;
  choice 1 yields dev only.)*
- [x] **[HARDENING] Per-customer inputs are hardcoded**: region fixed to
  `eastus`/`eus` (no prompt), repo name defaults to `HCW-Demo-LZDeployment`,
  `TERRAFORM_CLOUD_ENABLED` always `'true'`, TFC workspace hardcoded
  `landing-zone`. *(Fixed 2026-08-01: region, repo name, and TFC workspace are
  prompted or seeded from `-ConfigPath <lz-config.json>`; the new
  `-Backend azurerm|hcp-terraform` parameter skips the TFC phases and sets
  `TERRAFORM_CLOUD_ENABLED=false` for azurerm.)*
- [x] **[HARDENING] Reviewer gate is the bootstrapping operator** — in a
  single-owner repo that is self-approval. *(Fixed 2026-08-01: new
  `-EnvironmentReviewers` parameter accepts user logins and `org/team` slugs;
  the default (operator) now emits a loud SELF-APPROVAL warning. Supplying a
  real client reviewer per engagement remains operator input.)*
  *(Operator-seeded item.)*
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
  script honor it. *(2026-08-01: Tooling shipped (this PR): the legacy script
  now honors the wizard's `backend.type` via `-ConfigPath` and accepts an
  explicit `-Backend azurerm|hcp-terraform` override; azurerm skips the TFC
  auth and org/workspace phases and sets `TERRAFORM_CLOUD_ENABLED=false`. The
  Issue #11 migration of this repo's own backend remains open — operator
  execution pending.)*

**CRUD per engagement**
- Created (client tenant): 2 app registrations + service principals by
  default (minimal model; `per-environment` scales to 2 × N), federated
  credentials — plan: `pull_request` + `ref:refs/heads/main`; apply: one
  `environment:<name>` per environment — and RBAC assignments (Reader @ MG
  root; Management Group Contributor + Resource Policy Contributor @ MG root;
  Contributor per distinct subscription; Storage Blob Data Reader/Contributor
  on the state account for azurerm; ABAC-constrained RBAC Administrator on
  the sandbox subscription only when sandbox is selected).
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

- [x] **[HARDENING] The wizard's NEXT-STEPS.md teaches an interface that does
  not exist.** `site/app.js` (`nextStepsMarkdown`) told the operator to run
  `bootstrap-broker.ps1 -ConfigPath … -Phase discovery` (no `-Phase` parameter
  exists; discovery is `factory/discovery/Invoke-Discovery.ps1`), mentioned
  `--rollback` (does not exist), and `scaffold-copy.ps1 -DryRun` / `-AutoPush`
  (real interface: plan-by-default, `-Apply`, `-Force`, `LZ_SCAFFOLD_*`
  variables). *(Fixed 2026-08-01: the generated NEXT-STEPS.md now emits the
  real interfaces — discovery → broker plan/`-Apply` → render → scaffold
  plan/`-Apply`; the fictional flags are gone. 48 wizard tests pass.)*
- [x] **[HARDENING] Variable placement is manual.** Downloads land in the
  browser's download directory; the operator must create
  `generated-output/<customer>/` and move all 8 files by hand. *(Fixed
  2026-08-01: new "Download all as bundle (.zip)" — an offline, store-only zip
  containing all 8 artifacts under the customer's output directory plus a
  SHA-256 `checksums.txt` manifest for verifying placement; individual
  downloads kept.)*
- [ ] **[HARDENING] Wizard is not hosted** — requires opening
  `site/index.html` from disk. Host per fork (GitHub Pages) or document the
  local-open flow as the supported path. (The separate legacy `frontend/`
  generator has the same gap; that one stays tracked in TODO.md.)
  *(2026-08-01: Tooling shipped (this PR):
  `.github/workflows/deploy-pages.yml` — SHA-pinned GitHub Pages deploy of
  `site/` on pushes to `main` touching `site/**`. One manual prerequisite
  remains: repo Settings → Pages → source "GitHub Actions". Operator
  execution pending.)*
- [x] **[HARDENING] Document the placeholder loop-back.** `management_ip_ranges`
  must be filled before the first connectivity plan;
  `log_analytics_workspace_id` can only be filled **after** platform-management
  applies. The wiki guidebook now walks this; keep it in the generated
  CONFIGURATION.md too. *(Done 2026-08-01: the generated CONFIGURATION.md now
  documents the loop-back — fill `management_ip_ranges` → apply
  platform-management → paste `log_analytics_workspace_id` → re-plan
  connectivity. The contract-#4 commented placeholders are untouched.)*

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
- [x] **[BLOCKER] Reconcile the `spoke-network` template-corpus divergence** —
  `factory/templates/terraform/modules/spoke-network/` did not carry
  `configuration_aliases = [azurerm.hub]` (contract #5,
  [.claude/CROSS-DOMAIN-CONTRACTS.md](.claude/CROSS-DOMAIN-CONTRACTS.md)); a
  repo generated then would drop the hub-side peering wiring that
  `terraform/live/workloads-prod/main.tf` depends on. *(Resolved 2026-08-01:
  the template module is at byte parity with `terraform/modules/spoke-network/`
  and carries the alias; the template callers
  (`workloads-{prod,nonprod}/main.tf.tmpl`) pass `providers` maps with a
  conditional `azurerm.hub` provider fed by the new
  `connectivity_subscription_id` variable, mapped in
  `factory/renderer/variable-map.json`. 199 renderer tests green; touched
  stacks validate.)*
- [x] **[HARDENING] Reconcile the remaining `terraform/live/` ↔ factory-corpus
  divergence** *(moved from TODO.md)*. *(Resolved 2026-08-01:
  `terraform/live/sandbox/variables.tf` location validation fixed `^[a-z]+$` →
  `^[a-z0-9]+$` so `eastus2`-style regions pass; the corpus remote-state reads
  gained `use_azuread_auth` (contract #3); the live vs corpus state-container
  layouts were re-verified and are deliberately different — live uses
  per-layer containers, the corpus uses a shared container with per-layer
  keys — and both are internally consistent. `Test-LzSchemaDrift` reports
  InSync. The live/corpus split as a whole still ends only when Stage 13
  regenerates this repo from the factory. Sandbox location-regex item
  operator-seeded.)*
- [x] **[HARDENING] Broker's default required check assumes qlty.** The
  generated repo's branch protection defaulted to `qlty check` — an
  integration a fresh customer repo does not have, so protection waits on a
  check that never reports. *(Fixed 2026-08-01: default changed to
  `repository-scan` (`Set-LzBranchProtection`,
  `factory/bootstrap/LZFactory.Bootstrap.psm1`) — the only corpus-shipped
  check that reports on every PR with no path filter.
  `LZ_REQUIRED_STATUS_CHECKS` still overrides; documented in the module's
  comment help and USER-CHECKLIST.md.)*
- [x] **[HARDENING] Four entry points, one motion.** Discovery → broker →
  render → scaffold spans four commands wired by environment variables.
  *(Done 2026-08-01: `scripts/Invoke-CustomerEngagement.ps1` — single wrapper
  with `-Phase discovery|broker|render|scaffold|all`, plan-first; `-Apply`
  propagates to the broker and scaffold only, the sequence stops on the first
  failure, cross-phase inputs are validated, and per-phase evidence paths are
  printed.)*

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

- [x] **[BLOCKER] Replace the `backend.hcl` placeholders** *(operator-seeded)*
  — all four live stacks (`terraform/live/global|platform-connectivity|platform-management|workloads-prod/backend.hcl`)
  carry `storage_account_name = "<REPLACE_WITH_OUTPUT_FROM_BOOTSTRAP>"`;
  `terraform init` fails until the operator pastes the
  `terraform/backend-bootstrap` output. *(Automation shipped 2026-08-01:
  `scripts/New-BackendConfig.ps1` — plan-first (`-Apply`) generator of all
  four per-layer `backend.hcl` files from the backend-bootstrap outputs (new
  `layer_state_containers` output in `terraform/backend-bootstrap/outputs.tf`),
  a wizard-exported `backend.hcl`, or `lz-config.json`; always enforces
  `use_azuread_auth = true`. The placeholder files themselves are only
  replaced when the operator runs it after backend-bootstrap applies.)*
- [ ] **[BLOCKER] Verify the pipeline actually runs green end-to-end** *(moved
  from TODO.md)* — confirm `010-terraform-init.yml`, `020-rbac-validation.yml`,
  `terraform-plan.yml`, and `terraform-apply.yml` complete successfully on a
  real PR/push. As of 2026-07-01 there is no recorded successful run of any of
  these; the PR leg stays red until the Phase 2 identity blocker is fixed.
  *(Updated 2026-08-01: read-only live discovery found no landing-zone
  identity estate exists at all — no app registrations, no
  `AZURE_PLAN_CLIENT_ID` secret, no dev/prod/hub environments — so the
  prerequisite is the full Phase-2 bootstrap in the confirmed engagement
  tenant, not credential patching. See Phase 2, first blocker.)*
- [x] **[HARDENING] Investigate 0-second workflow failures** *(moved from
  TODO.md)* — historical runs of `010-terraform-init.yml` /
  `020-rbac-validation.yml` failed in 0 seconds. *(Investigated and resolved
  2026-08-01: root cause was a YAML block-scalar bug, fixed by PR #13 (commit
  `516cf44`, 2026-07-01). Every failure since is the missing live OIDC
  federated credential — those fail in ~10–40 s, not 0 s. No workflow change
  was needed; the remaining redness is the Phase 2 credential item.)*
- [x] **[HARDENING] First-apply traps need loud errors.** The three known traps
  — unset `management_ip_ranges`, the `log_analytics_workspace_id` loop-back
  after platform-management, and the missing sandbox RBAC grant — were
  documented but surfaced as raw Terraform/Azure errors. *(Fixed 2026-08-01:
  new exported `Test-LzFirstApplyPreflight` in the broker
  (`factory/bootstrap/LZFactory.Bootstrap.psm1`) checks all three loudly and
  early, persisting findings in the `preflight` array of
  `bootstrap-audit.json`; the generated connectivity plan workflow
  (`factory/templates/.github/workflows/terraform-plan.yml.tmpl`) gained a
  matching pre-flight step that fails fast before login and init.)*
- [x] **[HARDENING] Set customer expectations on module status** —
  `keyvault-cmk` and `sentinel-siem` are scaffolds (render-blocked),
  `defender-baseline` is not auto-deployed. Never describe them as live
  capabilities in engagement collateral. *(Fixed 2026-08-01: the wizard's
  feature table now labels `defender-baseline` "available, not auto-deployed"
  — the earlier claim that the renderer wires it in was false;
  `sentinel-siem`/`keyvault-cmk` were already labeled scaffold-only. Keep the
  wizard table and generated `CONFIGURATION.md` accurate as modules change.)*
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

**Exists today (updated 2026-08-01)**: `scripts/Dispose-Engagement.ps1`
(plan-first, archive-then-delete with SHA-256 verification) and the runbook
[docs/runbooks/engagement-disposal.md](docs/runbooks/engagement-disposal.md).
[USER-CHECKLIST.md](USER-CHECKLIST.md) carries the "Never store" list (user
tokens, `TFE_TOKEN`, client secrets, storage keys) and per-stage
evidence-preservation steps; `.gitignore` keeps all per-customer artifacts out
of the fork.

**Missing / manual**

- [x] **[HARDENING] Write and script the disposal runbook.** Order matters:
  **archive, then delete.** *(Done 2026-08-01: runbook at
  [docs/runbooks/engagement-disposal.md](docs/runbooks/engagement-disposal.md);
  script `scripts/Dispose-Engagement.ps1` — plan-first, archives
  `lz-config.json` (hard-fails if it cannot be archived and verified),
  broker/scaffold plan+audit evidence, discovery artifacts, and
  `.reports/**` with SHA-256 verification before any deletion; deletes clone
  residue; ends CLI sessions; writes `disposal-plan.json` /
  `disposal-audit.json`.)*
- [x] **[HARDENING] Fork-side residue.** The fork retains secrets
  (`AZURE_CLIENT_ID`, `AZURE_PLAN_CLIENT_ID`, `AZURE_TENANT_ID`,
  `AZURE_SUBSCRIPTION_ID`, `TF_API_TOKEN`), variables, environments, and any
  bootstrap branch/PR (`bootstrap/phase-0-oidc-setup-*`, which committed
  `.lz-bootloader-state.json`). *(Done 2026-08-01: `Dispose-Engagement.ps1`
  prints the fork-residue `gh` cleanup commands and executes them only with
  `-IncludeForkCleanup -Apply -ForkRepository`; retire-vs-retain guidance is
  in the disposal runbook.)*
- [x] **[HARDENING] Identity residue — decide the end-state.** Legacy-script
  SPs carry federated credentials subject-bound to the **fork**
  (`repo:<owner>/<fork>:…`); the generated repo gets its own identities from
  the broker. Two write-capable identity sets must not persist with one
  unmonitored. *(Decided 2026-08-01, recorded in the disposal runbook: the
  fork-bound legacy-script identity set is DELETED at disposal once the
  generated repo's broker-created identities are verified working; re-pointing
  the fork-bound subjects to the customer repo is the documented alternative
  only when the engagement never used the broker path.)*
- [x] **[HARDENING] Say what must NOT be deleted.** The state storage account
  and containers (or TFC workspaces), the landing-zone identities in the client
  tenant, and the customer repo survive disposal — they ARE the deliverable.
  *(Done 2026-08-01: the disposal runbook carries the MUST-NOT-DELETE list as
  prominently as the deletion list, and `Dispose-Engagement.ps1` prints it as
  a banner on every run.)*

**CRUD per engagement**
- Deleted: local clone (+ everything inside), CLI sessions, local tokens,
  optionally the fork's secrets/branches.
- Retained: customer repo, Azure resources + state, landing-zone identities,
  archived evidence.

---

## Phase 7 — Repeat (factory hygiene between engagements)

- [x] **[HARDENING] Define the upgrade channels.** Client fork ← upstream:
  document fork-sync (or re-fork) policy. Customer repo ← factory corpus:
  `scaffold-copy.ps1` existing-repo mode (draft PR on `LZ_SCAFFOLD_BRANCH`)
  already supports this — document it as the supported regeneration/upgrade
  path per customer. *(Addressed by doc 2026-08-01:
  [docs/runbooks/engagement-lifecycle.md](docs/runbooks/engagement-lifecycle.md).)*
- [x] **[HARDENING] Engagement provenance.** `deployment-metadata.json` and
  `factory-version.json` stamp factory/schema versions per export; keep a
  CBTS-side record of customer → factory version so a corpus fix can be mapped
  to affected engagements. *(Addressed by doc 2026-08-01:
  [docs/runbooks/engagement-lifecycle.md](docs/runbooks/engagement-lifecycle.md).)*
- [x] **[HARDENING] Cross-engagement isolation on the operator workstation.**
  One clone per customer, never shared `generated-output/`; run
  `az account clear` and `gh auth logout` between engagements so a session from
  customer A cannot touch customer B's tenant. *(Addressed by doc 2026-08-01:
  [docs/runbooks/engagement-lifecycle.md](docs/runbooks/engagement-lifecycle.md).)*

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
