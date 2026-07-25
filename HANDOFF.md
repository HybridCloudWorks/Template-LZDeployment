# Landing Zone Factory — Session Handoff

**Last updated:** 2026-07-25 · **Factory version:** 0.1.0 · **Config schema:** 1.0.0
**Progress:** Stages 1–5 of 13 complete. Stage 6 is next.

You are continuing a multi-session build. This document is the single source of
truth for where the work stopped. Read the *Next steps* section first, then
*Verify you're in the right state* before changing anything.

---

## 1. NEXT STEPS — start here

### 1.1 Immediate: land the open PRs

Two PRs are open and stacked. Nothing is on `main` yet.

| PR | Branch | Contains | Base |
|---|---|---|---|
| [#28](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/pull/28) | `feat/lz-factory-config-plane-and-engines` | Stages 1–5 (36 files) | `main` |
| this one | `docs/factory-handoff-and-tests` | This doc + the 205-test suite | `feat/lz-factory-…` |

Merge the stacked PR into `feat/lz-factory-…` first, then #28 into `main` — or
merge #28 first and retarget this one to `main`. Either order works.

### 1.2 Then: Stage 6 — promote the real Terraform into the template corpus

This is the next build stage and the highest-value work remaining.

**Goal:** move `terraform/` into `factory/templates/terraform/` as tokenised
templates, so generated repositories carry the actual module corpus rather than
the current proof set.

**Concretely:**

1. For each layer in `terraform/live/` — `platform-connectivity`,
   `platform-management`, `workloads-prod`, plus `platform-identity` and
   `sandbox` if kept — copy `variables.tf` into
   `factory/templates/terraform/live/<layer>/variables.tf` with
   **`mode: "copy"`** in the manifest. Never templatise a `variables.tf`; it is
   the contract the drift check validates against.
2. Write a `terraform.auto.tfvars.tmpl` per layer, following the two that already
   exist as worked examples (`global`, `platform-connectivity`).
3. Add each layer to `factory/renderer/variable-map.json` under `layers`, and
   remove it from `$pendingLayers.pending`. That list exists precisely so the
   coverage gap stays visible — keep it honest.
4. Copy `terraform/modules/**` into the corpus. Modules are mostly static; expect
   `mode: "copy"` for nearly all of them.
5. Register everything in `factory/renderer/template-manifest.json`.
6. Run the drift check until clean, then the full suite:

```bash
pwsh -NoProfile -Command "Import-Module ./factory/renderer/LZFactory.Renderer.psd1 -Force; Test-LzSchemaDrift -SchemaPath ./factory/schema/lz-config.schema.json -MappingPath ./factory/renderer/variable-map.json -TemplateRoot ./factory/templates | Format-List"
```

**Expect drift findings on the first run — that is the point.** The wizard exposes
options that the Terraform corpus may not implement. Each finding is a real
decision: implement the variable, or remove the wizard option. Do not silence
them by deleting map entries.

### 1.3 Known work queued behind stage 6

| Priority | Item | Why |
|---|---|---|
| High | `terraform fmt -recursive terraform/` | 26 files fail the repo's own fmt gate — see §6.1 |
| High | Add federated credential for `pull_request` subject | Unblocks all CI — see §6.2 |
| Medium | Wire the 205 tests into a CI workflow | They only run locally today |
| Medium | Reconcile `org_prefix` in `terraform/live/global/variables.tf` | Still `^[a-z]{2,4}$` — see §6.3 |
| Later | Stages 7–13 | See §7 |

---

## 2. Verify you're in the right state

Run this first. If it disagrees with the table below, stop and reconcile before
building anything.

```bash
git branch -vv && git log --oneline -3 && git status --short
```

Expected at handoff time:

| | |
|---|---|
| Branches | `main` (ahead of origin by 1), `feat/lz-factory-config-plane-and-engines`, `docs/factory-handoff-and-tests` |
| `main` HEAD | `655e268` — **1 commit ahead of `origin/main`, unpushed** |
| Feature HEAD | `4561df7` |
| Working tree | clean |

> **`main` is 1 commit ahead of `origin/main`.** A direct push to `main` was
> attempted earlier and **denied by the permission layer**. That commit is
> preserved on the PR branch, so once #28 merges you can safely run
> `git checkout main && git reset --hard origin/main`. Do not force-push `main`.

Sanity check that the toolchain works:

```bash
pwsh -NoProfile -Command "Import-Module ./factory/renderer/LZFactory.Renderer.psd1 -Force; Import-Module ./factory/discovery/LZFactory.Discovery.psd1 -Force; 'both modules loaded'"
```

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

---

## 4. Tests — 205, all green

**These were rescued into the repo by this PR.** They previously existed only in
a session-scoped temp directory and would have been lost permanently.

```bash
cd factory/tests
node test.js                                  # 48 — wizard logic
pwsh -NoProfile -File ./Test-Discovery.ps1    # 60 — discovery engine
pwsh -NoProfile -File ./Test-Renderer.ps1     # 97 — renderer
```

Paths resolve from `$PSScriptRoot`/`__dirname`, so they run from any checkout and
any working directory. Generated output goes to `factory/tests/.out/`
(gitignored). Fixtures live in `factory/tests/fixtures/`.

**They are not wired into CI yet** — see §1.3.

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

### 6.3 `org_prefix` constraint mismatch in the live layer

`terraform/live/global/variables.tf` still validates `^[a-z]{2,4}$`, rejecting any
org prefix longer than 4 characters. The **template corpus copy** was aligned to
the schema (`^[a-z0-9]{2,10}$`) with the storage-account-length reasoning
documented inline; the live layer was not touched.

This was found by `Test-LzSchemaDrift`, which reports a concrete counterexample
rather than "these regexes differ". Re-running it after stage 6 will surface any
similar conflicts in the newly promoted layers.

### 6.4 Guardrails are disabled in GitHub

`main` is protected, but Terraform Apply/Plan, secret scanning, and action pinning
exist in the repo while being turned off in GitHub settings. Relevant when
judging whether a green PR actually means anything.

---

## 7. Remaining stages (7–13)

| Stage | Deliverable |
|---|---|
| 6 | **Next.** Promote `terraform/` into the template corpus |
| 7 | Promote `.github/workflows/` into the corpus |
| 8 | Documentation templates: operating model, governance, threat model, observability, FinOps, state management, DR, upgrade guide, phase model |
| 9 | **Bootstrap broker** — creates Entra apps, federated credentials, GitHub environments, secrets. Consumes `discovery-inventory.json`. The first stage that *writes* anything. |
| 10 | **Scaffold builder** — moves a rendered tree into a real repository |
| 11 | Brownfield import generation |
| 12 | Factory CI — run the 205 tests, drift check, and `terraform validate` over the raw corpus |
| 13 | Dogfood instance — regenerate this repo from the factory and prove it applies green |

Stages 1–5 wrote **nothing** outside the repo. Stage 9 is the first that mutates
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
| Console encoding | Set `[Console]::OutputEncoding = [Text.Encoding]::UTF8` or box-drawing glyphs render as `?`. |

Local `az` context was an **expired grant (AADSTS50173)** at handoff — re-run
`az login --tenant <id>` before live discovery. The `resource-graph` extension was
also absent: `az extension add --name resource-graph`.

---

## 9. Repo conventions

- `CLAUDE.md` governs capability routing. Usage reporting is **off** by default
  (`.claude/agent-report.json`).
- `settings.json` denies `terraform apply`/`destroy`/`state rm|mv`, `az` deletion,
  `gh workflow run`, `gh pr merge`, and force-push to `main`. **Produce the plan,
  then stop** — applying is the operator's call.
- `generated-output/` is gitignored; it holds per-company configs containing
  tenant and subscription IDs.
- PowerShell follows the house style in `scripts/Start-LandingZoneBootstrap.ps1`
  (box headers, `Write-LzOK`/`Warn`/`Fail`).
