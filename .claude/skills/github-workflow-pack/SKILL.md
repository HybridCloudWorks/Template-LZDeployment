---
name: github-workflow-pack
description: The standardized GitHub Actions workflow packs for this repository and the repositories it generates, plus the invariants that make every setup identical. Use this whenever creating, copying, reviewing, or re-standardizing a workflow — adding a new .yml or .yml.tmpl, standing up CI in a new or generated repo, wiring OIDC/azure-login, pinning or bumping an action, fixing a permissions or id-token finding, re-enabling disabled workflows, or answering "which workflows should this repo have". Also use it when a request merely implies workflow setup ("set up CI like the factory", "make the new repo match", "why is this check missing").
---

# GitHub Workflow Pack

This repository maintains **two** standardized workflow packs. Never invent a
new workflow shape when a pack member already covers the job — copy the
canonical file and adapt the minimum.

| Pack | Lives in | Deployed to | Canonical source |
| --- | --- | --- | --- |
| **Factory pack** | `.github/workflows/` | this repository | the files themselves |
| **Emitted pack** | `factory/templates/.github/workflows/*.tmpl` | every generated client repo | the templates + `factory/renderer/template-manifest.json` |

Per-workflow specs, triggers, and the reason each exists:
- Read [references/factory-pack.md](references/factory-pack.md) when working on this repo's own CI.
- Read [references/emitted-pack.md](references/emitted-pack.md) when working on the templates a client repo receives.

The canonical files are the truth; these references are the map. When they
disagree, the file wins — then fix the reference in the same change.

## The invariants — every workflow, both packs, no exceptions

These are enforced by CI (`Test-ActionPins.ps1`, `Test-CI.ps1`, e2e gate (d),
V05), so a workflow that skips one does not merge. Apply them at authoring
time rather than discovering them in a red check.

1. **SHA-pin every action.** `uses: owner/action@<40-hex-sha> # vX.Y.Z`.
   The canonical SHA registry is `factory/ci/Test-ActionPins.ps1` — a new or
   bumped action goes into that registry **in the same change**, and the SHA
   is verified against the upstream repo first:
   `git ls-remote https://github.com/<owner>/<action> refs/tags/<tag>`.
   Never trust a SHA from a Dependabot diff, a blog post, or memory — the
   registry exists precisely because a wrong SHA is invisible in review.
2. **Least-privilege permissions, declared explicitly.** Top level is
   `permissions: {}` (dispatch/apply workflows) or `contents: read` (CI).
   `id-token: write` appears **only** on jobs that run `azure/login`, at job
   level. A credential-free workflow carrying `id-token: write` is a
   finding, not a convenience — the e2e proof fails on it in either
   direction.
3. **OIDC only — no long-lived cloud secrets.** Azure auth is
   `azure/login` with a client ID from repository/environment variables,
   never a stored credential. Plan and apply use **different identities**;
   the apply subject is pinned to `environment:<name>` so only a protected
   environment's reviewer gate can mint it (a `repo:owner/repo:*` wildcard
   subject would let any branch assume apply).
4. **Concurrency groups on everything.** CI: keyed by ref,
   `cancel-in-progress: true`. Applies and one-shot mutations: keyed by
   operation, `cancel-in-progress: false` — never cancel a mutation mid-run.
5. **Path-filter the triggers** to exactly what the workflow validates, and
   keep the filter in sync when the validated tree moves (a deleted root
   left in a filter env/paths list is a real past failure — see the
   factory-ci `LZ_FACTORY_CI_TERRAFORM_ROOTS` history).
6. **Evidence artifacts, `if: always()`.** Every gate uploads its report
   even on failure (`if-no-files-found: error`), with a stated
   `retention-days`. A gate whose evidence vanishes on failure cannot be
   audited.
7. **Pinned toolchain.** `setup-terraform` takes the version from
   `factory-version.json` `toolchain.terraform.tested` (templates render it
   via `{{FACTORY-RAW:computed.terraformVersion}}`) and always sets
   `terraform_wrapper: false` — the wrapper corrupts redirected
   `terraform show -json` output.
8. **Mutations are dispatch-only and guarded.** Anything that changes cloud
   or repo state: `workflow_dispatch` with a protected `environment:`, an
   input validated before any credential is issued (unknown-layer reject,
   layer→environment binding, type-the-name confirmation), and a
   destructive-change refusal (plan-JSON destroy count) before apply. Merging
   to `main` never deploys.
9. **Self-contained emitted workflows** (decision 0016): a generated repo's
   workflows reference nothing in the factory — no reusable workflows, no
   factory URLs. The client repo must work after the factory copy is
   deleted.

## Creating or changing a workflow — the procedure

1. Pick the closest pack member from the relevant reference file and copy
   its file. State which one you started from in the PR.
2. Adapt triggers/paths/steps; hold every invariant above.
3. New or bumped action → verify the tag SHA upstream → add/update the
   `Test-ActionPins.ps1` registry entry with a comment naming the
   verification.
4. Emitted-pack changes additionally need: a `template-manifest.json` entry
   (with a `when:` condition if conditional), and — if the workflow consumes
   config values — tokens resolved by the renderer, never hand-substituted.
5. Run the checks the change touches before pushing:
   `pwsh -File factory/ci/Test-ActionPins.ps1`, `pwsh -File
   factory/tests/Test-CI.ps1`, and for emitted templates the renderer suite
   `pwsh -File factory/tests/Test-Renderer.ps1`.

## Repo setup checklist (same every time)

**Generated client repos — the broker owns this; do not do it by hand.**
`factory/bootstrap/LZFactory.Bootstrap.psm1` creates branch protection,
required checks, environments with reviewers, variables, and reads every
setting back for the audit record. If a generated repo is set up manually,
that is a bug to fix in the broker, not a procedure to document.

**This repository (the factory) — operator actions, in order:**

1. Workflows land via PR; Factory CI + E2E Generation Proof must be green.
2. Check the Actions tab for `disabled_manually` state — a workflow disabled
   in the UI **stays disabled across pushes** and silently never runs; the
   enable button is on the workflow's own page in the Actions tab, one per
   workflow (not in Settings).
3. Branch protection on `main`: apply
   `docs/runbooks/branch-protection-payload.json` (required checks:
   `Factory CI`; add `azure/login`-dependent contexts only once the
   identity estate exists — TODO item 4.2).
4. Pages source = "GitHub Actions" (for `deploy-pages.yml`).
5. Costs: this repo is public, so Actions minutes are free; the secret-scan
   workflow is TruffleHog OSS in a normal job, **not** the paid GitHub
   Secret Protection product. If the repo ever goes private, both statements
   change — re-check before enabling schedules.

**Traps that recur:**
- Scheduled workflows auto-disable after 60 days without repo activity.
- Draft→ready conversion drops auto-merge/queue membership.
- A workflow renamed or moved keeps its numeric ID but breaks
  `required_status_checks` contexts, which match by **name**.
