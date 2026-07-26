# Stage 9 Completion — Bootstrap Broker

**Date:** 2026-07-26  
**Factory version:** 0.4.0  
**Config schema:** 2.0.0  
**Manifest version:** 1.4.0

## Scope

Stage 9 implements the first factory component authorized to mutate external
systems. The broker consumes `lz-config.json` and
`discovery-inventory.json`, emits deterministic plan/audit evidence, and
reconciles:

- Entra applications and service principals;
- exact GitHub OIDC federated credentials;
- least-privilege Azure RBAC assignments;
- GitHub environments and deployment-protection reviewers;
- repository/environment Actions variables and HCP token secret;
- required default-branch protection;
- HCP Terraform workspaces or Azure Storage backend prerequisites.

## Entry points

- `bootstrap-broker.ps1` — canonical PowerShell entry point.
- `bootstrap-broker.sh` — strict Bash launcher for PowerShell.
- `factory/bootstrap/LZFactory.Bootstrap.psm1` — idempotent broker functions.
- `USER-CHECKLIST.md` — factory-operator activities.
- generated `USER-CHECKLIST.md` — customer-specific activities.

## Safety model

- Plan-only is the default. Mutation requires `-Apply` or
  `LZ_BOOTSTRAP_APPLY=true`.
- No command prompts for tenant-specific values.
- Config/discovery files and environment variables are the only input channels.
- Discovery must assert `readOnly=true`.
- Blocking discovery findings stop apply unless an explicit
  `-AllowNotReady`/`LZ_BOOTSTRAP_ALLOW_NOT_READY=true` exception is supplied.
- Plan identities receive Reader. Workload apply identities receive Contributor
  at the declared subscription scope; bootstrap apply receives only management
  group and policy contributor roles at the configured root.
- OIDC subjects are exact `pull_request` or `environment:<name>` values; no
  wildcard subjects are generated.
- Plan workflows select per-layer client/subscription mappings.
- `TFE_TOKEN` is read from the environment, stored only as a GitHub Actions
  secret, and never written to plan/audit artifacts.
- Every run emits `bootstrap-plan.json` and `bootstrap-audit.json`.

## User-owned activities

All authentication, token provisioning, approval, exception, and live
verification activities are recorded in `USER-CHECKLIST.md` and the generated
customer checklist. Missing user activity does not prevent code generation or
repository publication. Runtime apply reports pending HCP activity in
`bootstrap-audit.json` when `TFE_TOKEN` is absent.

## Validation status

Executable validation was intentionally skipped at the repository owner's
direction because the implementation environment was declared not to contain
the required external binaries/authenticated services. No broker apply was run,
and no Azure, Entra, GitHub administration, HCP Terraform, or backend mutation
was attempted.

Static test coverage was authored in `factory/tests/Test-Bootstrap.ps1` and
Stage 9 renderer assertions were added to `factory/tests/Test-Renderer.ps1`,
but neither new executable path is claimed as run in this stage.

The last verified baseline remains Stage 8:

- Wizard: 48 passed.
- Discovery: 60 passed.
- Renderer: 175 passed.
- Total: 283 passed.

## Definition of done

- [x] Plan-only, non-interactive broker entry points implemented.
- [x] Config and discovery contracts consumed.
- [x] Entra app/SP/FIC/RBAC reconciliation implemented.
- [x] GitHub environments, variables, secrets, and protection implemented.
- [x] HCP and Azure Storage backend reconciliation implemented.
- [x] Per-layer plan identity/subscription workflow integration implemented.
- [x] Plan and audit evidence implemented.
- [x] Factory and generated user checklists implemented.
- [x] Static test coverage authored.
- [x] Version, manifest, handoff, architecture, README, TODO, and changelog
  reconciled.
- [x] Executable validation skipped and documented without claiming success.

## Next boundary

Stage 10 is the scaffold builder. It creates or updates a target repository from
the renderer output and must preserve the manifest exactly. Live Stage 9 apply
and verification remain operator activities in `USER-CHECKLIST.md`.
