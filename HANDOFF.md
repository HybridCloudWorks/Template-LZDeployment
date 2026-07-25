# Landing Zone Factory — Session Handoff

**Last updated:** 2026-07-25 · **Factory version:** 0.1.0 · **Config schema:** 1.0.0
**Progress:** Stages 1–6 of 13 complete. Stage 7 is next.
**First action:** merge the three open PRs — see §1.1. Nothing is on `main` yet.

You are continuing a multi-session build. This document is the single source of
truth for where the work stopped. Read the *Next steps* section first, then
*Verify you're in the right state* before changing anything.

---

## 1. NEXT STEPS — start here

### 1.1 Immediate: land the three open PRs

**Everything built so far is on branches. `main` still has none of it.** All
three PRs report `MERGEABLE`. Merging them is the first thing to do.

| PR | Branch | Contains | Base |
|---|---|---|---|
| [#30](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/30) | `chore/claude-capability-routing-clean` | `CLAUDE.md`, the agent-report hook | `main` |
| [#28](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/28) | `feat/lz-factory-config-plane-and-engines` | Stages 1–5 (36 files) | `main` |
| [#31](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/31) | `docs/factory-handoff-and-tests` | This doc, the test suite, **and stage 6** | `feat/lz-factory-…` |

Merge in this order — #31 is stacked on #28, so #28 must land first or #31 has
to be retargeted:

```bash
gh pr merge 30 --squash --delete-branch
gh pr merge 28 --merge
gh pr merge 31 --merge
```

Then reset the stale local `main`:

```bash
git checkout main && git fetch origin && git reset --hard origin/main
```

Three things that will otherwise waste your time:

- **`settings.json` denies `gh pr merge` and `git push origin main`.** An agent
  cannot run the commands above; a human has to. This is deliberate — see §9.
- **All three PRs show `mergeStateStatus: UNSTABLE`.** That is the pre-existing
  red CI from §6.2, not a merge blocker. No required check is failing, because
  the guardrails are switched off in GitHub (§6.4). A green tick here would not
  mean much either way.
- **Local `main` is 1 commit ahead of `origin/main`** (`655e268`). A direct push
  to `main` was attempted in an earlier session and denied. That commit is
  preserved inside #28, so the `reset --hard` above loses nothing. **Do not
  force-push `main`.**

#31 already contains #30's commit by a real merge rather than a cherry-pick, so
the SHA is shared and the two cannot conflict — merging both is safe in any
order.

### 1.2 Then: Stage 7 — promote `.github/workflows/` into the corpus

Stage 6 is done (see §3.5). Stage 7 is the same exercise for the pipeline:
`.github/workflows/` becomes templates so a generated repository ships its own
plan/apply workflows rather than the single proof workflow that exists today.

The identity decision in §5 is the constraint that governs it: a
`pull_request`-triggered job may only ever assume the Reader `*-plan` identity,
and an apply job may only ever be reached through `environment:<name>`. No
subject uses a wildcard, and the tests assert that.

### 1.3 The one decision stage 6 surfaced and did not make

**The wizard offers non-prod application environments that the Terraform corpus
cannot build.** `Get-LzActiveLayers` selects `workloads-nonprod` whenever `dev`,
`test`, or `uat` is chosen, and `platform-identity` whenever an identity
subscription is supplied — but neither layer exists under `terraform/live/`, so
there is nothing to promote.

Before stage 6 this produced a layer directory containing only `backend.tf`:
`terraform init` succeeded, `terraform plan` reported no changes, and the
operator would reasonably read that as "this layer has nothing to do" rather
than "this layer does not exist". **Guard G21 now refuses the render instead.**

Resolving it properly needs a schema change, which is why it was not done
silently: the corpus has `connectivity.hubSpoke.primarySpokeAddressSpace` and
`drSpokeAddressSpace` and nothing else, so there is no address space to give a
non-prod spoke. The options are:

- add per-environment spoke CIDRs to the schema (a `configSchemaVersion` bump)
  and author `workloads-nonprod` against them; or
- remove non-prod application environments from the wizard.

`factory/tests/fixtures/nonprod-config.json` exercises the refusal.

### 1.4 Known work queued behind stage 7

| Priority | Item | Why |
|---|---|---|
| High | Decide the non-prod workload layer question | See §1.3 — most real configurations hit it |
| High | `terraform fmt -recursive terraform/` | 26 files fail the repo's own fmt gate — see §6.1 |
| High | Add federated credential for `pull_request` subject | Unblocks all CI — see §6.2 |
| Medium | Wire the 208 tests into a CI workflow | They only run locally today |
| Medium | Backport the stage-6 fixes to `terraform/live/` | The corpus and the live tree have diverged — see §6.3 |
| Later | Stages 8–13 | See §7 |

---

## 2. Verify you're in the right state

Run this first. If it disagrees with the table below, stop and reconcile before
building anything.

```bash
git branch -vv && git log --oneline -3 && git status --short
```

Expected at handoff time — **before** the §1.1 merges:

| | |
|---|---|
| Current branch | `docs/factory-handoff-and-tests`, in sync with its remote |
| Its HEAD | `5b41af4` — turn the capability usage report on |
| | `6345207` — merge `chore/claude-capability-routing-clean` |
| | `ce8760f` — stage 6, the Terraform corpus |
| | `d0806ea` — handoff + test suites |
| `main` HEAD | `655e268` — **1 commit ahead of `origin/main`, unpushed**; see §1.1 |
| Working tree | clean |

If you are reading this *after* the merges, expect `origin/main` to contain all
four commits above and the three PR branches to be gone.

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

`factory/templates/terraform/` now carries five live layers and the whole module
corpus, so a generated repository is deployable rather than illustrative.

| Layer | Emitted when | Form |
|---|---|---|
| `global` | always | `main.tf`/`outputs.tf` copied; tfvars rendered |
| `platform-connectivity` | `connectivity.model != 'none'` | rendered — DR hub and hub-to-hub peering are conditional |
| `platform-management` | always | rendered — backup and sandbox-cleanup sections are independently conditional |
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

## 4. Tests — 208, all green

**These were rescued into the repo by [#31](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/31).**
They previously existed only in a session-scoped temp directory and would have
been lost permanently. Until that PR merges they exist on one branch only —
which is a further reason not to leave §1.1 sitting.

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
| **Renderer re-validates independently of the wizard** | A validation that exists only in the UI is a suggestion, not a guarantee. 20 guards (G01–G20). |

---

## 6. Open problems

### 6.1 26 Terraform files fail the repo's own fmt gate — pre-existing

`.github/workflows/terraform-plan.yml:150` runs `terraform fmt -check -recursive`.
It fails today on every PR touching Terraform, and plausibly contributes to the
"no recorded successful run" in `TODO.md`.

```bash
terraform fmt -recursive terraform/
```

Left unfixed because it touches 26 files unrelated to the factory work.

### 6.2 CI is red on all PRs — pre-existing, blocks everything

`RBAC Audit & Validation` and `RBAC Compliance Checks` both fail at Azure login:

```
AADSTS700213: No matching federated identity record found for presented
assertion subject 'repo:saulpatinojr/HCW-Plan_LZDeployment:pull_request'
```

No federated credential exists for the `pull_request` subject. This is exactly
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

---

## 7. Remaining stages (7–13)

| Stage | Deliverable |
|---|---|
| 6 | Done — `terraform/` promoted into the template corpus (see §3.5) |
| 7 | **Next.** Promote `.github/workflows/` into the corpus |
| 8 | Documentation templates: operating model, governance, threat model, observability, FinOps, state management, DR, upgrade guide, phase model |
| 9 | **Bootstrap broker** — creates Entra apps, federated credentials, GitHub environments, secrets. Consumes `discovery-inventory.json`. The first stage that *writes* anything. |
| 10 | **Scaffold builder** — moves a rendered tree into a real repository |
| 11 | Brownfield import generation |
| 12 | Factory CI — run the 208 tests, drift check, and `terraform validate` over the raw corpus |
| 13 | Dogfood instance — regenerate this repo from the factory and prove it applies green |

Stages 1–6 wrote **nothing** outside the repo. Stage 9 is the first that mutates
a tenant; treat that boundary carefully.

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

- `settings.json` denies `terraform apply`/`destroy`/`state rm|mv`, `az` deletion,
  `gh workflow run`, `gh pr merge`, and force-push to `main`. **Produce the plan,
  then stop** — applying is the operator's call. The `gh pr merge` denial is why
  §1.1 asks a human to run the merges; do not try to route around it.
- `generated-output/` is gitignored; it holds per-company configs containing
  tenant and subscription IDs.
- PowerShell follows the house style in `scripts/Start-LandingZoneBootstrap.ps1`
  (box headers, `Write-LzOK`/`Warn`/`Fail`).
