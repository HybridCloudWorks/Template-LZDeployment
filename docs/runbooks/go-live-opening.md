# Runbook — Go-Live Opening (Phase 4 pre-flight)

**Scope**: the ordered, operator-local checklist that opens the go-live
chain — [TODO.md](../../TODO.md) items 4.2 → 4.3 → 4.1 (+4.4) → 4.5 → 4.7.
Opened by the operator in-session 2026-08-15, lifting the 2026-08-06
deferral ([REVIEW.md](../../REVIEW.md) §§1–9). Ends at the first real
instantiation (step 5), which is where the *generated* repository takes
over as the deliverable.

**Reconciled 2026-08-19 to the post-refactor architecture.** Steps 4 and 5
previously named the four numbered workflows
(`010-terraform-init.yml`, `020-rbac-validation.yml`, `terraform-plan.yml`,
`terraform-apply.yml`) and the Stage 13 dogfood. All of those were deleted
by the generator-only refactor
([ADR 0013](../decisions/0013-generator-only-avm-architecture.md)): this
repository no longer deploys anything itself. "Pipeline green" now means
the **generated** repository's own emitted workflows running against a real
tenant, and the dogfood gate was replaced by the end-to-end generation
proof. The steps below are the current ones.

**Why operator-local.** Probed from the remote sandbox 2026-08-15, with a
working operator token: `gh api repos/…/branches/main/protection` → HTTP 403
"GitHub access is not enabled for this session" (App-level block on admin
endpoints), and `gh api repos/…/pages` → HTTP 403 "Access to this GitHub API
path is not permitted through this proxy". Steps 1–2 therefore run only on
the operator's own machine with their own `gh` session — consistent with
[decision 0004](../decisions/0004-factory-copy-is-a-disposable-installer.md)'s
execution model.

**Tenant-agnosticism still holds.** The same-day operator directive — "Do
not tie yourself to a specific azure tenant/sub ID, this is meant to be a
template" — is not in tension with go-live: opening the phase authorizes
*executing* the chain; the tenant/subscription values are chosen at
execution time on the operator's machine and never land in template files.

---

## 1. Item 4.2 — Required status checks on upstream `main` — ✅ DONE 2026-08-28

> **Applied and verified.** `main` enforces `contexts: ["Factory CI"]` bound to
> the GitHub Actions app, `enforce_admins: true`, `strict: false`, approvals
> `0`. Nothing to run here for this repository. The steps below are retained
> because they are the procedure, and because item 4.2 re-opens whenever a
> context is added — after item 4.1 lands, the `azure/login`-dependent contexts
> join the payload and it is re-PUT (see the end of this section).

> **Shell**: every command block in this runbook is **PowerShell**, because
> that is what the operator runs (`pwsh` is already a prerequisite — the
> factory's own tooling is PowerShell). Do not paste bash line continuations
> (`\`) into PowerShell: it parses the backslash as a unary operator and
> splits the command, which is exactly the failure this note exists to
> prevent. PowerShell's continuation character is a backtick (`` ` ``); the
> blocks below are written as one-liners instead, so there is nothing to
> continue.

Payload: [branch-protection-payload.json](branch-protection-payload.json).
Requires only the `Factory CI` context (the one check that is reliable
today); the `azure/login`-dependent contexts stay non-required until item
4.1 exists, otherwise every merge deadlocks. Approvals stay 0 (single-owner
caveat, REVIEW.md §2). `enforce_admins: true` — the failure this fixes was
red merges by the sole admin's account (dependabot PRs #63–#68), so
exempting admins would re-open it. `strict: false` — single-owner serial
PRs don't race each other, and requiring branch-up-to-date would force a
full CI re-run per trailing PR for no second contributor.

> **Prerequisite, added 2026-08-28 — shipped in #115 (`d2878fb`), on `main`.**
> `Factory CI` used to carry a `paths:` filter on its `pull_request` trigger
> (`factory/**`, `site/**`, `terraform/**`, `*.ps1`, `*.sh`,
> `factory-version.json`). **A path-filtered required check is a merge
> deadlock**: on a PR that misses the filter the check never reports, and
> GitHub holds the PR at *"Expected — waiting for status to be reported"*
> indefinitely. Every docs-only PR would have become unmergeable the moment
> this payload was applied — verified against PRs #111, #113 and #114, none of
> which ran `Factory CI`. The filter was removed from the `pull_request`
> trigger (the job runs in ~50s, so it costs nothing); the `push:` filter is
> untouched because required checks gate PRs, not pushes. **Before applying
> the payload, confirm the fix is on `main`:**
>
> ```powershell
> gh api "repos/HybridCloudWorks/Template-LZDeployment/contents/.github/workflows/factory-ci.yml?ref=main" -H "Accept: application/vnd.github.raw" | Select-Object -First 20
> ```
>
> The `pull_request:` block must show `branches: [main]` and **no** `paths:`.
> (The raw media type returns the file directly — the default JSON response
> is base64-wrapped, and neither `base64 -d` nor `sed` exists in PowerShell.)

```powershell
gh api -X PUT repos/HybridCloudWorks/Template-LZDeployment/branches/main/protection --input docs/runbooks/branch-protection-payload.json
```

Read-back (item 4.2's validation criterion):

```powershell
gh api repos/HybridCloudWorks/Template-LZDeployment/branches/main/protection --jq '{contexts: .required_status_checks.contexts, strict: .required_status_checks.strict, enforce_admins: .enforce_admins.enabled, approvals: .required_pull_request_reviews.required_approving_review_count}'
```

Expect `contexts: ["Factory CI"]`, `strict: false`, `enforce_admins: true`,
`approvals: 0`. After item 4.1 lands and the four pipeline workflows run
green (step 4), add their contexts to the payload and re-PUT.

Upstream factory repo only — client copies are never hardened
([decision 0007](../decisions/0007-retire-client-copy-hardening.md)).

## 2. Item 4.3 — GitHub Pages source → "GitHub Actions"

Either route; `deploy-pages.yml` is ready and SHA-pinned.

- **UI**: repo **Settings → Pages → Source → GitHub Actions**.
- **API** — first-time enablement (Pages was not enabled at the 2026-08-02
  read-back):

  ```powershell
  gh api -X POST repos/HybridCloudWorks/Template-LZDeployment/pages -f build_type=workflow
  ```

  If Pages is already enabled from a branch, switch it instead:

  ```powershell
  gh api -X PUT repos/HybridCloudWorks/Template-LZDeployment/pages -f build_type=workflow
  ```

Verify: the next `deploy-pages.yml` run publishes; the site serves `site/`
at root and `frontend/` under `/frontend/` (item 4.3's criterion).

## 3. Item 4.1 — Confirm the tenant, then bootstrap the identity estate

The tenant-confirmation step is **load-bearing** ([decision
0004](../decisions/0004-factory-copy-is-a-disposable-installer.md)): it is
the operator's own `az`/`gh` sessions that create the estate, and the
reachable tenant in past discovery belonged to a regulated-industry client
(REVIEW.md §1) — do not proceed on an unconfirmed tenant.

Rights needed on the confirmed tenant: **Entra application administrator**
(app registrations + federated credentials) and **management-group root**
access (RBAC assignments at the MG root). Pre-flight checklist:
[docs/USER-CHECKLIST.md](../USER-CHECKLIST.md).

### 3a. Produce the config, then run discovery on its own first

`lz-config.json` comes from the `site/` wizard (open `site/index.html`
locally). `azure.tenantId` is a **required** schema field — the wizard
cannot emit a valid config without it, which is the tenant confirmation
enforced structurally rather than by convention.

Then run **discovery alone** before the wrapper. It is read-only, mutates
nothing, and produces the human gate:

```powershell
pwsh -File factory/discovery/Invoke-Discovery.ps1 -ConfigPath <lz-config.json>
```

It writes `discovery-inventory.json` and **`tenant-readiness-report.md`**
beside the config. Both are gitignored — a discovery run at the repo root
cannot commit tenant data.

**Read the readiness report and resolve every `Fail` before going on.** Ten
checks, each carrying its own remediation text:

| | | | | |
| --- | --- | --- | --- | --- |
| `R01` app registrations | `R02` federated credentials | `R03` management groups | `R04` subscription availability | `R05` policy assignment |
| `R06` RBAC roles | `R07` diagnostic settings | `R08` networking | `R09` GitHub access | `R10` Terraform backend |

`R09` fails on an ownership-model/account-type mismatch — see
[decision 0010](../decisions/0010-generated-repo-ownership-policy.md).
`R03` fails without write access at the management-group root; its
remediation names the intermediate-root alternative.

Running discovery first is not required — the wrapper runs it as phase 1
anyway — but it turns 4.1 from one large step into a specific punch list,
at zero risk.

### 3b. Run the engagement wrapper

The identity estate is created by the **broker**, which the engagement
wrapper sequences plan-first. The wrapper gates discovery → broker →
render → validate → scaffold in order and stops on the first failure:

```powershell
# Plan-first: no Entra, RBAC, GitHub, or backend mutation.
pwsh -File scripts/Invoke-CustomerEngagement.ps1 -ConfigPath <lz-config.json>

# Review the emitted plan/audit evidence, then execute:
pwsh -File scripts/Invoke-CustomerEngagement.ps1 -ConfigPath <lz-config.json> -Apply
```

With `-Apply`, discovery runs with `-FailOnNotReady` (unless
`-AllowNotReady` is given), so a tenant with blocking findings stops the
engagement before the broker touches anything.

`-Apply` propagates to the broker and the scaffold **only** — discovery,
render, and validate never mutate external systems. To reconcile just the
identity estate, add `-Phase broker`.

`scripts/Start-LandingZoneBootstrap.ps1` is the legacy single-repo
bootloader, retained for compatibility; it is not the engagement path, and
its help text still describes the deleted numbered workflows.

If the engagement enables the sandbox subscription, pass
`-SandboxSubscriptionId <guid>` to the broker — that is item 4.4; omitting
it on a sandbox-enabled config is a terminating error by design.

Verify: the generated repository's `azure-auth-test.yml` OIDC token
exchange green from a real PR (item 4.1's criterion).

## 4. Item 4.5 — Pipeline green end to end

Two halves, only one of which is still open.

- **Factory-side — already done.** `factory-ci.yml` and
  `e2e-generation-proof.yml` both run green on PRs and on `main` (PR
  #99/#101 check runs, both topology jobs, real registry access). Nothing
  to do here.
- **Estate-side — the open half.** In the **generated** repository
  produced by step 3, open a real PR touching a layer and confirm its
  emitted workflows run green against the confirmed tenant:
  `azure-auth-test.yml`, `terraform-fmt-validate.yml`, `terraform-plan.yml`
  on the PR, then `terraform-apply.yml` per layer in dependency order
  (`platform-management` → `global` → `platform-connectivity` →
  `state-hardening`).

Anything still red after 4.1 routes to `deployment-troubleshooter`
(REVIEW.md §3). Then widen the factory's protection payload required
contexts (step 1, last paragraph) — those are the factory's own checks,
not the generated repo's.

## 5. Item 4.7 — First real instantiation

The self-deploying Stage 13 dogfood was deleted with the live tree
(ADR 0013), and its **generation half** is already discharged: the
end-to-end generation proof passed on GitHub-hosted runners for both
topologies (2026-08-17). What remains is the **apply half** — the first
real instantiation against the confirmed tenant, which is steps 3 and 4
carried through to a green apply in the generated repository.

This is also where the per-estate verifications parked by TODO item 3.1
execute: resource-provider registration audit entries land
`registered`/`already-registered` with none `pending`, the authenticated
broker/scaffold suite runs record evidence, and any `enable_nsg_flow_logs`
flag flip is a separate PR whose plan shows the flow-log resources against
the chosen NSGs only.

Acceptance criteria: [docs/USER-CHECKLIST.md](../USER-CHECKLIST.md).
Item 5.1 (release attestation, and the reviewed PR that flips the
`releaseGates` booleans against named evidence) follows from its hand-off.
[stage13-dogfood-execution.md](stage13-dogfood-execution.md) is retained
as superseded history only — do not execute it.
