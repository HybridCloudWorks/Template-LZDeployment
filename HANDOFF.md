# Landing Zone Factory — Session Handoff

**Last updated:** 2026-07-26 · **Factory version:** 0.5.0 · **Config schema:** 2.0.0
**Progress:** Stages 1–10 implemented.
**First action:** review the Stage 10 scaffold builder and completion record in
[`docs/factory/STAGE-10-READINESS.md`](docs/factory/STAGE-10-READINESS.md).
Everything through Stage 10 is intended to be merged to `main` through the
Stage 10 implementation PR.

You are continuing a multi-session build. This document is the single source of
truth for where the work stopped. Read the *Next steps* section first, then
*Verify you're in the right state* before changing anything.

---

## 1. NEXT STEPS — start here

### 1.1 Everything is merged — how `main` got here

**Nothing is pending in code from Stages 1–10 after the Stage 10 PR merges.**
Runtime operator activities remain in `USER-CHECKLIST.md`.

| PR | Outcome |
|---|---|
| [#31](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/31) | Merged into `feat/lz-factory-…` |
| [#28](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/28) | Squash-merged into `main` as `11f09cd` — carried everything |
| [#30](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/30) | Closed as **superseded**, not abandoned — see below |
| [#32](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/32) | Squash-merged as `7568bc3` — agent git/gh permissions |

**Read this before you open your next PR against `main`**, because two branch
protection settings constrain how anything can land:

| Setting on `main` | Value | Consequence |
|---|---|---|
| `enforce_admins` | `true` | Direct push to `main` is rejected server-side, for everyone. A PR is the only route. |
| `required_linear_history` | `true` | **`--merge` is rejected.** |
| `allow_force_pushes` | `false` | — |
| `required_status_checks` | *absent* | Red CI does not block a merge (§6.4) |

So `gh pr merge <n> --merge` always fails on `main`. `--rebase` also fails on any
branch containing merge commits, because GitHub cannot replay them — which is
what happened to #28. **`--squash` is the reliable option**, and it is why the
whole factory arrived as one commit rather than as its individual commits:

```bash
gh pr merge <n> --squash --delete-branch
```

Two things worth knowing about how the stack was landed, because the reasoning
generalises:

- **#30 was deliberately not merged on its own.** Its commit `0040033` had
  already reached `docs/factory-handoff-and-tests` by a *real merge* rather than
  a cherry-pick, so it kept its SHA and travelled to `main` inside #28. Squashing
  #30 separately would have minted a second SHA for identical content and
  conflicted on `.gitignore`, `.claude/settings.json`, and `CLAUDE.md`. When you
  stack branches, prefer `git merge` over `git cherry-pick` for exactly this
  reason — a shared SHA cannot conflict with itself.
- **`gh` needs to run inside the repository.** `gh pr merge` from a home
  directory fails with `fatal: not a git repository`. Either `cd` first or pass
  `--repo saulpatinojr/HCW-Plan_LZDeployment`.

### 1.2 Stage 9 — bootstrap broker

Stage 9 adds the non-interactive bootstrap broker and the first authorized
external-write boundary. It plans by default, consumes config plus discovery,
reconciles Entra/RBAC/GitHub/backend prerequisites only in apply mode, and emits
plan/audit evidence. User-owned authentication and live verification are in
`USER-CHECKLIST.md`. Executable validation was skipped by owner direction; see
[`docs/factory/STAGE-9-READINESS.md`](docs/factory/STAGE-9-READINESS.md).

### 1.3 Stage 10 — scaffold builder

Stage 10 adds the non-interactive scaffold builder. It verifies the exact
renderer inventory and hashes every managed file, plans by default, refuses
unsafe/non-empty targets, preserves a recovery backup on forced updates, and
creates/commits/pushes the config-selected repository only in apply mode.
Operator authentication, force approval, backup retention, and remote read-back
are in `USER-CHECKLIST.md`. Executable validation was skipped by owner
direction; see
[`docs/factory/STAGE-10-READINESS.md`](docs/factory/STAGE-10-READINESS.md).

### 1.4 Non-production workloads — resolved

Schema 2.0.0 adds primary and DR spoke CIDRs for each of `dev`, `test`, and
`uat`. The wizard exposes those values, guard G22 requires a selected
environment's CIDRs and the shared `workloadNonProd` subscription, and the
`workloads-nonprod` template emits only the selected environments. G21 remains
the general protection against any active layer absent from the corpus.

### 1.5 Known work queued behind stage 10

| Priority | Item | Why |
|---|---|---|
| High | Add federated credential for `pull_request` subject | Unblocks all CI — see §6.2 |
| Medium | Execute the new Stage 9 broker tests in a provisioned toolchain | Authenticated external services were intentionally unavailable/skipped |
| Medium | Backport the stage-6 fixes to `terraform/live/` | The corpus and the live tree have diverged — see §6.3 |
| Low | Mark the GitGuardian incident a false positive | Dashboard-only action; the finding is a public test vector — see §6.5 |
| Medium | Execute the new Stage 10 scaffold tests in a provisioned toolchain | Git/PowerShell/GitHub runtime validation was intentionally skipped |
| Later | Stages 11–13 | See §7 |

---

## 2. Verify you're in the right state

Run this first. If it disagrees with the table below, stop and reconcile before
building anything.

```bash
git branch -vv && git log --oneline -3 && git status --short
```

Expected:

| | |
|---|---|
| Current branch | `main`, in sync with `origin/main` |
| `main` snapshot at handoff | `d219174` — post-merge handoff correction (#33) |
| | `7568bc3` — agent git/gh permissions (#32) |
| | `11f09cd` — the whole factory, stages 1–6 (#28) |
| Working tree | clean |
| Open PRs | none |
| Branches | `main` only; the four PR branches were deleted on merge |

Everything before `11f09cd` is ordinary dependabot traffic. If your `main` sits
at `1a94d2b` you are on a stale checkout — `git fetch origin && git pull --ff-only`.

Sanity check that the toolchain works:

```bash
pwsh -NoProfile -Command "Import-Module ./factory/renderer/LZFactory.Renderer.psd1 -Force; Import-Module ./factory/discovery/LZFactory.Discovery.psd1 -Force; 'both modules loaded'"
```

Then confirm the corpus is still self-consistent — this is the single most
useful check in the repo, and it takes two seconds:

```bash
pwsh -NoProfile -Command "Import-Module ./factory/renderer/LZFactory.Renderer.psd1 -Force; Test-LzSchemaDrift -SchemaPath ./factory/schema/lz-config.schema.json -MappingPath ./factory/renderer/variable-map.json -TemplateRoot ./factory/templates | Format-List"
```

Expect `InSync: True`, `DriftCount: 0`, `InfoCount: 2`. The two Info findings are
deliberate and explained in §3.5 — do not "fix" them by deleting map entries.

---

## 3. What exists, and what each piece is for

### 3.1 Stages 1–2 — Contract

| Path | Role |
|---|---|
| `docs/factory/FACTORY-DESIGN.md` | Architecture, assumptions, and a **41-entry risk register**. Risk IDs (AR3, BR2, GH1, SR1…) are referenced in code comments — when a comment cites one, this is where it's defined. |
| `factory/schema/lz-config.schema.json` | **The contract.** 17 domains, `additionalProperties: false`. Every downstream component reads it. Changing it is a breaking change — bump `configSchemaVersion`. |
| `factory-version.json` | Version contract, per-module implementation status, 5 release gates (all `false`). |

### 3.2 Stage 3 — Config plane

`site/` — a 15-step offline wizard (`index.html`, `app.js`, `styles.css`).

- **Makes zero network requests.** Enforced by CSP `connect-src 'none'` and a
  source scan. Do not introduce `fetch`/`XHR`/`WebSocket`/`sendBeacon`.
- Emits `lz-config.json` plus 7 derived artifacts.
- Estimates managed resources against the HCP Terraform **500-resource free-tier
  cap** and blocks export above it without explicit acknowledgement.

### 3.3 Stage 4 — Discovery engine (read-only)

`factory/discovery/` — inventories GitHub, Entra, Azure, and the Terraform
backend, then runs 10 readiness checks.

```bash
pwsh ./factory/discovery/Invoke-Discovery.ps1 -ConfigPath <path>/lz-config.json
```

**The rule that governs this whole module:** a probe must never conflate *"there
is nothing here"* with *"I was not allowed to look."* Five states — `Ok`,
`Empty`, `Forbidden`, `Unavailable`, `Error` — with `Conclusive` true only for
the first two. `Empty` and `Forbidden` must never collapse into each other.
(Control **BR2**.)

Capability is proven by **reading effective permissions**
(`Microsoft.Authorization/permissions`) and directory-role membership — never by
attempting a mutation and rolling it back. `Assert-LzReadOnly` structurally
rejects mutating verbs.

### 3.4 Stage 5 — Renderer

`factory/renderer/` + `factory/templates/`. Full detail in
[`factory/renderer/README.md`](factory/renderer/README.md).

```bash
pwsh -NoProfile -Command "Import-Module ./factory/renderer/LZFactory.Renderer.psd1 -Force; Invoke-LzRender -ConfigPath ./factory/tests/fixtures/sample-config.json -OutputDirectory ./.render-scratch -Force"
```

Key invariants — **do not break these**:

- Tokens are `{{FACTORY:...}}`, never `${...}` (Terraform owns `${...}`).
- Directives are comment-prefixed (`#{{IF}}`) so unrendered templates stay valid
  HCL/YAML/Markdown — that's what lets CI validate the raw corpus.
- GitHub Actions `${{ }}` survives via a negative lookbehind in the residual check.
- **Fail-closed**: unknown tokens, mistyped kinds, leftover placeholders, and
  unbalanced directives are hard errors.
- Directives evaluate **before** token substitution; loop bodies substitute
  *during* expansion while the loop variable is in scope.
- Use `defined path` for optional keys — an exported config *strips* them rather
  than emitting empty. Bare paths stay strict so typos fail loudly.

### 3.5 Stage 6 — the real Terraform corpus

`factory/templates/terraform/` now carries six live layers and the whole module
corpus, so a generated repository is deployable rather than illustrative.

| Layer | Emitted when | Form |
|---|---|---|
| `global` | always | `main.tf`/`outputs.tf` copied; tfvars rendered |
| `platform-connectivity` | `connectivity.model != 'none'` | rendered — DR hub and hub-to-hub peering are conditional |
| `platform-management` | always | rendered — backup and sandbox-cleanup sections are independently conditional |
| `workloads-nonprod` | dev, test, or UAT selected | rendered — selected primary/DR spokes share the non-production subscription |
| `workloads-prod` | `prod` selected | rendered — the connectivity remote-state read takes the azurerm or HCP form |
| `sandbox` | sandbox environment **and** sandbox subscription | copied; tfvars rendered |

`terraform/modules/**` and `terraform/scripts/` are copied verbatim through a new
`directories` section in the manifest. A directory is the right unit for content
with no per-configuration variation: listing sixty static `.tf` files
individually would add no decision while creating a trap where a newly added
file is silently not shipped. Committed `.terraform.lock.hcl` files under
`modules/` are excluded — a dependency lock only means anything at the root
module, and shipping those would mislead anyone who trusted them.

Both rendered trees pass `terraform fmt -check -recursive` and every layer
passes `terraform validate`.

**Reconciliations the promotion forced.** Each was a real defect, not a
formatting change:

| What | Was | Now |
|---|---|---|
| `firewall_threat_intel_mode` | `hub-network` implemented threat intelligence; the connectivity layer never plumbed a variable to it, so the wizard's choice landed in a tfvars entry Terraform ignored | Declared and passed through |
| `location` validation in the sandbox layer **and** module | `^[a-z]+$` — rejects `eastus2`, `westus3`, every numbered region the schema allows | `^[a-z0-9]+$` |
| `azfw_tier` | Unvalidated; the schema allows `Basic` | Validated against the schema's three values |
| Remote-state container | The layer read a per-layer container; `backend.tf` writes one shared container keyed by layer | Reads `<container>/platform-connectivity.tfstate` |
| Automation schedule `start_time` | Literal `2026-06-01T02:00:00Z` — Azure rejects a past start time, so it expired the day it was written | `timeadd(plantimestamp(), "1h")` with `ignore_changes` |
| Single-region configs | `New-LzRenderContext` and `Test-LzRenderGuards` read `azure.drRegion` unconditionally; the export strips optional keys, so **every** single-region render crashed under StrictMode | Existence-checked |

Two `Info` drift findings are expected and intentional:
`management_ip_ranges` (no schema key for operator source ranges — the default
is `"*"`, which reaches management interfaces from anywhere, and should be set
per landing zone) and `log_analytics_workspace_id` (owned by
`platform-management`, which keeps separate state).

---

## 4. Tests — 283, all green

**These were rescued into the repo by [#31](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/31)**
and reached `main` through #28. They previously existed only in a session-scoped
temp directory and would otherwise have been lost.

```bash
cd factory/tests
node test.js                                  # 48 — wizard logic
pwsh -NoProfile -File ./Test-Discovery.ps1    # 60 — discovery engine
pwsh -NoProfile -File ./Test-Renderer.ps1     # 100 — renderer
```

Paths resolve from `$PSScriptRoot`/`__dirname`, so they run from any checkout and
any working directory. Generated output goes to `factory/tests/.out/`
(gitignored). Fixtures live in `factory/tests/fixtures/`.

**They are not wired into CI yet** — see §1.4.

---

## 5. Decisions already made — do not silently revisit

| Decision | Rationale |
|---|---|
| **Two identities per environment** — Reader `*-plan` on `pull_request`, Contributor `*-apply` on `environment:<name>` | Makes it *structurally* impossible for a PR-triggered run to hold write access. No subject uses a wildcard; tests assert this. Prevents regression of the OIDC gap this repo already hit. |
| **Layers are never merged** | Each is its own state file and gate. Shared state across layers is the most common way a landing zone becomes unrecoverable. (Control **AR3**.) |
| **HCP Terraform is the default backend** | Validated: legacy free plan ended 2026-03-31; current cap is 500 managed resources; paid tiers bill on *peak hourly* count from $0.10/resource/month. `azurerm` is fully supported as the alternative. |
| **Release gates start `false`** | This pipeline has no recorded successful run. A factory multiplies the blast radius of an unproven path. `dogfoodInstanceAppliesGreen` and `oidcTokenExchangeVerifiedLive` are deliberate v1.0.0 blockers. |
| **Scaffold modules block rendering** | `sentinel-siem` and `keyvault-cmk` declare zero resources; `virtual-wan` doesn't exist. Emitting them would silently deploy nothing. Status is read from `factory-version.json`, so implementing a module lifts its guard automatically. |
| **Renderer re-validates independently of the wizard** | A validation that exists only in the UI is a suggestion, not a guarantee. 22 guards (G01–G22). |

---

## 6. Open problems

### 6.1 Legacy Terraform formatting — resolved in PR #35

`.github/workflows/terraform-plan.yml:150` runs `terraform fmt -check -recursive`.
The 26 pre-existing failures were normalized with Terraform 1.9.8:

```bash
terraform fmt -recursive terraform/
```

`terraform fmt -check -recursive terraform/` now exits zero.

### 6.2 CI is red on all PRs — pre-existing, prevents trustworthy validation

`RBAC Audit & Validation` and `RBAC Compliance Checks` both fail at Azure login:

```
AADSTS700213: No matching federated identity record found for presented
assertion subject 'repo:saulpatinojr/HCW-Plan_LZDeployment:pull_request'
```

No live federated credential exists for the `pull_request` subject. This is exactly
the gap `TODO.md` records as "root cause fixed in code, live verification
pending" — the code fix landed, the Entra app registration was never updated.
Nothing in the factory work touches these workflows; it reproduces on any PR.

Fix (needs Application Administrator):

```bash
az ad app federated-credential create --id <APP_ID> --parameters '{"name":"pr-plan","issuer":"https://token.actions.githubusercontent.com","subject":"repo:saulpatinojr/HCW-Plan_LZDeployment:pull_request","audiences":["api://AzureADTokenExchange"]}'
```

### 6.3 The corpus and `terraform/live/` have diverged

Stage 6 fixed several real defects in the promoted copies (§3.5) without
touching the live tree, so the two now differ. This is deliberate — the live
tree deploys *this* repository, and changing it is a separate reviewable
change — but it will not stay tolerable for long. Stage 13 (regenerating this
repo from the factory) resolves it permanently.

Currently divergent:

| File | Live tree | Corpus |
|---|---|---|
| `live/global/variables.tf` | `org_prefix` validates `^[a-z]{2,4}$` | `^[a-z0-9]{2,10}$`, matching the schema |
| `live/sandbox/variables.tf`, `modules/sandbox/variables.tf` | `location` validates `^[a-z]+$` | `^[a-z0-9]+$` |
| `live/platform-connectivity` | no `firewall_threat_intel_mode` | declared and wired to the module |
| `live/platform-management/main.tf` | literal past `start_time` | derived at plan time |
| `live/workloads-prod/main.tf` | per-layer state container | shared container, keyed by layer |

`Test-LzSchemaDrift` reports a concrete counterexample rather than "these
regexes differ", which is what made the `org_prefix` and `location` cases
actionable in one step.

### 6.4 Guardrails are disabled in GitHub

`main` is protected, but Terraform Apply/Plan, secret scanning, and action pinning
exist in the repo while being turned off in GitHub settings. Relevant when
judging whether a green PR actually means anything.

Concretely, `main` has **no** `required_status_checks`. Every check on a PR is
advisory, so a merge succeeding tells you nothing about whether CI passed. See
the protection table in §1.1 for what *is* enforced.

### 6.5 GitGuardian fails on a public test vector — do not chase it

`factory/tests/Test-Discovery.ps1:85` holds the canonical jwt.io sample token:
header `{"alg":"HS256"}`, payload `{"sub":"1234567890"}`. It exists only to prove
`Protect-LzSecretText` redacts JWT-shaped strings.

**It is not a credential. There is nothing to revoke, and nothing to rotate.**
The line carries an inline comment saying exactly this, and it was reviewed
before merge.

The check will keep failing until someone marks the incident a false positive in
the GitGuardian dashboard — which is a UI action outside the repository, so no
amount of editing here clears it. Do **not** "fix" it by deleting the test or by
splitting the literal so the scanner stops matching: the first removes real
coverage of the redaction path, and the second is evading a security scanner
rather than resolving its finding.

---

## 7. Remaining stages (11–13)

Stage 7 readiness and acceptance criteria are maintained in
[`docs/factory/STAGE-7-READINESS.md`](docs/factory/STAGE-7-READINESS.md).

| Stage | Deliverable |
|---|---|
| 6 | Done — `terraform/` promoted into the template corpus (see §3.5) |
| 7 | Done — generated workflow corpus |
| 8 | Done — generated documentation corpus |
| 9 | Done — non-interactive bootstrap broker, evidence, and user checklists |
| 10 | Done — plan-first scaffold builder, exact inventory, evidence, and publication |
| 11 | Brownfield import generation |
| 12 | Factory CI — run the 283 tests, drift check, and `terraform validate` over the raw corpus |
| 13 | Dogfood instance — regenerate this repo from the factory and prove it applies green |

Stage 9 is the first code path authorized to mutate a tenant and Stage 10 is the
first generated-repository publication path. Neither live path was executed
during implementation.

---

## 8. Environment notes that cost real debugging time

Windows + PowerShell 7.6.4 + Git Bash. These bit during the build:

| Trap | Detail |
|---|---|
| `az.cmd` argument mangling | `&` in a URL is a `cmd` command separator; parentheses in an OData `--filter` break parsing. **Call Graph via `Invoke-RestMethod`, not `az rest`.** |
| `Mandatory [string[]]` | Rejects an array containing *any* empty string — this broke every template with a blank line. Use `[AllowEmptyString()]`. |
| `-is [psobject]` | True for **every** PowerShell value. Use explicit type dispatch (`Test-LzIsComposite`). |
| `$Var:` in a string | Parses as a scope qualifier. Use `${Var}:`. |
| Empty pipeline | Yields `$null`, not `@()`. Wrap in `@(...)` before `.Count` under StrictMode. |
| `-bnot` on `uint32` | Yields a signed value. CIDR maths uses `int64`. |
| Git Bash `/tmp` | Not visible to `pwsh`. Use Windows paths when crossing shells. |
| `git show <ref>:<path>` | MSYS path conversion rewrites the `:` to `;` and the `/` to `\`, so it fails with "unknown revision or path not in the working tree" on a perfectly valid ref. Prefix with `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'`. |
| Console encoding | Set `[Console]::OutputEncoding = [Text.Encoding]::UTF8` or box-drawing glyphs render as `?`. |

Local `az` context was an **expired grant (AADSTS50173)** at handoff — re-run
`az login --tenant <id>` before live discovery. The `resource-graph` extension was
also absent: `az extension add --name resource-graph`.

---

## 9. Repo conventions

- `CLAUDE.md` governs capability routing across the 10 agents in `.claude/agents/`.
  It arrived with [#30](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/30);
  the orchestration layer it routes over arrived earlier with #27. If a previous
  session told you `CLAUDE.md` does not exist, it was reading a branch that
  predates #30 — check `git log --all` before concluding something is missing.
- The capability usage report is now **on** (`.claude/agent-report.json`,
  `enabled: true`). It is a `Stop` hook that counts real `tool_use` blocks out
  of the session transcript rather than estimating, reporting only the segment
  since the last report. Per-session offsets live in
  `.claude/.agent-report-state/` and are gitignored. Toggle it with:

  ```bash
  pwsh -NoProfile -File .claude/hooks/agent-report.ps1 -Mode Toggle -State Off
  ```

- `settings.json` **allows** an agent the ordinary git and GitHub verbs — commit,
  branch, push, and `gh pr create`/`edit`/`merge` (granted by
  [#32](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/32)). It still
  **denies** `terraform apply`/`destroy`/`import`/`state rm|mv`, the `az`
  deletions, `gh workflow run`, and force-push to `main`. **Produce the plan,
  then stop** — applying is the operator's call, and `gh workflow run` is denied
  because it can reach `terraform-apply.yml` by another route.
- **The `git push origin main` deny entries are not the guarantee.** They are a
  fast local failure with a clearer message, and they are not exhaustive —
  `git switch main && git push` would not match the pattern. What actually holds
  is `enforce_admins: true` on the branch protection (§1.1).
- **An agent cannot widen its own permissions.** Editing `.claude/settings.json`,
  and merging a PR that edits it, are both refused. That is deliberate: #32 had
  to be merged by a human. Do not look for a way around it — write the change
  out for the operator instead.
- **Commit a `settings.json` change immediately.** An earlier uncommitted edit to
  it was destroyed by a `git reset --hard` that ran after an `&&`-chained
  `git checkout` had already failed on the dirty tree. Never chain `reset --hard`
  behind a command that can fail on uncommitted work.
- `generated-output/` is gitignored; it holds per-company configs containing
  tenant and subscription IDs.
- PowerShell follows the house style in `scripts/Start-LandingZoneBootstrap.ps1`
  (box headers, `Write-LzOK`/`Warn`/`Fail`).

---

## 10. Pre-Stage 7 review record

A static repository review was completed on 2026-07-25 before preparing Stage 7.
It covered the Stage 1–6 design and implementation, the three test suites, the
renderer manifest and existing workflow proof, all ten live workflows, and the
repo-local orchestration files. After the Stage 8 implementation, all 283 tests
were re-run locally. Representative rendered trees plus the legacy Terraform
tree pass `terraform fmt -check -recursive`.
