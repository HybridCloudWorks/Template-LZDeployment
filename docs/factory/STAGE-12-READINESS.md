# Stage 12 Completion — Factory CI

**Date:** 2026-07-26
**Factory version:** 0.7.0
**Config schema:** 2.0.0
**Manifest version:** 1.7.0

## Scope

Stage 12 implements the credential-free Factory CI gate for changes to factory
source, templates, workflows, scripts, the wizard, and version contracts.

The gate covers:

- wizard Node tests;
- Discovery, Renderer, Bootstrap, Scaffold, Import, and Factory CI PowerShell
  suites;
- schema-to-Terraform variable drift;
- static wizard no-network policy;
- immutable GitHub Action references;
- ShellCheck at error severity;
- PSScriptAnalyzer at error severity;
- Terraform recursive format checks;
- backend-disabled Terraform initialization and validation for every directory
  containing raw corpus HCL.

## Entry points and variables

- `.github/workflows/factory-ci.yml` — pull request, protected-branch push, and
  manual workflow.
- `factory/ci/Invoke-FactoryCI.ps1` — local/CI orchestrator and evidence writer.
- `factory/ci/Test-SiteNoNetwork.ps1` — config-plane network prohibition.
- `factory/ci/Test-ActionPins.ps1` — forty-character action SHA policy.
- `LZ_FACTORY_CI_OUTPUT` — evidence directory.
- `LZ_FACTORY_CI_FAIL_FAST` — stop after the first failed check.
- `LZ_FACTORY_CI_SKIP_TERRAFORM` and `LZ_FACTORY_CI_SKIP_STATIC` — explicit
  exception switches.
- `LZ_FACTORY_CI_TERRAFORM_ROOTS` — comma-separated roots.
- `LZ_PSSCRIPTANALYZER_VERSION` — pinned analyzer version.

## Evidence and status

Every orchestrated run writes per-check logs plus
`factory-ci-report.json`, containing:

- start/end timing;
- check category, status, exit code, duration, and log;
- pass/fail totals;
- skip switches and Terraform roots;
- `externalMutation=false`.

The GitHub workflow uploads that directory even when checks fail. Its stable
status context is `Factory CI / Factory CI`.

## Security and safety

The workflow has `contents: read` only. It does not request OIDC, cloud
credentials, repository administration, HCP tokens, state credentials, or
environment secrets. Terraform initialization always uses `-backend=false`.
There is no Terraform plan, apply, import, destroy, or state command.

All Actions references are full immutable SHAs. Third-party tool versions are
provided by the version contract or explicit repository variables.

## User-owned activities

Enabling Actions, approving allowed actions, maintaining repository variables,
reviewing evidence, resolving failures, configuring the required status
context, and verifying branch protection are recorded in root and generated
`USER-CHECKLIST.md`. These activities do not block Stage 12 code creation or
factory deployment.

## Validation status

Local executable validation was intentionally skipped at the repository
owner's direction because this implementation environment was declared not to
contain the required binaries. The CI workflow, runner, policy checks, and new
static test were authored but not manually executed here.

The required pre-existing `qlty check` remains the publication gate used for
the Stage 12 implementation PR. A future provisioned Factory CI run must
establish the new gate before it is made required.

The last verified local executable baseline remains Stage 8:

- Wizard: 48 passed.
- Discovery: 60 passed.
- Renderer: 175 passed.
- Total: 283 passed.

## Definition of done

- [x] Credential-free SHA-pinned Factory CI workflow implemented.
- [x] Variable-driven fail-closed orchestrator implemented.
- [x] All test suites registered.
- [x] Drift, no-network, and action-pinning policies implemented.
- [x] Shell/PowerShell static analysis implemented.
- [x] Terraform format/init-without-backend/validate implemented.
- [x] Machine-readable report and uploaded evidence implemented.
- [x] Root/generated operator checklists updated.
- [x] Static CI contract coverage authored.
- [x] Versions, handoff, architecture, README, TODO, and changelog reconciled.
- [x] Local executable validation skipped and documented without claiming
  success.

## Next boundary

Stage 13 is the dogfood instance: regenerate the HCW repository from the factory
and prove the real plan/apply path. Factory CI enablement and branch-protection
read-back remain operator activities in `USER-CHECKLIST.md`.
