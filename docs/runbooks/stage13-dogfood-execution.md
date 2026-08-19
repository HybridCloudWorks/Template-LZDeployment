# Runbook — Stage 13 Dogfood Execution

> ## ⛔ SUPERSEDED 2026-08-15 — historical record, do not execute
>
> The self-deploying dogfood instance this runbook drives **no longer
> exists**. The generator-only refactor
> ([ADR 0013](../decisions/0013-generator-only-avm-architecture.md))
> deleted the bespoke `terraform/live/` tree and the numbered workflows
> (`010-terraform-init.yml`, `020-rbac-validation.yml`) that every gate
> below depends on, and the `dogfoodInstanceAppliesGreen` release gate was
> replaced by `endToEndGenerationProofPasses` — which **passed** on
> GitHub-hosted runners for both topologies on 2026-08-17.
>
> **Where the work went instead**: the dogfood's generation half is
> discharged by the end-to-end generation proof; its apply half is now
> TODO item 4.7, "first real instantiation", sequenced by
> [go-live-opening.md](go-live-opening.md) step 5.
>
> Retained because its gate-by-gate structure and the 2026-08-01/02
> discovery findings are cited elsewhere. Nothing below is a current
> instruction.

**Scope** (as written 2026-08-02): the operator's command-exact path from the repository's current
state to a completed Stage 13 dogfood, ending at the Stage 14 hand-off.
Written 2026-08-02; every command below was verified against the current
script parameter blocks and workflow YAML on this branch
(`fix/factory-motion-findings`, PR #59). Run all commands from the repo root.
Backlog context: [TODO.md](../../TODO.md) items 4.1–4.7 and 5.1; operator
acceptance criteria: [USER-CHECKLIST.md](../USER-CHECKLIST.md) (Stage 13/14
sections).

Convention per gate: **Preconditions → Commands → Expected evidence →
Verify.** Do not skip a gate; each one's verification is the next one's
precondition.

---

## Gate 0 — Current state (verified 2026-08-02)

Nothing to run; this is the starting position the rest of the runbook assumes.

- PRs #55–#58 are merged; #59 (`fix/factory-motion-findings`) is open and
  carries this runbook.
- **No identity estate exists** (read-only live discovery, 2026-08-01): no
  landing-zone app registrations; only 3 repo secrets (`AZURE_CLIENT_ID`,
  `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, last updated 2026-05-29);
  `AZURE_PLAN_CLIENT_ID` and `TF_API_TOKEN` absent; only repo environment is
  `copilot`.
- Branch protection on `main`: empty required contexts, `strict=false`,
  required approvals 0, `enforce_admins=true`. GitHub Pages: not enabled.
- `generated-output/dogfood/lz-config.json` exists, is **gitignored**
  (`git check-ignore` confirms), validates against
  `factory/schema/lz-config.schema.json`, and carries all-zeros GUID
  placeholders for every tenant/subscription field. It renders clean:
  `generated-output/dogfood/rendered/render-manifest.json` records
  **fileCount 94, 0 blocking guards, 1 warning** (G14: the `prod` environment
  has no required reviewers — closed by the bootstrap in Gate 3).
- Sandbox is **disabled** in this config (`azure.subscriptions.sandbox` is
  empty), backend is `azurerm`, management-group root is `mg-hcw-dogfood`,
  org prefix `hcw`, region `eastus`/`eus`.

## Gate 1 — Fill the config placeholders

**Preconditions**: the engagement owner has confirmed the intended deployment
tenant (the REVIEW.md §1 hard stop — do not proceed on an unconfirmed
tenant).

**Commands**: edit `generated-output/dogfood/lz-config.json` and replace the
`00000000-…` placeholders in exactly these fields (per USER-CHECKLIST, the
config carries no secrets — GUIDs only):

- `azure.tenantId`
- `azure.subscriptions.management`
- `azure.subscriptions.connectivity`
- `azure.subscriptions.workloadProd`
- `azure.subscriptions.workloadNonProd`
- `backend.azurerm.subscriptionId`

Then re-validate and re-render:

```powershell
Test-Json -Json (Get-Content generated-output/dogfood/lz-config.json -Raw) `
  -SchemaFile factory/schema/lz-config.schema.json

Import-Module ./factory/renderer/LZFactory.Renderer.psd1
Invoke-LzRender -ConfigPath generated-output/dogfood/lz-config.json `
  -OutputDirectory generated-output/dogfood/rendered -Force
```

**Expected evidence**: `Test-Json` returns `True`; the render completes with
`fileCount: 94` and no blocking guards in
`generated-output/dogfood/rendered/render-manifest.json`.

**Verify**: `git status` shows **no** change involving
`generated-output/` — the directory is gitignored and the filled config must
never be committed (it now holds real tenant/subscription IDs).

## Gate 2 — Repository settings (operator-run)

These two mutations are repository administration. The agent session could
not execute them: the permission system classifies them as requiring
interactive operator approval, and the repo guardrails
([CLAUDE.md](../../CLAUDE.md) §5) stop short of settings mutations by design.
Both were **plan-verified read-only** on 2026-08-01/02; only the write is
outstanding.

**2a. Branch protection on `main`.** Apply the prepared payload (it
was preserved in the 2026-08-01 session scratchpad as
`protection-main.json` — session-scoped, so regenerate it if that session is
gone; the required contexts are listed in Gate 5):

```bash
gh api -X PUT repos/HybridCloudWorks/Template-LZDeployment/branches/main/protection \
  --input protection-main.json
```

This is the only route since 2026-08-07: the packaged script's hardening
stages were retired by
[decision 0007](../decisions/0007-retire-client-copy-hardening.md) —
`Initialize-ClientFork.ps1` is now only the private-copy mechanic. Note this
Gate targets the **upstream factory repo only**; client copies are never
hardened (decision 0004). Caveat: keep `required_approving_review_count` at
**0** in the payload — a ≥ 1 floor deadlocks self-merges in this
single-owner repo.

**2b. GitHub Pages** (prerequisite of `.github/workflows/deploy-pages.yml`,
which deliberately does not automate it): Settings → Pages → Source
**"GitHub Actions"**, or the REST equivalent:

```bash
gh api -X POST repos/HybridCloudWorks/Template-LZDeployment/pages \
  -f build_type=workflow
```

**Expected evidence / verify**: `gh api repos/HybridCloudWorks/Template-LZDeployment/branches/main/protection`
returns the required contexts (Gate 5 lists them) with `strict: true`;
`gh api repos/HybridCloudWorks/Template-LZDeployment/pages` returns
`"build_type": "workflow"`.

## Gate 3 — Bootstrap the identity estate

**Preconditions**: Gate 1 done; `az login` to the confirmed tenant with
rights to create app registrations and assign roles at `mg-hcw-dogfood` and
the subscriptions; `gh auth login` with repo-admin scope.

**Command** (parameters verified against the current
`scripts/Start-LandingZoneBootstrap.ps1` param block; the two stdin lines
answer the only prompts left when `-ConfigPath` seeds everything else — the
phase-4 `CREATE` confirmation and the final `Create PR? [y/N]`):

```powershell
"CREATE", "N" | pwsh -NoProfile -File scripts/Start-LandingZoneBootstrap.ps1 `
  -ConfigPath generated-output/dogfood/lz-config.json `
  -Repository HybridCloudWorks/Template-LZDeployment `
  -Backend azurerm `
  -SkipSandboxRbac
```

Notes: `-Backend azurerm` skips the TFC auth and org/workspace phases and
sets `TERRAFORM_CLOUD_ENABLED=false`. `-SkipSandboxRbac` is belt-and-braces
here — sandbox is disabled in this config, so no sandbox RBAC would be
attempted anyway. Prefer running it interactively the first time and typing
`CREATE` when phase 4 shows its **RESOURCE CREATION** banner; the banner
enumerates exactly what will be created before anything is touched.

**What it creates** (minimal model — the default, since `identity` is absent
from this config; enumeration read from the current script):

| | Plan identity `sp-hcw-plan` | Apply identity `sp-hcw-apply` |
| --- | --- | --- |
| OIDC subjects | `repo:…:pull_request`, `repo:…:ref:refs/heads/main` | `repo:…:environment:dev`, `…:environment:prod`, `…:environment:hub` |
| RBAC | Reader @ MG root `mg-hcw-dogfood`; Storage Blob Data Reader on the state account | Management Group Contributor + Resource Policy Contributor @ MG root; Contributor per distinct subscription; Storage Blob Data Contributor on the state account |

Plus: repo secrets `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
`AZURE_CLIENT_ID` (apply), `AZURE_PLAN_CLIENT_ID` (plan) — this closes the
Gate 0 secret gap in the same change that creates the identities (REVIEW.md
§1 requirement); environments `dev`/`prod`/`hub` with reviewers (pass
`-EnvironmentReviewers` to avoid the SELF-APPROVAL warning); and deletion of
any **stale environment-scoped `AZURE_CLIENT_ID` overrides** (they would
silently shadow the repo-level secret).

**Expected evidence**: `.lz-bootloader-state.json` and a report under
`.reports/bootstrap/` — both **gitignored since PR #57**; they carry tenant
and subscription IDs and must never be committed. The report's
**Legacy Identity Estate — Remediation** section will be **empty** for this
repo ("No legacy-matrix identities found"): no `sp-terraform-*` matrix apps
were ever created here (Gate 0 discovery found zero landing-zone apps). In a
real engagement with a legacy estate, that section lists operator-run `az`
commands only — the script never deletes identities itself.

**Verify**:

```bash
az ad app federated-credential list --id <plan-app-id> --query "[].subject"
az ad app federated-credential list --id <apply-app-id> --query "[].subject"
gh secret list --repo HybridCloudWorks/Template-LZDeployment
gh api repos/HybridCloudWorks/Template-LZDeployment/environments --jq '.environments[].name'
```

Subjects must match the table exactly — no wildcards.

## Gate 4 — State backend and per-layer backend.hcl

**Preconditions**: Gate 3 done (the operator's own `az` session performs
this; the pipeline identities are not used here).

**Commands** (`terraform apply` is operator-run — the repo guardrails deny
apply to agent sessions by design; `management_subscription_id` is the only
variable without a default, and the region defaults differ from this
config's `eastus`/`eus`, so pass all three):

```powershell
terraform -chdir=terraform/backend-bootstrap init
terraform -chdir=terraform/backend-bootstrap plan `
  -var "management_subscription_id=<management-subscription-guid>" `
  -var "primary_region=eastus" -var "primary_region_code=eus"
terraform -chdir=terraform/backend-bootstrap apply `
  -var "management_subscription_id=<management-subscription-guid>" `
  -var "primary_region=eastus" -var "primary_region_code=eus"
```

Then generate the four per-layer `backend.hcl` files — plan first, then
apply (parameters verified against `scripts/New-BackendConfig.ps1`; with no
source parameters it reads `terraform output -json` from
`terraform/backend-bootstrap/`, the authoritative source):

```powershell
pwsh -File scripts/New-BackendConfig.ps1
pwsh -File scripts/New-BackendConfig.ps1 -Apply
```

**Expected evidence**: `terraform/live/{global,platform-connectivity,platform-management,workloads-prod}/backend.hcl`
each carry the real storage-account name and `use_azuread_auth = true` —
always enforced, never key auth, because the state account is created with
shared-key access disabled (contract #3,
[docs/CROSS-DOMAIN-CONTRACTS.md](../CROSS-DOMAIN-CONTRACTS.md)).

**Verify — name-mismatch check (important)**: the real account name is
`sthcwtfstate<random-suffix>` (the stack appends a random suffix), while the
config placeholder says `sthcwtfstateeus01`. Compare:

```powershell
terraform -chdir=terraform/backend-bootstrap output -raw storage_account_name
```

If it differs from `backend.azurerm.storageAccountName` in
`generated-output/dogfood/lz-config.json`, update the config to the real
name and re-run Gate 3's command — the bootstrap is idempotent and the
re-run repoints the Storage Blob Data Reader/Contributor grants at the real
account. Skipping this leaves the data-plane grants on a nonexistent scope
and `terraform init` fails with 403 for the pipeline identities.

## Gate 5 — Pipeline verification

**Preconditions**: Gates 2–4 done. All triggers below are operator-run (the
repo guardrails deny `gh workflow run` to agent sessions).

**Commands**:

```bash
gh workflow run azure-auth-test.yml
gh workflow run 020-rbac-validation.yml
gh workflow run 010-terraform-init.yml -f environment=dev
gh run list --limit 5
```

**Expected evidence / what green looks like**:

- `azure-auth-test.yml` (`workflow_dispatch` plus a weekly cron since
  2026-08-02, and now **enforcing** — the role assertions fail the run
  rather than inform): the OIDC login succeeds as `AZURE_PLAN_CLIENT_ID` — a
  `workflow_dispatch` token carries a branch subject, which is bound to the
  plan identity. This is the live token-exchange proof USER-CHECKLIST
  requires.
- `020-rbac-validation.yml`: both jobs authenticate as the plan identity on
  every trigger and the audit of the apply identity's RBAC passes.
- `010-terraform-init.yml`: all three read-only jobs log in as the plan
  identity and `terraform init` succeeds against the AAD-only backend
  (the plan step runs `-lock=false`; the plan identity cannot take state
  leases).

**Verify**: with these runs green, the Gate 2 required checks can all report.
The protection set (the contexts for the Gate 2a payload):
`Factory CI`, `Enforce Immutable Action Refs`, `TruffleHog Secret Scan`,
`Gitleaks Secret Detection`, `Terraform Security Scan`. Caveat: the first
two are **path-filtered** — a PR touching none of their paths waits forever
on an "Expected" check; the three secrets-scan checks report on every PR.

## Gate 6 — Layer applies

Two paths exist; read before choosing.

**Primary for the Stage 13 gate: `dogfood-instance.yml`.** The release gate
only accepts evidence from this workflow — `releaseGateEligible` is computed
as `Mode == 'Apply' && Layer == 'all' && failures == 0`
(`factory/dogfood/Invoke-Dogfood.ps1`), and USER-CHECKLIST Stage 14 requires
exactly such a run. The PR loop below cannot produce that artifact.

**Preconditions** (USER-CHECKLIST "Stage 13 dogfood variables"): repo
variables `LZ_DOGFOOD_CONFIG_JSON` (the full filled config —
`gh variable set LZ_DOGFOOD_CONFIG_JSON < generated-output/dogfood/lz-config.json`),
`LZ_DOGFOOD_TENANT_ID`, `LZ_DOGFOOD_SUBSCRIPTION_ID`,
`LZ_DOGFOOD_PLAN_CLIENT_ID`; `AZURE_APPLY_CLIENT_ID` configured **only** on
each protected apply environment.

**Commands** (inputs verified against the workflow: `mode`
Render|Plan|Apply, `layer` all|global|platform-connectivity|platform-management|workloads-prod|workloads-nonprod|sandbox,
`environment` for Apply only):

```bash
gh workflow run dogfood-instance.yml -f mode=Render -f layer=all
gh workflow run dogfood-instance.yml -f mode=Plan   -f layer=all
# then, per layer in dependency order, through the protected environment:
gh workflow run dogfood-instance.yml -f mode=Apply -f layer=global -f environment=hub
```

Apply order: `global` → `platform-management` → `platform-connectivity`
(after the loop-back below) → `workloads-prod` / `workloads-nonprod`.
Finish with an `Apply`/`layer=all` run for the release-gate-eligible report.

**The connectivity loop-back (contract #4)** — applies on either path.
`management_ip_ranges` is deliberately never collected by the wizard and
`log_analytics_workspace_id` only exists after platform-management applies:

1. Set `management_ip_ranges` for the connectivity layer **before its first
   plan**. On this repo's live tree that means adding it to a tfvars file in
   `terraform/live/platform-connectivity/` (start from
   `terraform.tfvars.example`); the variable's own validation rejects an
   empty list and the wildcards `*`/`0.0.0.0/0`, so an unfilled value fails
   the plan with that error — note the fail-fast **pre-flight step exists in
   the generated corpus and the broker** (`Test-LzFirstApplyPreflight`), not
   in this repo's root plan workflow.
2. Apply `platform-management`; copy its `log_analytics_workspace_id`
   output into the connectivity tfvars.
3. Re-plan and apply `platform-connectivity` — this second pass is what
   wires firewall diagnostics and threat-intel alerts.

**Alternative / day-2 path: PR + dispatch** on the repo's own
`terraform/live/` tree *(updated 2026-08-02 — `terraform-apply.yml` is now
dispatch-only; merging to `main` deploys nothing)*: open a PR touching
`terraform/**` (`terraform-plan.yml` plans changed layers as the plan
identity, `-lock=false`), merge, then **dispatch the apply per layer**
(Actions → Terraform Apply → pick the layer, or
`gh workflow run terraform-apply.yml -f layer=<layer>` — operator-run; the
repo guardrails deny `gh workflow run` to agent sessions). The run checks
out trusted `main`, validates the layer against a hard allowlist, creates a
saved plan, refuses destructive plans, and applies through the layer's
protected environment gate. This is the day-2 change path and the natural
vehicle for the loop-back edits, but its runs do not produce Stage 13
evidence.

**Verify**: every Plan shows no unintended destroy/replace; every Apply run
uploads `dogfood-<run-id>-*` artifacts; the final `Apply`/`all` run's
`dogfood-report.json` has `externalMutation: true` and
`releaseGateEligible: true`.

## Gate 7 — Evidence and the Stage 14 hand-off

**Preserve**: every `dogfood-<run-id>-*` artifact, `dogfood-report.json`,
per-layer init/plan/show/apply logs, the configuration SHA-256, and the
exact **workflow run IDs** of (a) a successful, unskipped Factory CI run and
(b) the successful `Apply`/`all` dogfood run.

**Independent read-backs** (USER-CHECKLIST Stage 13, do not skip): Azure
resources, Terraform state, federated credentials and exact OIDC subjects,
GitHub environment protections, and required status checks — read back via
`az`/`gh`, not inferred from workflow logs.

**Then, in order** (pointers, not duplication — the acceptance detail lives
in [USER-CHECKLIST.md](../USER-CHECKLIST.md) Stage 13/14):

1. Set `dogfoodInstanceAppliesGreen=true` in `factory-version.json` in a
   **separately reviewed PR** — only after every layer applied green and the
   read-back evidence is accepted.
2. Build the hash-pinned attestation
   (`factory/release/release-attestation.schema.json`), run
   `.github/workflows/release-readiness.yml` with the two exact run IDs, and
   require every R01–R10 finding plus `readyForPromotion=true`.
3. Open the separate release-gate PR. The evaluator never promotes
   automatically.

---

## What can go wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| `AADSTS700213` on any workflow login | Identity estate missing (Gate 3 not run) or the token's subject has no matching federated credential | Run Gate 3; verify subjects with `az ad app federated-credential list` against the Gate 3 table. Remember: read-only jobs need the **plan** identity's subjects (`pull_request`, `ref:refs/heads/main`); apply jobs need `environment:<name>` on the apply identity |
| `terraform init` 403 against the state account | Data-plane grants landed on the config's placeholder account name, not the real `sthcwtfstate<suffix>` account | Gate 4 name-mismatch check: update the config, re-run the idempotent Gate 3 bootstrap |
| Connectivity plan fails on `management_ip_ranges` | Contract #4: the wizard never collects it; validation rejects empty/wildcard | Gate 6 loop-back step 1. The generated corpus and the broker fail fast with instructions; this repo's root plan workflow does not — expect the raw variable-validation error here |
| Firewall diagnostics silently absent after connectivity apply | `log_analytics_workspace_id` never looped back after platform-management | Gate 6 loop-back steps 2–3; nothing else warns about this |
| `az role assignment create` fails right after SP creation | Entra replication lag — the script already passes `--assignee-principal-type ServicePrincipal` and sleeps 5 s after SP creation, but lag can exceed that | Re-run the bootstrap (idempotent); it re-attempts only what is missing |
| A PR waits forever on an "Expected" check | `Factory CI` and `Enforce Immutable Action Refs` are path-filtered; a docs-only PR never triggers them | Trigger the workflow manually, or narrow the `contexts` list in the Gate 2a protection payload and re-apply it |
| `AuthorizationFailed` on sandbox cleanup at platform-management apply | Sandbox subscription enabled without the RBAC grant | **N/A for this dogfood** — sandbox is disabled in the config. In real engagements: supply the sandbox subscription in `lz-config.json` and do not pass `-SkipSandboxRbac` |
| Self-merge blocked after Gate 2 | The applied protection payload set `required_approving_review_count` ≥ 1 | Single-owner caveat: re-apply the Gate 2a payload with approvals 0, or add a second reviewer |
