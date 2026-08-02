# Decision 0002 — Minimal-by-default CI/CD identity estate

**Date**: 2026-08-02
**Status**: Accepted
**Context**: PROD-TODO Phase 2 (identity estate creation); operator directive
2026-08-01 (minimal by default, scale is the client's choice); design
authority: `azure-platform-architect`, 2026-08-01

## Context

The legacy bootstrap created a layers × environments matrix —
`sp-terraform-{main,dev,prod}-{dev,prod}-<prefix>` plus
`sp-terraform-plan-ci-<prefix>`, seven identities in total. The architect
review found:

- **4 of the 7 were never wired to any workflow secret**
  (`sp-terraform-dev-dev`, `sp-terraform-dev-prod`, `sp-terraform-prod-dev`,
  `sp-terraform-main-dev`) — dead weight with live credentials.
- The grants were simultaneously **excessive** — subscription-scope RBAC
  Administrator on the dev-*/prod-* layer SPs that nothing needed — and
  **insufficient** — no management-group-root grants, which the
  `management-groups`/`policy-baseline` modules require, so the global layer
  could never have applied as the legacy SP.

## Decision

CI/CD identities default to the **minimal model**: 2 Entra identities total,
selected by the new broker-only schema key `identity.cicdIdentityModel`
(enum `minimal|per-environment`, default `minimal`; like `github.*` it is
deliberately absent from `factory/renderer/variable-map.json` and never
reaches a Terraform variable).

- **Plan identity** (shared, read-only): Reader at the management-group root;
  plus Storage Blob Data Reader on the state storage account when the backend
  is azurerm. Subjects: `pull_request` (broker path); the legacy bootstrap
  additionally binds `ref:refs/heads/main`, since this repo's read-only
  push-triggered jobs authenticate as the plan identity.
- **Apply identity** (shared): Management Group Contributor + Resource Policy
  Contributor at the MG root, Contributor per distinct subscription (union of
  scopes, deduplicated), plus Storage Blob Data Contributor on the state
  account for azurerm. Subjects: one `environment:<name>` federated
  credential per unique environment — **only** environment subjects, so it
  still cannot be assumed from a branch or pull request.
- RBAC Administrator is granted **only** when the sandbox is selected, scoped
  to the sandbox subscription, and constrained by an ABAC delegation
  condition (may only assign role = Contributor to
  principalType = ServicePrincipal, condition-version 2.0).

**`per-environment` is the explicit scale-out tier**: a plan/apply pair per
unique environment (2 × N). The broker's per-environment output is proven
byte-parity with its prior output
(`factory/tests/fixtures/bootstrap-plan-per-environment.expected.json`), so
existing estates re-run idempotently.

The wizard asks "Deployment identity model" and shows a live count ("This
will create N Entra identities") computed from the environment selections.

## Consequences

- **Shared apply identity trade-off**: one principal holds Contributor across
  every workload subscription. Compensating controls: each
  `environment:<name>` OIDC subject can only be minted through its protected
  GitHub environment gate (per-layer approval), and destructive plans remain
  behind the `approved-destroy` control. Clients that want per-environment
  blast-radius isolation choose `per-environment` in the wizard.
- **The CHANGELOG decision "Two identities per environment" is preserved, not
  silently revisited**: it lives on as the `per-environment` tier, byte-parity
  tested. The 2026-08-01 operator directive changes only the default.
- Legacy-matrix estates are never mutated: the bootstrap detects them and
  emits a report-only remediation section (delete the 4 dead apps, remove the
  subscription-scope RBAC Administrator grants, add the missing MG-root
  grants) as operator-run `az` commands.
- Secret names are unchanged (`AZURE_CLIENT_ID`, `AZURE_PLAN_CLIENT_ID`), so
  workflows and generated repos need no renames.
