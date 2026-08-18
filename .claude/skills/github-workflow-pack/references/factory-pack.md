# Factory pack — this repository's own workflows

Seven workflows in `.github/workflows/`. Together they are the factory's
development gate; none of them ship to client repos (the emitted pack does
that). Every one follows the invariants in SKILL.md.

| Workflow | Triggers | Purpose | Notes |
| --- | --- | --- | --- |
| `factory-ci.yml` (Factory CI) | PR + push to `main`, path-filtered (`factory/**`, `site/**`, root `*.ps1`/`*.sh`, `factory-version.json`, itself); dispatch | The whole local validation corpus on a runner: wizard node tests, all PowerShell suites, schema-drift, template coverage, action-pinning, provider constraints, PSScriptAnalyzer (pinned version), terraform fmt/init/validate over `factory/templates/terraform` | The **required check** for branch protection. Repo variables `LZ_FACTORY_CI_*` tune output dir, fail-fast, skips, terraform roots — keep `LZ_FACTORY_CI_TERRAFORM_ROOTS` in sync when trees move |
| `e2e-generation-proof.yml` (E2E Generation Proof) | PR + push, path-filtered (`site/**`, `factory/**`, `factory-version.json`, itself); dispatch | The release-evidence source that replaced the dogfood apply (ADR 0013): drives the real wizard headlessly (Playwright), renders, runs V01–V08, evaluates the six proofs — including re-verifying every AVM pin via `terraform init` with real registry access | Matrix over both topologies (`hub-spoke`, `virtual-wan`), `fail-fast: false`. Evidence retention 90 days |
| `secrets-scan.yml` (Secret Scanning & Security) | PR (diff-only scan), push to `main` (full history), **weekly cron Mon 02:00 UTC**, dispatch | TruffleHog OSS with `--only-verified` — fails only on live, verified credentials | This is a normal Actions job, not the paid GitHub Secret Protection product. The cron fires on its own once the workflow is enabled |
| `action-pinning-policy.yml` (Action Pinning Policy) | PR + push, path-filtered (workflows, workflow templates, `factory/ci/Test-ActionPins.ps1`) | Runs the canonical-SHA registry check over both packs | The registry and this workflow move together — a Dependabot bump that outruns the registry turns this red (see the trufflehog v3.97.0 incident, PR #101) |
| `terraform-policy-checks.yml` (Terraform Policy Checks) | PR + push, path-filtered (`factory/**`, itself) | Renders both topology fixtures and runs `init`/`validate` on the **rendered output** — execution-time proof the emitted Terraform is coherent | Rewritten during the generator-only refactor; disabled 2026-06-28 → re-enabled 2026-08-17, so watch its first modern run |
| `deploy-pages.yml` (Deploy Wizard to GitHub Pages) | push to `main` (site paths), dispatch | Publishes `site/` (and `frontend/`) via the Pages Actions flow | Needs the one-time Pages-source-to-Actions repo setting |
| `release-readiness.yml` (Release Readiness) | dispatch | Stage 14: hash-binds Factory CI + e2e evidence to a promotion proposal | Never flips release gates itself — that is the separately reviewed release-gate PR |

## Division of labor to preserve

- **Factory CI** is breadth: every suite, every static check, no cloud, no
  registry dependency beyond provider downloads for template dirs.
- **E2E proof** is depth: one true end-to-end path with real registry access,
  producing release evidence.
- **Policy checks** duplicates the render+init/validate slice of the e2e
  proof *without* the browser layer — cheap re-verification on every
  `factory/**` change.

A new factory-side check belongs inside `Invoke-FactoryCI.ps1` (so it runs
locally and in CI identically), not as a new workflow — add a workflow only
for a genuinely different trigger shape (schedule, deployment, dispatch-only
mutation).

## Dynamic workflows you will see but do not own

`Dependabot Updates`, `CodeQL`, Copilot agents, and `GitHub Advanced
Security` appear in the Actions API with `dynamic/` paths. They are
platform-managed; there is no YAML to standardize. Their side effects DO
intersect the pack: Dependabot bumps action SHAs, so every Dependabot
workflow PR must be checked against the pinning registry before merge.
